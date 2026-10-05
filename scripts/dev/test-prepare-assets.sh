#!/bin/bash
# Verification for the one-owner runtime reconciliation in
# scripts/release/prepare-assets.sh (FID-2026-0914-002, 2026-10-03): the
# runtime archive is the BUILDER's payload entry (asserted against the lock's
# pin), and only the source archive is staged here. All network access is
# synthetic (file:// URLs); nothing is fetched from the internet.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO/scripts/release/prepare-assets.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { echo "  PASS $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (=$3)"; else bad "$1 (want $3, got $2)"; fi; }

RUNTIME_NAME="winq-emu-alpha10-portable.zip"
SOURCE_NAME="winq-emu-alpha10-source.zip"

echo "== 1. syntax =="
if bash -n "$SCRIPT"; then ok "bash -n"; else bad "bash -n"; fi

# make_fixture <sums-content> -> sets ARTIFACTS and LOCK for one run
make_fixture() { # <sums-content> <source-staged: bool>
  local sums=$1
  ARTIFACTS="$TMP/art-$RANDOM"
  mkdir -p "$ARTIFACTS"
  printf '%s\n' "$sums" > "$ARTIFACTS/SHA256SUMS"
  # Payload files the final sha256sum --check needs. The runtime entry is
  # the builder's staged archive — a real payload carries the file, so the
  # fixture does too.
  printf 'rootfs-bytes' > "$ARTIFACTS/rootfs.ext4.zst"
  printf 'kernel-bytes' > "$ARTIFACTS/vmlinuz-linux"
  printf 'payload' > "$ARTIFACTS/$RUNTIME_NAME"
  # Local source archive the lock's file:// URL points at.
  printf 'source-bytes' > "$TMP/$SOURCE_NAME"
  local src_digest; src_digest=$(sha256sum "$TMP/$SOURCE_NAME" | cut -d' ' -f1)
  local src_url="file:///"
  src_url+="$(cygpath -m "$TMP/$SOURCE_NAME" 2>/dev/null || sed 's|^/||' <<<"$TMP/$SOURCE_NAME")"
  cat > "$TMP/lock.json" <<EOF
{
  "runtime": {"url": "https://example.invalid/$RUNTIME_NAME", "filename": "$RUNTIME_NAME", "sha256": "$RUNTIME_DIGEST"},
  "source": {"url": "$src_url", "filename": "$SOURCE_NAME", "sha256": "$src_digest"}
}
EOF
}

run_prepare() {
  SAVANTOS_RUNTIME_LOCK="$TMP/lock.json" bash "$SCRIPT" "$ARTIFACTS" >"$TMP/out" 2>"$TMP/err"
  echo $?
}

echo "== 2. assertion passes and the source archive is staged (offline positive) =="
printf 'payload' > "$TMP/$RUNTIME_NAME"
RUNTIME_DIGEST=$(sha256sum "$TMP/$RUNTIME_NAME" | cut -d' ' -f1)
R_DIGEST=$(printf 'rootfs-bytes' | sha256sum | cut -d' ' -f1)
K_DIGEST=$(printf 'kernel-bytes' | sha256sum | cut -d' ' -f1)
make_fixture "${R_DIGEST}  rootfs.ext4.zst
${K_DIGEST}  vmlinuz-linux
${RUNTIME_DIGEST}  $RUNTIME_NAME"
rc=$(run_prepare)
check "exit" "$rc" "0"
S_DIGEST=$(printf 'source-bytes' | sha256sum | cut -d' ' -f1)
if grep -qE "^${S_DIGEST}[[:space:]]+${SOURCE_NAME}$" "$ARTIFACTS/SHA256SUMS"; then
  ok "source digest appended"
else
  bad "source digest appended"
fi
if grep -qE "^${RUNTIME_DIGEST}[[:space:]]+$RUNTIME_NAME$" "$ARTIFACTS/SHA256SUMS"; then
  ok "runtime entry untouched"
else
  bad "runtime entry untouched"
fi

echo "== 3. payload missing the runtime entry fails closed =="
make_fixture "${R_DIGEST}  rootfs.ext4.zst
${K_DIGEST}  vmlinuz-linux"
rc=$(run_prepare)
check "exit" "$rc" "1"
if grep -q "lacks the pinned runtime archive entry" "$TMP/err"; then
  ok "actionable refusal message"
else
  bad "actionable refusal message (err: $(cat "$TMP/err"))"
fi

echo "== 4. drifted runtime digest fails closed =="
make_fixture "${R_DIGEST}  rootfs.ext4.zst
${K_DIGEST}  vmlinuz-linux
0000000000000000000000000000000000000000000000000000000000000000  $RUNTIME_NAME"
rc=$(run_prepare)
check "exit" "$rc" "1"
if grep -q "lacks the pinned runtime archive entry" "$TMP/err"; then
  ok "drift refusal message"
else
  bad "drift refusal message (err: $(cat "$TMP/err"))"
fi

echo "== 5. duplicate source archive still refused =="
make_fixture "${R_DIGEST}  rootfs.ext4.zst
${K_DIGEST}  vmlinuz-linux
${RUNTIME_DIGEST}  $RUNTIME_NAME
$(printf 'source-bytes' | sha256sum | cut -d' ' -f1)  $SOURCE_NAME"
rc=$(run_prepare)
check "exit" "$rc" "1"
if grep -q "already present in SHA256SUMS" "$TMP/err"; then
  ok "duplicate guard fires for the source role"
else
  bad "duplicate guard fires for the source role (err: $(cat "$TMP/err"))"
fi

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
