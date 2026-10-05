#!/bin/bash
# G4 headless smoke (FID-2026-0916-001): a -headless boot of a provisioned
# dev dir must reach QEMU and userspace-ready with every dialog resolved
# non-interactively and logged, never blocking on an invisible message box.
#
# The launcher is launched detached with its own stdout/stderr redirected:
# a foreground call would hold the calling terminal's pipe open and time out.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="${SAVANTOS_ACCEPT_DIR:-$USERPROFILE/savantos-accept}"
LAUNCHER="$REPO/app/SavantOS-dev.exe"
LOG="$REPO/dev/scratchpad/g4-headless-boot.log"
SHELLLOG="$TARGET/vm/shell.log"
READY_TIMEOUT="${READY_TIMEOUT:-300}"
SSH_PORT=2222

[ -f "$LAUNCHER" ] || { echo "missing launcher: $LAUNCHER" >&2; exit 1; }
command -v tasklist >/dev/null || { echo "tasklist unavailable" >&2; exit 1; }
if netstat -ano 2>/dev/null | grep -q ':4450 .*LISTENING'; then
  echo "error: QMP 4450 is already held; refusing to start a second VM" >&2
  exit 2
fi

cleanup() {
  local pid=${1:-}
  [ -n "$pid" ] || return 0
  # Power the guest down cleanly so the launcher's own close path runs.
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$SSH_PORT" savant@127.0.0.1 'systemctl poweroff' >/dev/null 2>&1
  local t
  for t in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 2
  done
  echo "WARN: launcher still alive after 120s; killing the tree" >&2
  taskkill //F //T //PID "$pid" >/dev/null 2>&1
}
trap 'cleanup "$LPID"' EXIT

before=$( [ -f "$SHELLLOG" ] && wc -l < "$SHELLLOG" || echo 0 )
echo "=== G4 headless smoke: $(date +%H:%M:%S) ==="
echo "target: $TARGET"
echo "slice:  shell.log lines $((before+1)).."

"$LAUNCHER" -dir "$(cygpath -w "$TARGET")" -headless -instant -no-update -ssh "$SSH_PORT" \
  >"$LOG" 2>&1 </dev/null &
LPID=$!
echo "launcher pid $LPID"

ready=0
for ((t=0; t<READY_TIMEOUT; t+=5)); do
  if tail -n +"$((before+1))" "$SHELLLOG" 2>/dev/null | grep -q "guest userspace announced ready"; then
    ready=1
    echo "userspace ready after ${t}s"
    break
  fi
  kill -0 "$LPID" 2>/dev/null || { echo "launcher exited early"; break; }
  sleep 5
done

slice=$(tail -n +"$((before+1))" "$SHELLLOG" 2>/dev/null)

echo
echo "--- D3 dialog discipline (every decision must be logged) ---"
printf '%s\n' "$slice" | grep -E "headless" || echo "  (no headless decision lines)"
echo
echo "--- pre-boot phases ---"
printf '%s\n' "$slice" | grep -E "^[0-9:]+ phase: " || true
echo
echo "--- share / provision decisions ---"
printf '%s\n' "$slice" | grep -E "shared folder|share-validation|provision|instant" || true
echo
echo "--- QEMU reached + guest ready ---"
printf '%s\n' "$slice" | grep -E "phase: qemu|booting - |userspace announced ready" || true
echo
if printf '%s\n' "$slice" | grep -qE "FATAL |modalFatal|no non-interactive default"; then
  echo "FAIL: a headless path hit a fatal or an undefaulted dialog"
  [[ "$ready" -eq 1 ]] || echo "FAIL: never reached userspace ready"
  exit 1
fi
[[ "$ready" -eq 1 ]] || { echo "FAIL: never reached userspace ready"; exit 1; }
echo "PASS: headless boot reached QEMU and userspace ready with no dialog block"
exit 0
