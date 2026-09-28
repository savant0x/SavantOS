#!/bin/bash
# Verification for dev-vm.sh boot's QMP-port refusal. Launches NO VM: the
# script is exercised from a stub repo layout whose app/SavantOS-dev.exe is a
# recording stub, so "proceeded" is observable without a launcher.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
PS_EXE="$WINDIR/System32/WindowsPowerShell/v1.0/powershell.exe"
export STUB_LOG="$TMP/stub.log"
trap 'rm -rf "$TMP"; kill_listener' EXIT

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if [[ "$2" == "$3" ]]; then ok "$1 (=$3)"; else bad "$1 (want $3, got $2)"; fi; }
# -e so a pattern starting with "-" is never read as an option, and -- before
# the file so a missing file is an error rather than a read of stdin.
has()   { if grep -q -e "$2" -- "$3"; then ok "$1"; else bad "$1 (missing: $2)"; fi; }
hasnt() { if grep -q -e "$2" -- "$3"; then bad "$1 (unexpected: $2)"; else ok "$1"; fi; }

STUBREPO="$TMP/repo"
mkdir -p "$STUBREPO/scripts/dev" "$STUBREPO/app"
cp "$REPO/scripts/dev/dev-vm.sh" "$STUBREPO/scripts/dev/dev-vm.sh"
cat > "$STUBREPO/app/SavantOS-dev.exe" <<'STUB'
#!/bin/sh
echo "STUB-LAUNCHER-INVOKED $*" >> "$STUB_LOG"
exit 0
STUB
chmod +x "$STUBREPO/app/SavantOS-dev.exe"

LISTENER_PID=""
# Git Bash's $! is the MSYS-side pid, which taskkill never matches, so the
# Windows pid is read back off the port instead. Killing the wrong namespace
# is how test 1's listener silently survived into test 2 and made the QEMU
# case pass against the wrong image.
kill_listener() {
  local wpid
  wpid=$(netstat -ano 2>/dev/null | awk '$2 ~ /:4450$/ && $4=="LISTENING"{print $5; exit}')
  if [ -n "$wpid" ]; then
    taskkill //F //PID "$wpid" >/dev/null 2>&1
    for _ in $(seq 1 40); do
      netstat -ano 2>/dev/null | grep -q ':4450 .*LISTENING' || break
      sleep 0.25
    done
  fi
  LISTENER_PID=""
}
# A real TCP listener on the QMP port, published under a chosen image name so
# the QEMU branch can be reached. powershell.exe is the payload because it is
# a single self-contained binary that still runs when copied and renamed;
# python.exe does not (it needs its install directory to resolve stdlib).
# The holder is verified to be the requested image, so a leftover listener
# from an earlier case can never masquerade as this one.
start_listener() {
  local exe="$1" bindir="$TMP/bin" wpid holder
  kill_listener
  if netstat -ano 2>/dev/null | grep -q ':4450 .*LISTENING'; then
    echo "     (4450 still held by a previous case; refusing to continue)" >&2
    return 1
  fi
  mkdir -p "$bindir"
  cp "$PS_EXE" "$bindir/$exe" 2>/dev/null || return 1
  "$bindir/$exe" -NoProfile -Command \
    '$l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,4450); $l.Start(); Start-Sleep -Seconds 300' \
    >/dev/null 2>&1 </dev/null &
  for _ in $(seq 1 80); do
    wpid=$(netstat -ano 2>/dev/null | awk '$2 ~ /:4450$/ && $4=="LISTENING"{print $5; exit}')
    if [ -n "$wpid" ]; then
      holder=$(tasklist //NH 2>/dev/null | awk -v p="$wpid" '$2 == p {print $1; exit}')
      if [ "$holder" = "$exe" ]; then
        LISTENER_PID="$wpid"
        return 0
      fi
      echo "     (port 4450 held by '$holder', wanted '$exe')" >&2
      return 1
    fi
    sleep 0.25
  done
  return 1
}
port_free() { ! netstat -ano 2>/dev/null | grep -q ':4450 .*LISTENING'; }

run_boot() { # run_boot <args...>
  : > "$STUB_LOG"
  SAVANTOS_DEV_DIR="$TMP/devdir" SAVANTOS_DEV_SHARE="$TMP/share" \
    SAVANTOS_DEV_PORT=2299 bash "$STUBREPO/scripts/dev/dev-vm.sh" boot "$@" \
    >"$TMP/out" 2>"$TMP/err"
  echo $?
}
launched() { grep -q "STUB-LAUNCHER-INVOKED" "$STUB_LOG"; }

echo "== 0. baseline: QMP port free, boot proceeds to the stub =="
if port_free; then ok "4450 is free to start"; else bad "4450 already busy before the test"; fi
rc=$(run_boot -nogpu)
check "exit" "$rc" "0"
if launched; then ok "stub launcher was invoked"; else bad "stub launcher was invoked"; fi
has "extra flag passed through" "-nogpu" "$STUB_LOG"
has "dev flags passed through" "-instant -no-update" "$STUB_LOG"
hasnt "no refusal" "refusing to start" "$TMP/err"

echo "== 1. QMP port held by a NON-QEMU process: refuse, do not launch =="
if start_listener "notqemu.exe"; then ok "probe listener is up"; else bad "probe listener failed"; fi
holder=$(netstat -ano 2>/dev/null | awk '$2 ~ /:4450$/ && $4=="LISTENING"{print $5; exit}')
rc=$(run_boot)
check "exit" "$rc" "2"
has "refuses" "refusing to start" "$TMP/err"
has "names the port" "4450" "$TMP/err"
has "names the holder pid" "pid $holder" "$TMP/err"
has "explains it is not SavantOS" "not SavantOS" "$TMP/err"
has "offers the override" "force-qmp" "$TMP/err"
if launched; then bad "must NOT launch while refusing"; else ok "must NOT launch while refusing"; fi
kill_listener

echo "== 2. QMP port held by a QEMU: the SavantOS-specific remedy =="
if start_listener "qemu-system-x86_64w.exe"; then ok "QEMU-named probe is up"; else bad "QEMU-named probe failed"; fi
rc=$(run_boot)
check "exit" "$rc" "2"
has "refuses" "refusing to start" "$TMP/err"
has "identifies the image" "qemu-system-x86_64w.exe" "$TMP/err"
has "says another instance is running" "Another SavantOS instance is still running" "$TMP/err"
if launched; then bad "must NOT launch while refusing"; else ok "must NOT launch while refusing"; fi
kill_listener

echo "== 3. --force-qmp overrides, and is not forwarded to the launcher =="
if start_listener "notqemu.exe"; then ok "probe listener is up"; else bad "probe listener failed"; fi
rc=$(run_boot --force-qmp -nogpu)
check "exit" "$rc" "0"
has "warns it proceeds anyway" "starting anyway" "$TMP/err"
if launched; then ok "stub launcher was invoked"; else bad "stub launcher was invoked"; fi
has "extra flag survived" "-nogpu" "$STUB_LOG"
hasnt "force-qmp must not reach the launcher" "force-qmp" "$STUB_LOG"
kill_listener

echo "== 4. the refusal precedes building or running the launcher =="
if start_listener "notqemu.exe"; then ok "probe listener is up"; else bad "probe listener failed"; fi
rm -f "$STUBREPO/app/SavantOS-dev.exe"   # a build would now be attempted
rc=$(run_boot)
check "exit" "$rc" "2"
has "port message, not a build failure" "refusing to start" "$TMP/err"
hasnt "no build was attempted" "building dev launcher" "$TMP/err"
kill_listener

echo "== 5. usage documents the flag =="
if bash "$STUBREPO/scripts/dev/dev-vm.sh" help | grep -q -e "--force-qmp"; then
  ok "help mentions --force-qmp"
else
  bad "help mentions --force-qmp"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
