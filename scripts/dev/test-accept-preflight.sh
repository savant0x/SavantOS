#!/bin/bash
# Verification for accept-close-cycles.sh that launches NO VM: every refusal
# path plus the --preflight-only path, which is the only authorized route
# that reaches the build check.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIVER="$REPO/scripts/dev/accept-close-cycles.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (=$3)"; else bad "$1 (want $3, got $2)"; fi; }
has()   { if grep -q "$2" "$3"; then ok "$1"; else bad "$1"; fi; }

run() { # run <dir> <logfile> <args...>
  local dir="$1" lg="$2"; shift 2
  SAVANTOS_ACCEPT_LOG="$lg" SAVANTOS_ACCEPT_DIR="$dir" \
    bash "$DRIVER" "$@" >"$TMP/stdout" 2>"$TMP/stderr"
  echo $?
}

echo "== 1. no authorization flag: refuses, runs nothing =="
rc=$(run "$TMP/target" "$TMP/l1.log")
check "exit" "$rc" "2"
has "says NOT RUN" "VERDICT: NOT RUN" "$TMP/l1.log"
has "explains why" "not implied by a headless run" "$TMP/l1.log"
if [ -d "$TMP/target" ]; then bad "target untouched (must not be created)"; else ok "target untouched (must not be created)"; fi

echo "== 2. unknown option: refuses =="
rc=$(run "$TMP/target" "$TMP/l2.log" --authorized-disposable-target --bogus)
check "exit" "$rc" "2"

echo "== 3. authorized but target missing: refuses with reseed guidance =="
rc=$(run "$TMP/nope" "$TMP/l3.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "2"
has "says NOT RUN" "VERDICT: NOT RUN" "$TMP/l3.log"
has "gives reseed guidance" "dev-vm.sh init --seed-from" "$TMP/l3.log"

echo "== 4. target exists but is not a dev dir (no anchor): refuses =="
mkdir -p "$TMP/plain"
rc=$(run "$TMP/plain" "$TMP/l4.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "2"
has "explains the anchor rule" "not a dev-vm.sh data dir" "$TMP/l4.log"

echo "== 5. dev dir with anchor: preflight passes, no VM launched =="
mkdir -p "$TMP/target"
printf '{"kind": "savantos-dev-anchor", "version": 1}\n' > "$TMP/target/dev-anchor.json"
rc=$(run "$TMP/target" "$TMP/l5.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "0"
has "reports PREFLIGHT OK" "VERDICT: PREFLIGHT OK" "$TMP/l5.log"
has "confirms no VM launched" "no VM was launched" "$TMP/l5.log"
has "checked QMP+SSH free" "QMP and SSH ports free" "$TMP/l5.log"
has "checked no pre-existing QEMU" "no pre-existing QEMU" "$TMP/l5.log"

echo "== 6. the preflight path never reaches a boot =="
if grep -q "dev-vm.sh boot" "$TMP/l5.log"; then
  bad "preflight must not log a boot"
else
  ok "preflight must not log a boot"
fi
if grep -q "session 1" "$TMP/l5.log"; then
  bad "preflight must not start a session"
else
  ok "preflight must not start a session"
fi

echo "== 7. teardown trap is installed for the real run =="
if grep -q "^trap teardown EXIT" "$DRIVER"; then ok "EXIT trap present"; else bad "EXIT trap present"; fi
if grep -qE "Stop-Process -Name|Stop-Process -Name qemu" "$DRIVER"; then
  bad "must not kill by process name"
else
  ok "must not kill by process name"
fi
if grep -q 'taskkill //F //T //PID' "$DRIVER"; then ok "kills by PID tree"; else bad "kills by PID tree"; fi

echo "== 8. the QEMU probe sees a real QEMU (regression: the .exe-less filter matched nothing) =="
# A shimmed tasklist is the only way to exercise this without a live VM.
# The old probe used `tasklist //FI "IMAGENAME eq qemu-system-x86_64w"`, which
# matches nothing; this feeds the real tasklist shape through the driver.
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/tasklist" <<'SHIM'
#!/bin/sh
printf 'Image Name                     PID Session Name        Session#       Mem Usage\n'
printf 'qemu-system-x86_64w.exe      66216 Console                    1  7,714,940 K\n'
exit 0
SHIM
chmod +x "$STUB/tasklist"
PATH="$STUB:$PATH" rc=$(run "$TMP/target" "$TMP/l8.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "2"
has "sees the stray QEMU" "already running" "$TMP/l8.log"
has "reports its pid" "66216" "$TMP/l8.log"
has "says NOT RUN" "VERDICT: NOT RUN" "$TMP/l8.log"

echo "== 9. a host with no QEMU still passes preflight =="
cat > "$STUB/tasklist" <<'SHIM'
#!/bin/sh
printf 'Image Name                     PID Session Name        Session#       Mem Usage\n'
printf 'explorer.exe                   1234 Console                    1    90,000 K\n'
exit 0
SHIM
chmod +x "$STUB/tasklist"
PATH="$STUB:$PATH" rc=$(run "$TMP/target" "$TMP/l9.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "0"
has "reports PREFLIGHT OK" "VERDICT: PREFLIGHT OK" "$TMP/l9.log"

echo "== 10. an unreadable process list refuses rather than passing blind =="
cat > "$STUB/tasklist" <<'SHIM'
#!/bin/sh
exit 1
SHIM
chmod +x "$STUB/tasklist"
PATH="$STUB:$PATH" rc=$(run "$TMP/target" "$TMP/l10.log" --authorized-disposable-target --preflight-only)
check "exit" "$rc" "2"
has "explains it cannot tell a clean host from a busy one" "rather than running blind" "$TMP/l10.log"
rm -f "$STUB/tasklist"

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
