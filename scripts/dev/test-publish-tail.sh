#!/bin/bash
# Scripted proofs for guest-image/publish-tail.sh (FID-2026-1005-001).
#
# Drives every state of the rename-swap publish FSM on tiny fake payloads:
# no VM, no Docker, no network — and no `find`/`head` (this host's Git
# Bash lacks both; the suite must run where CI and the operator run it).
# Auto-wired into CI: the windows-launcher job globs scripts/dev/test-*.sh.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAIL=$HERE/../../guest-image/publish-tail.sh

pass=0
failn=0

ok() { echo "  PASS $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; failn=$((failn + 1)); }
check() { # check <desc> <got> <want>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi
}
check_ne() { # check_ne <desc> <got> <not-want>
    if [[ "$2" != "$3" ]]; then ok "$1"; else bad "$1 (expected anything but '$3')"; fi
}

ROOT=""
cleanup() { [[ -n $ROOT && -d $ROOT ]] && rm -rf "$ROOT"; }
trap cleanup EXIT

new_env() {
    cleanup
    ROOT=$(mktemp -d)
    mkdir -p "$ROOT/out" "$ROOT/build-a"
    OUT=$ROOT/out
    STG=$ROOT/build-a
}

make_payload() { # make_payload <dir> <tag>
    mkdir -p "$1"
    local f
    for f in guest-manifest.json build-spec.json vmlinuz-linux \
        initramfs-linux.img rootfs.ext4 rootfs.ext4.zst rootfs.ext4.caibx; do
        printf '%s\n' "$2" >"$1/$f"
    done
    (cd "$1" && sha256sum guest-manifest.json build-spec.json vmlinuz-linux \
        initramfs-linux.img rootfs.ext4 rootfs.ext4.zst rootfs.ext4.caibx \
        >SHA256SUMS)
}

run_tail() { # run_tail [env vars...] — log lands in $ROOT/log, rc in $rc
    env "$@" bash "$TAIL" "$OUT" "$STG" "local/phase1" "0.0.0-test" \
        >"$ROOT/log" 2>&1
    rc=$?
}

exists() { [[ -e $1 ]] && echo yes || echo no; }

echo "== 1. happy swap publishes the new payload, removes the park, emits release-base =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_RETRY_DELAY=0
check "exit" "$rc" "0"
check "published payload is the new one" "$(<"$OUT/contract/rootfs.ext4")" "NEW"
check "park removed after verification" "$(exists "$OUT/contract.prev")" "no"
check "release-base.json emitted" "$(exists "$OUT/release-base.json")" "yes"
check "staged dir consumed by the rename" "$(exists "$STG/contract")" "no"
want=$(sha256sum "$OUT/contract/SHA256SUMS" | cut -d' ' -f1)
got=$(sed -n 's/.*"sumsSha256": "\([0-9a-f]*\)".*/\1/p' "$OUT/release-base.json")
check "release-base sumsSha256 matches published SHA256SUMS" "$got" "$want"
grep -q "GATE GREEN" "$ROOT/log" && ok "GATE GREEN line printed" || bad "GATE GREEN line printed"

echo "== 2. corrupt staged payload is refused BEFORE the swap; previous untouched =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
printf 'CORRUPTED\n' >"$STG/contract/rootfs.ext4"
run_tail PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
check "previous payload untouched" "$(<"$OUT/contract/rootfs.ext4")" "OLD"
check "no park created" "$(exists "$OUT/contract.prev")" "no"
check "no release-base.json on failure" "$(exists "$OUT/release-base.json")" "no"
grep -q "SHA256SUMS reported a mismatch" "$ROOT/log" &&
    ok "mismatch named in output" || bad "mismatch named in output"

echo "== 3. abort before park leaves the published payload byte-identical =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_FAIL_AT=before-park PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
check "previous payload untouched" "$(<"$OUT/contract/rootfs.ext4")" "OLD"
check "no park created" "$(exists "$OUT/contract.prev")" "no"

echo "== 4. abort between the renames: both generations recoverable =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_FAIL_AT=between-renames PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
check "published slot empty between renames" "$(exists "$OUT/contract")" "no"
check "previous payload parked (not destroyed)" "$(exists "$OUT/contract.prev")" "yes"
check "new payload still staged" "$(exists "$STG/contract")" "yes"
mv "$OUT/contract.prev" "$OUT/contract"
check "documented recovery (mv park back) restores the old payload" \
    "$(<"$OUT/contract/rootfs.ext4")" "OLD"

echo "== 5. busy handle on the park rename retries, then succeeds =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_MV_FAIL_FIRST=1 PT_MV_STATE="$ROOT/mvcount" PT_RETRY_DELAY=0
check "exit" "$rc" "0"
check "published payload is the new one" "$(<"$OUT/contract/rootfs.ext4")" "NEW"
grep -q "attempt 1/6" "$ROOT/log" && ok "retry logged" || bad "retry logged"

echo "== 6. retry exhaustion fails with the previous payload STILL PUBLISHED =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_MV_FAIL_FIRST=99 PT_MV_STATE="$ROOT/mvcount" PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
check "previous payload still published and intact" "$(<"$OUT/contract/rootfs.ext4")" "OLD"
check "no park left behind" "$(exists "$OUT/contract.prev")" "no"
check "new payload intact and staged" "$(exists "$STG/contract")" "yes"
grep -q "STILL PUBLISHED" "$ROOT/log" &&
    ok "STILL PUBLISHED stated" || bad "STILL PUBLISHED stated"

echo "== 7. a stale park fails closed with instructions =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
mkdir -p "$OUT/contract.prev"
printf 'prior-failure\n' >"$OUT/contract.prev/marker"
run_tail PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
check "stale park not silently deleted" "$(exists "$OUT/contract.prev/marker")" "yes"
check "previous payload untouched" "$(<"$OUT/contract/rootfs.ext4")" "OLD"
grep -q "stale park present" "$ROOT/log" &&
    ok "stale-park message" || bad "stale-park message"

echo "== 8. first publish (no previous payload) works =="
new_env
make_payload "$STG/contract" NEW
run_tail PT_RETRY_DELAY=0
check "exit" "$rc" "0"
check "published payload is the new one" "$(<"$OUT/contract/rootfs.ext4")" "NEW"
check "no park ever created" "$(exists "$OUT/contract.prev")" "no"
grep -q "first publish" "$ROOT/log" && ok "first-publish logged" || bad "first-publish logged"

echo "== 9. the park name is invisible to the contract-* globs (rotation/delta) =="
new_env
mkdir -p "$OUT/contract.prev" "$OUT/contract-20260929"
# The rotation guard and delta-prev selection match -name 'contract-*';
# an equivalent shell glob must not see the park directory.
shopt -s nullglob
siblings=("$OUT"/contract-*)
shopt -u nullglob
check "glob sees exactly one entry" "${#siblings[@]}" "1"
check "and it is the sibling payload, not the park" \
    "$(basename "${siblings[0]}")" "contract-20260929"

echo "== 10. unknown PT_FAIL_AT fails closed (no silent stage skip) =="
new_env
make_payload "$OUT/contract" OLD
make_payload "$STG/contract" NEW
run_tail PT_FAIL_AT=bogus-stage PT_RETRY_DELAY=0
check_ne "exit is nonzero" "$rc" "0"
grep -q "unknown PT_FAIL_AT" "$ROOT/log" &&
    ok "unknown value rejected" || bad "unknown value rejected"
check "previous payload untouched" "$(<"$OUT/contract/rootfs.ext4")" "OLD"

echo "== 11. same-device precondition present (static; live cross-device NEEDS-REVIEW) =="
grep -q 'stat -c %d' "$TAIL" &&
    ok "same-device check greppable in publish-tail.sh" ||
    bad "same-device check greppable in publish-tail.sh"

echo ""
echo "RESULT: $pass passed, $failn failed"
if [[ $failn -gt 0 ]]; then exit 1; fi
exit 0
