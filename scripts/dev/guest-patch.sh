#!/bin/bash
# Author guest-build patches from a running SavantOS dev VM.
#
# Captures files from the live guest (mode/symlink-preserving tar over SSH),
# stages them in a scratch tree, and emits the next numbered mailbox patch
# for guest-build/ — the format scripts/release/build-guest.sh consumes with
# `git am` (line 59) against the builder commit pinned in source.lock.json.
#
# Guest content reaches the factory image via the builder's overlay mapping:
#   <absolute path in the guest>  ->  guest/factory-overlay/<absolute path>
# e.g. /usr/local/bin/tool -> guest/factory-overlay/usr/local/bin/tool
#
# Subcommands: stage | list | commit | clean | help
# See "Patch authoring" in scripts/dev/README.md for the workflow.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GB="$REPO/guest-build"
LOCK="$GB/source.lock.json"
SSH_PORT="${SAVANTOS_DEV_PORT:-2222}"
GUEST_USER="savant"
STAGE="${SAVANTOS_PATCH_STAGE:-${TMPDIR:-/tmp}/savantos-guest-patch-stage}"
AUTHOR="${SAVANTOS_PATCH_AUTHOR:-}"

usage() {
  cat <<'EOF'
guest-patch.sh — snapshot live guest changes into the next guest-build patch

  stage <guest-path>...   capture file(s) from the running dev VM into the
                          staging tree (modes/symlinks preserved)
  list                    show staged files
  commit <subject>        emit the next numbered patch from staged files
       [--modify]         modify mode: staged files replace existing builder
                          files (diff against the pinned builder commit);
                          default is add mode (new files only)
       [--author "Name <email>"]   override patch author
  clean                   discard the staging tree

Examples:
  scripts/dev/guest-patch.sh stage /usr/local/bin/newtool
  scripts/dev/guest-patch.sh commit "Ship the newtool stub"
  scripts/dev/guest-patch.sh stage /usr/local/bin/clipboard-bridge
  scripts/dev/guest-patch.sh commit --modify "Tune the clipboard bridge"

The patch lands in guest-build/ as 00NN-<Subject>.patch with a provenance
header (builder commit, SavantOS source, factory image, captured paths).
Prove it in a scratch checkout with scripts/release/build-guest.sh
--contract-only before opening a PR. Only stage files that are your
intended content — never runtime-mutated state (/etc machine state, logs):
that belongs to the writable disk, not the factory overlay.
EOF
}

need_vm() {
  if ! ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
      -p "$SSH_PORT" "$GUEST_USER@127.0.0.1" true 2>/dev/null; then
    echo "error: dev VM not reachable on 127.0.0.1:${SSH_PORT} — boot it first:" >&2
    echo "       scripts/dev/dev-vm.sh boot" >&2
    exit 1
  fi
}

builder_field() { python -c "import json,sys; print(json.load(open(sys.argv[1]))['$1'])" "$LOCK"; }

capture() { # capture <guest-abs-path>... -> $STAGE/<guest-abs-path>
  mkdir -p "$STAGE"
  ssh -o StrictHostKeyChecking=accept-new -p "$SSH_PORT" \
    "$GUEST_USER@127.0.0.1" "tar -C / -cf - -- $*" | tar -xf - -C "$STAGE"
}

cmd_stage() {
  [[ $# -gt 0 ]] || { echo "error: stage needs at least one guest path" >&2; exit 2; }
  need_vm
  for p in "$@"; do
    [[ "$p" == /* ]] || { echo "error: paths must be absolute: $p" >&2; exit 2; }
  done
  capture "$@"
  for p in "$@"; do
    [[ -e "$STAGE$p" ]] || { echo "error: guest path not captured: $p" >&2; exit 1; }
    echo "[guest-patch] staged: $p"
  done
}

cmd_list() {
  if [[ ! -d "$STAGE" ]]; then echo "(nothing staged)"; return 0; fi
  (cd "$STAGE" && find . -mindepth 1 | sed 's|^\./|/|')
}

cmd_clean() { rm -rf "$STAGE"; echo "[guest-patch] staging cleared"; }

next_number() {
  local max=0 n f
  for f in "$GB"/[0-9][0-9][0-9][0-9]-*.patch; do
    [[ -e "$f" ]] || continue
    n="${f##*/}"; n="${n%%-*}"; n=$((10#$n))
    (( n > max )) && max=$n
  done
  printf '%04d' $((max + 1))
}

slug() { # Title-Case-Hyphen slug from a subject, matching existing names
  echo "$1" | tr -cs 'A-Za-z0-9 ' '-' | sed -e 's/^-//' -e 's/-$//' \
    | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1' OFS='-'
}

existing_patch_paths() {
  grep -h "^diff --git" "$GB"/[0-9][0-9][0-9][0-9]-*.patch 2>/dev/null \
    | sed -n 's|^diff --git a/||; s| b/.*$||p' | sort -u
}

cmd_commit() {
  local modify=0 subject="" author_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --modify) modify=1; shift ;;
      --author) [[ $# -ge 2 ]] || { echo "error: --author needs a value" >&2; exit 2; }
                author_args=(-c user.name="${2%% <*}" -c user.email="${2#*<}"); AUTHOR="$2"; shift 2 ;;
      *) if [[ -z "$subject" ]]; then subject="$1"; shift;
         else echo "error: unexpected argument: $1" >&2; exit 2; fi ;;
    esac
  done
  [[ -n "$subject" ]] || { echo "error: commit needs a subject" >&2; exit 2; }
  [[ -d "$STAGE" && -n "$(cd "$STAGE" 2>/dev/null && find . -mindepth 1 -print -quit)" ]] || {
    echo "error: nothing staged — use 'stage' first" >&2; exit 2; }

  local brepo bcommit savsha image
  brepo="$(builder_field repository)"; bcommit="$(builder_field commit)"
  savsha="$(git -C "$REPO" rev-parse HEAD)"
  image="$(sed -n 's/.*"release": *"\([^"]*\)".*/\1/p' "$STAGE/guest/install-state.json" 2>/dev/null || true)"
  if [[ -z "$image" ]]; then
    image="$(sed -n 's/.*"release": *"\([^"]*\)".*/\1/p' \
      "${SAVANTOS_DEV_DIR:-$USERPROFILE/savantos-dev}/guest/install-state.json" 2>/dev/null || true)"
  fi
  [[ -n "$image" ]] || image="(no install receipt found)"

  # Collision check for add mode: path must not exist in the builder tree or
  # in any existing patch.
  if (( ! modify )); then
    local collisions=""
    while IFS= read -r p; do
      if grep -qxF "guest/factory-overlay${p}" <(existing_patch_paths); then
        collisions+="  $p (already in an existing patch — use --modify)
"
      fi
    done < <(cd "$STAGE" && find . -mindepth 1 -type f -printf '/%P\n')
    [[ -z "$collisions" ]] || { echo "error: add-mode collisions:
$collisions" >&2; exit 1; }
  fi

  # WORKDIR is global so the EXIT trap (which runs after this function's
  # locals are gone) can still clean up under set -u.
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/savantos-gp-XXXXXX")"
  local work="$WORKDIR"
  trap 'rm -rf "${WORKDIR:-}"' EXIT
  git init -q "$work/tree"
  git -C "$work/tree" checkout -q -b authoring

  if (( modify )); then
    # The honest modify base is the FULL patched tree — builder commit plus
    # every existing guest-build patch — because a file may have been
    # introduced by an earlier SavantOS patch (e.g. clipboard-bridge by
    # 0003), not exist in the builder at all. This is the same sequence
    # build-guest.sh performs, so the emitted diff applies in CI context.
    echo "[guest-patch] modify mode: builder $bcommit + all existing patches"
    git -C "$work/tree" remote add builder "$brepo" 2>/dev/null || true
    git -C "$work/tree" fetch -q --depth=1 builder "$bcommit"
    git -C "$work/tree" checkout -q --detach FETCH_HEAD
    git -C "$work/tree" config user.name authoring
    git -C "$work/tree" config user.email authoring@localhost
    git -C "$work/tree" am -q "$GB"/[0-9][0-9][0-9][0-9]-*.patch
  fi

  # Refuse symlinks up front (straight loop so set -e works): Windows git
  # materializes them as plain files — silently wrong. Hand-edit per patch
  # 0044's symlink hunk pattern instead.
  while IFS= read -r -d '' rel; do
    if [[ -L "$STAGE/$rel" ]]; then
      echo "error: symlink staged — not supported (would materialize as a plain file on Windows): /$rel" >&2
      echo "       clean; re-stage without it; add it by hand following guest-build/0044's symlink hunk pattern." >&2
      exit 3
    fi
  done < <(cd "$STAGE" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0')

  # Lay staged files into the builder-tree mapping and record their modes.
  local rel gp mode
  (cd "$STAGE" && find . -mindepth 1 -type f -printf '%P\0') |
  while IFS= read -r -d '' rel; do
    gp="$work/tree/guest/factory-overlay/$rel"
    mkdir -p "$(dirname "$gp")"
    cp "$STAGE/$rel" "$gp"
    mode="$(stat -c '%a' "$STAGE/$rel")"
    printf '%s %s\n' "$rel" "$mode"
  done > "$work/captured.txt"

  git -C "$work/tree" add guest/factory-overlay
  # Windows git has core.fileMode=false: exec bits must be recorded
  # explicitly or scripts land as 100644 (existing patches use 100755).
  (cd "$work/tree" && git diff --cached --name-only) | while IFS= read -r f; do
    rel="${f#guest/factory-overlay/}"
    mode="$(stat -c '%a' "$STAGE/$rel" 2>/dev/null || echo 644)"
    if (( (8#$mode & 8#111) != 0 )); then
      git -C "$work/tree" update-index --chmod=+x "$f"
    fi
  done
  [[ -n "$(git -C "$work/tree" status --porcelain)" ]] || {
    echo "error: nothing to commit after staging — capture produced no files" >&2; exit 1; }
  local body
  body="Builder: $brepo @ $bcommit (source.lock.json)
SavantOS source: $savsha
Factory image provenance: $image
Captured from the live dev VM (scripts/dev/guest-patch.sh):
$(sed 's/^/  /' "$work/captured.txt")"
  if [[ -n "$AUTHOR" ]]; then
    git -C "$work/tree" ${author_args[@]+"${author_args[@]}"} \
      commit -q -m "$subject" -m "$body"
  else
    git -C "$work/tree" commit -q -m "$subject" -m "$body"
  fi

  local out num slugtext
  out="$work/out"; mkdir -p "$out"
  git -C "$work/tree" format-patch -1 -o "$out" HEAD >/dev/null
  local patchfile
  patchfile="$(ls "$out"/0001-*.patch 2>/dev/null | head -1)"
  [[ -n "$patchfile" ]] || { echo "error: format-patch produced no patch" >&2; exit 1; }
  num="$(next_number)"; slugtext="$(slug "$subject")"
  local dest="$GB/$num-$slugtext.patch"
  # Mailbox patches must stay LF (git am in CI consumes them as-is).
  tr -d '\r' < "$patchfile" > "$dest"
  if grep -q $'\r' "$dest"; then
    echo "error: CRLF survived sanitization in $dest" >&2; exit 1
  fi

  # Proof: the builder's real consumer is `git am` — round-trip the patch
  # against the same base the builder would have when this patch lands.
  local proof="$work/proof"
  git init -q "$proof"
  git -C "$proof" config user.name proof; git -C "$proof" config user.email proof@proof
  if (( modify )); then
    git -C "$proof" fetch -q --depth=1 "$brepo" "$bcommit"
    git -C "$proof" checkout -q --detach FETCH_HEAD
    git -C "$proof" am -q "$GB"/[0-9][0-9][0-9][0-9]-*.patch
    git -C "$proof" am -q "$dest"
    echo "[guest-patch] git am round-trip: OK (modifies $(git -C "$proof" diff --name-only HEAD~1 HEAD | wc -l) file(s) on the fully-patched tree)"
  else
    # An add-only patch cannot `am` onto the unrelated builder head without
    # its context commit; prove mailbox validity + payload paths instead.
    git -C "$proof" commit -q --allow-empty -m base
    git -C "$proof" am -q "$dest"
    git -C "$proof" diff --name-only --diff-filter=A HEAD~1 HEAD | while IFS= read -r f; do
      [[ "$f" == guest/factory-overlay/* ]] || {
        echo "error: patch touches non-overlay path: $f" >&2; exit 1; }
    done
    echo "[guest-patch] git am round-trip: OK (adds $(git -C "$proof" diff --name-only --diff-filter=A HEAD~1 HEAD | wc -l) file(s), all under guest/factory-overlay/)"
  fi

  echo "[guest-patch] wrote $dest"
  echo "[guest-patch] NEXT: delete it if it was only a probe, or prove it with:"
  echo "[guest-patch]   scripts/release/build-guest.sh --contract-only"
  echo "[guest-patch] then commit guest-build/$num-$slugtext.patch and open a PR."
}

case "${1:-help}" in
  stage)  shift; cmd_stage "$@" ;;
  list)   cmd_list ;;
  commit) shift; cmd_commit "$@" ;;
  clean)  cmd_clean ;;
  help|-h|--help) usage ;;
  *) echo "error: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
