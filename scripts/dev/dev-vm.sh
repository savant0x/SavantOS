#!/bin/bash
# SavantOS developer live-loop VM.
#
# One entry point for the host-side dev loop described in README.md beside
# this script: a dedicated data directory, a shared folder, SSH into the
# running guest, and a locally built launcher with live console logs.
#
# Subcommands: init | boot | shell | stop | help
# Overrides:   SAVANTOS_DEV_DIR, SAVANTOS_DEV_SHARE, SAVANTOS_DEV_PORT
#
# Everything this script creates lives outside the repo and outside any real
# SavantOS install; delete the two folders to remove it completely.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="${SAVANTOS_DEV_DIR:-$USERPROFILE/savantos-dev}"
SHARE_DIR="${SAVANTOS_DEV_SHARE:-$USERPROFILE/savantos-share}"
SSH_PORT="${SAVANTOS_DEV_PORT:-2222}"
GUEST_USER="savant"
QMP_PORT=4450
SEED_DEFAULT="$USERPROFILE/Downloads/savantos-e2e/data"
LAUNCHER_EXE="$REPO/app/SavantOS-dev.exe"

w() { cygpath -w "$1"; } # Windows path for launcher-boundary arguments

usage() {
  cat <<'EOF'
SavantOS dev live-loop VM

  dev-vm.sh init [--seed-from DIR]   create the dev data dir + shared folder
              [--reseed]             (seed from an existing install's data/
                                     dir, skipping the 1.7 GB download; or
                                     leave empty and let first boot download
                                     the factory payload)
                                     --reseed replaces an existing data dir:
                                     the old one is renamed aside to
                                     <dir>.bak-<timestamp>, never deleted
  dev-vm.sh boot [extra flags...]    build (if needed) and launch the dev
                                     launcher with -share, -ssh, -instant,
                                     -no-update; runs in the foreground with
                                     live logs. Extra flags pass through
                                     (e.g. boot -nogpu -fullscreen).
                                     Refuses to start if the QMP port is
                                     already taken (two VMs on one control
                                     plane corrupt each other); pass
                                     --force-qmp to override.
  dev-vm.sh shell [command...]       ssh into the running guest as 'savant'
  dev-vm.sh stop                     how to shut the VM down cleanly

Environment overrides:
  SAVANTOS_DEV_DIR    (default: %USERPROFILE%\savantos-dev)
  SAVANTOS_DEV_SHARE  (default: %USERPROFILE%\savantos-share)
  SAVANTOS_DEV_PORT   (default: 2222)

Typical loop:  dev-vm.sh init && dev-vm.sh boot     (terminal 1)
               dev-vm.sh shell                      (terminal 2)
Edit files in the share folder on Windows; they appear in the guest at
/mnt/host instantly.
EOF
}

need_launcher() {
  if [[ ! -f "$LAUNCHER_EXE" ]]; then
    echo "[dev-vm] building dev launcher (console build, live logs)..."
    (cd "$REPO/app" && go build -o SavantOS-dev.exe .)
  fi
}

guest_up() {
  ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new \
    -p "$SSH_PORT" "$GUEST_USER@127.0.0.1" true 2>/dev/null
}

cmd_init() {
  local seed="" reseed=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --seed-from)
        [[ $# -ge 2 ]] || { echo "error: --seed-from needs a directory" >&2; exit 2; }
        seed="$2"; shift 2 ;;
      --reseed)
        reseed=1; shift ;;
      *) echo "error: unknown init option: $1" >&2; exit 2 ;;
    esac
  done
  if [[ -z "$seed" && -d "$SEED_DEFAULT" ]]; then seed="$SEED_DEFAULT"; fi

  mkdir -p "$SHARE_DIR"
  if [[ ! -f "$SHARE_DIR/hello.sh" ]]; then
    # LF endings only: this file runs under bash inside the guest.
    printf '#!/bin/bash\n# Dev smoke: run inside the guest with: bash /mnt/host/hello.sh\necho "dev share works: $(uname -n) $(date -Is)" > /mnt/host/from-guest.txt\n' \
      > "$SHARE_DIR/hello.sh"
    echo "[dev-vm] wrote $SHARE_DIR/hello.sh (guest->host round-trip smoke)"
  fi

  if [[ -n "$seed" ]]; then
    if [[ ! -d "$seed" ]]; then
      echo "error: seed source not a directory: $seed" >&2; exit 2
    fi
    # A data dir that already has content cannot be seeded into: sparsetool
    # refuses an existing destination on purpose, and merging would carry a
    # previous run's receipts and update state into a "fresh" target. Reseed
    # means replace — and replace by renaming, never by deleting, so a failed
    # or unwanted reseed is always recoverable from the backup.
    if [[ -d "$DEV_DIR" ]]; then
      if [[ -z "$(ls -A "$DEV_DIR" 2>/dev/null)" ]]; then
        # Empty leftover: hand-made, or the remains of an earlier failed run.
        # sparsetool refuses an existing destination whatever its contents, so
        # the empty shell has to go. rmdir is the fail-closed tool — it refuses
        # to remove anything with content, so it cannot take data with it.
        echo "[dev-vm] data dir exists but is empty; removing the empty dir"
        echo "[dev-vm] so the seed can land."
        rmdir "$DEV_DIR"
      else
        if [[ "$reseed" -eq 0 ]]; then
          echo "error: data dir already has content: $DEV_DIR" >&2
          echo "       re-run with --reseed to replace it (the existing dir is" >&2
          echo "       renamed to <dir>.bak-<timestamp>, not deleted), or point" >&2
          echo "       SAVANTOS_DEV_DIR at a new path." >&2
          exit 2
        fi
        if guest_up; then
          echo "error: a guest is still answering on port $SSH_PORT." >&2
          echo "       Shut it down first — reseeding under a running VM" >&2
          echo "       corrupts the data dir it is using." >&2
          exit 2
        fi
        local backup="$DEV_DIR.bak-$(date +%Y%m%d-%H%M%S)"
        echo "[dev-vm] reseeding: moving existing data dir aside to $backup"
        if ! mv "$DEV_DIR" "$backup"; then
          echo "error: could not move $DEV_DIR aside to $backup" >&2
          echo "       (is a VM or file handle still holding it?)" >&2
          exit 1
        fi
        echo "[dev-vm] previous data dir is at $backup — delete it yourself"
        echo "[dev-vm] once this reseed has proven out."
      fi
    fi
    echo "[dev-vm] seeding $DEV_DIR from $seed (sparse copy; nothing downloads)"
    local tool
    tool="$(mktemp -u /tmp/sparsetool-XXXXXX).exe"
    # sparsetool is its own Go module (own go.mod) — build from inside it.
    (cd "$REPO/scripts/vmtest/sparsetool" && go build -o "$tool" .)
    "$tool" copy "$(w "$seed")" "$(w "$DEV_DIR")"
    rm -f "$tool"
    echo "[dev-vm] seeded. Receipts copied byte-for-byte, so the launcher will"
    echo "[dev-vm] verify the local payload instead of re-downloading it."
  else
    echo "[dev-vm] no seed source found; first boot downloads the factory"
    echo "[dev-vm] payload (~1.7 GB) and digest-verifies it automatically."
    mkdir -p "$DEV_DIR"
  fi
  # Dev anchor (FID-2026-0916-001 D1b): marks this data directory as dev
  # tooling territory so the launcher's override guard accepts payload
  # overrides here. Schema must match devAnchor in app/provision_guard.go
  # exactly (unknown fields invalidate it).
  printf '{"kind": "savantos-dev-anchor", "version": 1}\n' > "$DEV_DIR/dev-anchor.json"
  echo "[dev-vm] wrote dev-anchor.json (override-guard anchor)"
  echo "[dev-vm] init complete. Next: scripts/dev/dev-vm.sh boot"
}

cmd_boot() {
  local force_qmp=0
  local passthrough=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force-qmp) force_qmp=1 ;;
      *) passthrough+=("$1") ;;
    esac
    shift
  done

  # Fail closed on a taken QMP port. Two VMs sharing the control plane
  # corrupt each other's state, and the old behaviour (warn, then launch
  # anyway) turned a five-second fix into a confusing dead VM. This runs
  # before need_launcher so a refusal costs nothing.
  local holder_pid holder_name
  holder_pid=$(netstat -ano 2>/dev/null | awk -v p=":${QMP_PORT}" '$2 ~ p"$" && $4 == "LISTENING" {print $5; exit}')
  if [[ -n "$holder_pid" ]]; then
    if [[ "$force_qmp" -eq 1 ]]; then
      echo "[dev-vm] WARNING: port ${QMP_PORT} (QMP) is held by pid ${holder_pid};" \
           "--force-qmp given, starting anyway." >&2
    else
      holder_name=$(tasklist //NH 2>/dev/null | awk -v pid="$holder_pid" '$2 == pid {print $1; exit}')
      echo "error: refusing to start - port ${QMP_PORT} (QMP) is already in use." >&2
      if [[ -n "$holder_name" ]]; then
        echo "       held by: ${holder_name} (pid ${holder_pid})" >&2
      else
        echo "       held by pid ${holder_pid} (image name unavailable)" >&2
      fi
      if [[ "$holder_name" == qemu-system-x86_64w.exe ]]; then
        echo "       Another SavantOS instance is still running. Stop it" >&2
        echo "       first - close the SavantOS window or quit from the tray" >&2
        echo "       icon; 'dev-vm.sh stop' prints the full cleanup steps." >&2
      else
        echo "       That is not SavantOS, but the QMP control plane is still" >&2
        echo "       contended. Free the port, or stop that process." >&2
      fi
      echo "       Override with: dev-vm.sh boot --force-qmp" >&2
      exit 2
    fi
  fi

  need_launcher
  echo "[dev-vm] data dir:  $DEV_DIR"
  echo "[dev-vm] share:     $SHARE_DIR  (guest: /mnt/host)"
  echo "[dev-vm] ssh:       port $SSH_PORT (user: $GUEST_USER)"
  echo "[dev-vm] launching; from another terminal: scripts/dev/dev-vm.sh shell"
  echo "[dev-vm] stop by closing the window/tray icon (Ctrl+C is abrupt-kill)"
  "$LAUNCHER_EXE" \
    -dir "$(w "$DEV_DIR")" \
    -share "$(w "$SHARE_DIR")" \
    -ssh "$SSH_PORT" \
    -instant -no-update ${passthrough[@]+"${passthrough[@]}"}
}

cmd_shell() {
  if ! guest_up; then
    echo "error: no ssh on 127.0.0.1:${SSH_PORT} — boot first:" \
         "scripts/dev/dev-vm.sh boot" >&2
    exit 1
  fi
  if [[ $# -gt 0 ]]; then
    ssh -o StrictHostKeyChecking=accept-new -p "$SSH_PORT" \
      "$GUEST_USER@127.0.0.1" "$@"
  else
    exec ssh -o StrictHostKeyChecking=accept-new -p "$SSH_PORT" \
      "$GUEST_USER@127.0.0.1"
  fi
}

cmd_stop() {
  echo "Clean shutdown: close the SavantOS window or quit from the tray icon;"
  echo "the launcher powers the guest down and finishes cleanup itself."
  echo
  echo "Full removal of the dev environment:"
  echo "  1. shut down as above"
  echo "  2. dev-vm.sh shell -- exit any sessions"
  echo "  3. \"$LAUNCHER_EXE\" -dir \"$(w "$DEV_DIR")\" -uninstall"
  echo "     (removes shortcuts/Apps&features entry + the data folder)"
  echo "  4. delete the share folder:  rm -rf \"$(w "$SHARE_DIR")\""
}

case "${1:-help}" in
  init)  shift; cmd_init "$@" ;;
  boot)  shift; cmd_boot "$@" ;;
  shell) shift; cmd_shell "$@" ;;
  stop)  cmd_stop ;;
  help|-h|--help) usage ;;
  *) echo "error: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
