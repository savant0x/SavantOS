#!/bin/bash
# Stage-2 exit evidence for the D1 override-refusal guard (FID-2026-0916-001).
#
# The unit table (provision_guard_test.go) proves the guard's policy function.
# These are the LIVE runs the stage-2 gate asks for: the real launcher binary,
# the real resolution path, isolated LOCALAPPDATA so nothing outside the
# staging root can be touched.
#
#   refuse A1  damaged/partial install (guest content, no receipt), -dir, no
#              anchor            -> REFUSE before any network I/O
#   refuse A2  receipt + damaged rootfs (install-state.json copied verbatim),
#              -dir, no anchor   -> REFUSE before any network I/O
#   proceed P1 runtime-only dir (no guest/), -dir, no anchor -> guard passes,
#              run reaches phase: update-check
#   proceed P2 anchored dir (dev-anchor.json + install metadata), -dir ->
#              guard passes, run reaches phase: update-check
#
# Overrides use a dead loopback release URL so any post-guard fetch fails
# instantly: refuse runs must never fetch at all, proceed runs self-terminate.
# Teardown kills by real Windows PID (CommandLine token match) — never $!,
# never image name (scripts/dev/README.md process rules).
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER_SRC="$REPO/app/SavantOS-dev.exe"
REAL_TARGET="${SAVANTOS_ACCEPT_DIR:-$USERPROFILE/savantos-accept}"
ROOT="$(cygpath -m "$TEMP")/savantos-stage2-$$"
ISO="$ROOT/appdata"
DEAD_URL="http://127.0.0.1:9"
DEAD_SUMS="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef0000"
TIMEOUT_SECS=180

[ -f "$LAUNCHER_SRC" ] || { echo "missing launcher: $LAUNCHER_SRC" >&2; exit 1; }
[ -f "$REAL_TARGET/guest/install-state.json" ] || { echo "missing real install receipt at $REAL_TARGET" >&2; exit 1; }

# --- preflight: nothing of ours may be running -------------------------------
if tasklist //NH 2>/dev/null | grep -qi 'SavantOS-dev.exe'; then
  echo "error: a SavantOS-dev.exe is already running; refusing to start" >&2
  exit 2
fi
if netstat -ano 2>/dev/null | grep -q ':4450 .*LISTENING'; then
  echo "error: QMP 4450 held; refusing" >&2
  exit 2
fi

mkdir -p "$ISO/SavantOS"

kill_run() {
  # Kill every SavantOS-dev.exe whose command line names this campaign: every
  # run carries the dead release URL (C1 has no -dir, so the URL is the one
  # token present on all command lines).
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='SavantOS-dev.exe'\" | Where-Object { \$_.CommandLine -like '*127.0.0.1:9*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId 2>\$null }" >/dev/null 2>&1
  return 0
}
trap 'kill_run; exit' EXIT

run_launcher() { # $1=dir(win, empty = omit -dir) $2+=extra args; sets LAUNCH_PID
  local dir="$1"; shift
  local dirargs=()
  [ -n "$dir" ] && dirargs=(-dir "$dir")
  # stdout/stderr redirected per the process-lifetime rules; env-isolated.
  ( LOCALAPPDATA="$(cygpath -w "$ISO")" "$LAUNCHER_SRC" -headless "${dirargs[@]+"${dirargs[@]}"}" \
      -release "$DEAD_URL" -sums-sha256 "$DEAD_SUMS" "$@" \
      >"$ROOT/last-stdout.log" 2>&1 ) &
  # NOTE: set a global, never `echo $!` — a caller in command substitution
  # would orphan the job and `wait` would report 127 instead of the real code
  # (observed 2026-09-28).
  LAUNCH_PID=$!
}

wait_exit() { # $1=msys pid $2=timeout secs -> 0 if exited
  local pid=$1 t
  for ((t=0; t<$2; t+=2)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 2
  done
  return 1
}

windows_pid_of() { # echo real Windows PIDs for this campaign's launchers, if any
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='SavantOS-dev.exe'\" | Where-Object { \$_.CommandLine -like '*127.0.0.1:9*' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null
}

expect_refuse() { # $1=name $2=staged dir (win)  — asserts exit 1 + refusal + no update-check
  local name=$1 dir=$2 log msyspid rc
  echo "=== $name ==="
  run_launcher "$dir"
  msyspid=$LAUNCH_PID
  if wait_exit "$msyspid" "$TIMEOUT_SECS"; then
    wait "$msyspid" 2>/dev/null; rc=$?
  else
    echo "  FAIL: launcher still alive after ${TIMEOUT_SECS}s" >&2
    kill_run
    return 1
  fi
  # The launcher's durable log lives under the -dir (the staged data dir).
  log="$ROOT/$1/staged/vm/shell.log"
  if [ ! -f "$log" ]; then
    echo "  FAIL: no shell.log at $log"; cat "$ROOT/last-stdout.log" 2>/dev/null
    return 1
  fi
  if grep -q -e "FATAL payload overrides" -- "$log" \
     && grep -q -e "was resolved by SavantOS, not named by the caller\|has an installed SavantOS and no dev anchor" -- "$log" \
     && ! grep -q -e "phase: update-check" -- "$log"; then
    echo "  PASS: refused (exit $rc), refusal logged, no update-check phase (pre-network)"
    grep -e "FATAL payload overrides" -- "$log" | head -2 | sed 's/^/    /'
    return 0
  fi
  echo "  FAIL: expected refusal before update-check"; tail -5 "$log" | sed 's/^/    /'
  return 1
}

expect_proceed() { # $1=name $2=staged dir — asserts guard passed (update-check reached, no refusal)
  local name=$1 dir=$2 log msyspid rc
  echo "=== $name ==="
  run_launcher "$dir"
  msyspid=$LAUNCH_PID
  if wait_exit "$msyspid" "$TIMEOUT_SECS"; then
    wait "$msyspid" 2>/dev/null; rc=$?
  else
    echo "  FAIL: launcher still alive after ${TIMEOUT_SECS}s" >&2
    kill_run
    return 1
  fi
  log="$ROOT/$1/staged/vm/shell.log"
  if [ ! -f "$log" ]; then
    echo "  FAIL: no shell.log at $log"; cat "$ROOT/last-stdout.log" 2>/dev/null
    return 1
  fi
  if grep -q -e "phase: update-check" -- "$log" \
     && ! grep -q -e "FATAL payload overrides" -- "$log"; then
    echo "  PASS: guard passed (update-check reached, exit $rc), no refusal"
    grep -e "phase: update-check" -e "install:" -- "$log" | head -3 | sed 's/^/    /'
    return 0
  fi
  echo "  FAIL: expected proceed past the guard"; tail -5 "$log" | sed 's/^/    /'
  return 1
}

stage_partial() { # $1 = staged dir
  mkdir -p "$1/guest" "$1/vm"
  printf 'damaged' > "$1/guest/rootfs.ext4"
}

stage_receipt_damaged() { # $1 = staged dir — verbatim receipt, garbage payload
  mkdir -p "$1/guest" "$1/vm"
  cp "$REAL_TARGET/guest/install-state.json" "$1/guest/install-state.json"
  printf 'damaged' > "$1/guest/rootfs.ext4"
}

stage_runtime_only() { # $1 = staged dir — runtime tree via hardlinks, no guest/
  mkdir -p "$1" "$1/vm"
  cp -al "$REAL_TARGET/runtime" "$1/runtime"
}

stage_anchored() { # $1 = staged dir — anchor + install metadata + hardlinked runtime
  mkdir -p "$1" "$1/vm"
  cp -al "$REAL_TARGET/runtime" "$1/runtime"
  mkdir -p "$1/guest"
  cp "$REAL_TARGET/guest/install-state.json" "$1/guest/install-state.json"
  cp "$REAL_TARGET/guest/build-spec.json" "$1/guest/build-spec.json"
  cp "$REAL_TARGET/guest/guest-manifest.json" "$1/guest/guest-manifest.json"
  printf '{"kind": "savantos-dev-anchor", "version": 1}' > "$1/dev-anchor.json"
}

stage_pointer() { # $1 = staged dir (win path) — incident shape: pointer, no -dir
  # Forward slashes: the pointer is JSON, and a literal backslash path is an
  # invalid escape sequence there (observed: the launcher rightly refused the
  # malformed pointer instead of following it). Go accepts drive-letter
  # forward-slash paths on Windows.
  printf '{"version": 1, "path": "%s"}' "$(cygpath -m "$1")" > "$ISO/SavantOS/data-location.json"
}

fails=0
echo "staging root: $ROOT"
echo "launcher: $LAUNCHER_SRC"
echo

# --- A1: partial install, -dir, no anchor ------------------------------------
mkdir -p "$ROOT/A1"
stage_partial "$ROOT/A1/staged"
expect_refuse A1 "$(cygpath -w "$ROOT/A1/staged")" || fails=$((fails+1))
kill_run

# --- A2: receipt + damaged rootfs, -dir, no anchor ---------------------------
mkdir -p "$ROOT/A2"
stage_receipt_damaged "$ROOT/A2/staged"
expect_refuse A2 "$(cygpath -w "$ROOT/A2/staged")" || fails=$((fails+1))
kill_run

# --- P1: runtime-only, -dir, no anchor ---------------------------------------
mkdir -p "$ROOT/P1"
stage_runtime_only "$ROOT/P1/staged"
expect_proceed P1 "$(cygpath -w "$ROOT/P1/staged")" || fails=$((fails+1))
kill_run

# --- P2: anchored dir with install metadata ----------------------------------
mkdir -p "$ROOT/P2"
stage_anchored "$ROOT/P2/staged"
expect_proceed P2 "$(cygpath -w "$ROOT/P2/staged")" || fails=$((fails+1))
kill_run

# --- C1: incident shape (pointer, no -dir) — G2's live row, re-proven -------- 
mkdir -p "$ROOT/C1"
stage_partial "$ROOT/C1/staged"
stage_pointer "$(cygpath -w "$ROOT/C1/staged")"
echo "=== C1 (pointer-resolved, incident shape) ==="
run_launcher ""   # no -dir
msyspid=$LAUNCH_PID
if wait_exit "$msyspid" "$TIMEOUT_SECS"; then
  wait "$msyspid" 2>/dev/null; rc=$?
  log="$ROOT/C1/staged/vm/shell.log"
  if [ -f "$log" ] && grep -q -e "FATAL payload overrides" -- "$log" \
     && grep -q -e "resolved by SavantOS" -- "$log"; then
    echo "  PASS: pointer-resolved dir refused (exit $rc) — incident shape stays dead"
  else
    echo "  FAIL: pointer run did not refuse"; tail -5 "$ROOT/last-stdout.log" 2>/dev/null | sed 's/^/    /'
    fails=$((fails+1))
  fi
else
  echo "  FAIL: pointer run hung"; kill_run; fails=$((fails+1))
fi
kill_run

echo
echo "--- stray check ---"
if tasklist //NH 2>/dev/null | grep -qi 'SavantOS-dev.exe'; then
  echo "FAIL: a SavantOS-dev.exe survived"; fails=$((fails+1))
else
  echo "clean: no launcher processes remain"
fi
echo
if [ "$fails" -eq 0 ]; then
  echo "STAGE-2 EXIT EVIDENCE: GATE GREEN (A1 A2 refuse; P1 P2 proceed; C1 incident shape refuses)"
else
  echo "STAGE-2 EXIT EVIDENCE: $fails FAILURE(S)"
fi
exit $((fails > 0))
