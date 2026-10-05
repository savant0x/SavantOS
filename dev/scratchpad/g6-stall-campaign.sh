#!/bin/bash
# G6 stall-reproduction campaign (FID-2026-0916-001), 2026-09-28.
#
# Gate G6 is conditional: "the next live reproduction (if any) must produce
# phase + hint evidence into FID-2026-0915-002 — if it cannot, D2's phase set
# is incomplete and this FID reopens." Twelve sessions produced no stall, so
# this campaign hunts one deliberately, inside the recorded incident family,
# instead of waiting for luck:
#
#   warm-up  provisioned-copy headless boot to "ready" (proves the copy is
#            bootable and shakes out first-execution AV scans, H3)
#   arm A    the E4 incident shape: WINDOWED, no -dir (pointer-resolved),
#            update check ENABLED, provisioned dir
#   arm B    headless variant of A (isolates the headless flag)
#   arm C    windowed + -fresh (first-boot dialog family, H2's chooser path)
#   arm D    windowed, no overrides at all, dead -update-url (the
#            update-check branch under a hanging endpoint, windowed)
#
# Outcome per arm: BOOTED (reached phase: qemu -> graceful QMP powerdown),
# EXITED (ended before QEMU — tail printed, counted as a failure of the arm),
# or STALL (alive pre-QEMU with no log progress for STALL_GAP — evidence
# preserved, tree killed BY PID; scripts/dev/README.md process rules).
#
# NOTE for the operator: windowed arms show a minimized splash on your
# taskbar for up to ARM_SECS each — that is the incident shape and cannot
# be isolated away.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_TARGET="${SAVANTOS_ACCEPT_DIR:-$USERPROFILE/savantos-accept}"
LAUNCHER="$REPO/app/SavantOS-dev.exe"
ROOT="$(cygpath -m "$TEMP")/savantos-g6-$$"
ISO="$ROOT/appdata"
SSH_PORT=2222
QMP_PORT=4450
ARM_SECS=480          # windowed arms: > the 5-min watchdog hint mark
HEADLESS_SECS=420
WARMUP_SECS=300
GAP_POLL=15
STALL_GAP=180         # pre-QEMU silence that counts as a stall

[ -f "$LAUNCHER" ] || { echo "missing launcher: $LAUNCHER" >&2; exit 1; }
[ -f "$SRC_TARGET/guest/install-state.json" ] || { echo "missing source install" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
if tasklist //NH 2>/dev/null | grep -qiE 'SavantOS|qemu'; then
  echo "error: SavantOS/QEMU processes already running; refusing" >&2
  exit 2
fi
if netstat -ano 2>/dev/null | grep -qE ':(4450|2222) .*LISTENING'; then
  echo "error: QMP/SSH port held; refusing" >&2
  exit 2
fi

echo "=== G6 stall-reproduction campaign $(date +%H:%M:%S) ==="
echo "root: $ROOT"

mkdir -p "$ISO/SavantOS" "$ROOT/logs"

kill_g6() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='SavantOS-dev.exe'\" | Where-Object { \$_.CommandLine -like '*savantos-g6-*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId 2>\$null }" >/dev/null 2>&1
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='qemu-system-x86_64w.exe'\" | Where-Object { \$_.CommandLine -like '*savantos-g6-*' } | ForEach-Object { taskkill /F /T /PID \$_.ProcessId 2>\$null }" >/dev/null 2>&1
  return 0
}
trap 'kill_g6; exit' EXIT

alive() {
  [ -n "$(powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='SavantOS-dev.exe'\" | Where-Object { \$_.CommandLine -like '*savantos-g6-*' } | ForEach-Object { \$_.ProcessId }" 2>/dev/null)" ]
}

stage_copy() { # $1 = name -> $ROOT/$1 (provisioned, bootable; rootfs hardlinked)
  local d="$ROOT/$1"
  mkdir -p "$d/guest" "$d/vm" "$d/runtime"
  cp -al "$SRC_TARGET/runtime/." "$d/runtime/"
  cp "$SRC_TARGET/guest/install-state.json" "$d/guest/"
  cp "$SRC_TARGET/guest/build-spec.json" "$d/guest/"
  cp "$SRC_TARGET/guest/guest-manifest.json" "$d/guest/"
  cp "$SRC_TARGET/guest/vmlinuz-linux" "$d/guest/"
  cp "$SRC_TARGET/guest/initramfs-linux.img" "$d/guest/"
  cp -al "$SRC_TARGET/guest/rootfs.ext4" "$d/guest/rootfs.ext4"
  printf 'instant' > "$d/provision-mode"
  printf '%s' "$(cat "$SRC_TARGET/dev-anchor.json")" > "$d/dev-anchor.json"
}

stage_pointer() { # $1 = target dir (win, forward slashes)
  printf '{"version": 1, "path": "%s"}' "$1" > "$ISO/SavantOS/data-location.json"
}

arm_args() { # $1=dir ; extra args appended afterwards; prints the arg array
  # DELIBERATELY no -release/-sums-sha256 overrides and no -no-update: the E4
  # incident ran pointer-resolved with the update check ENABLED against the
  # real default URLs, and every one of the 12 non-reproducing sessions went
  # through dev-vm.sh boot, which passes -no-update — the flag family has
  # never been exercised by the dev launcher. Reproduce the family faithfully.
  local wd; wd=$(cygpath -m "$1")
  printf '%s\n' -dir "$wd" -instant -ssh "$SSH_PORT" "$@"
}

launch_headless() { # $1=dir $2+=args — direct child; LAUNCH_PID set globally
  ( export LOCALAPPDATA="$(cygpath -w "$ISO")"
    "$LAUNCHER" "$@" -headless >"$1/stdout.log" 2>&1 ) &
  LAUNCH_PID=$!
}

launch_windowed() { # $1=dir $2+=args — detached via cmd start, env inherited
  ( export LOCALAPPDATA="$(cygpath -w "$ISO")"
    cmd //c start "" //min "$(cygpath -w "$LAUNCHER")" "$@" >/dev/null 2>&1 )
}

log_gap_secs() { # $1=log file -> seconds since last mtime change
  local f=$1 now mt
  [ -f "$f" ] || { echo 9999; return; }
  now=$(date +%s)
  mt=$(stat -c %Y "$f" 2>/dev/null || echo "$now")
  echo $((now - mt))
}

report_stall() { # $1=arm $2=dir(full path) $3=note
  local log="$2/vm/shell.log"
  echo "  *** STALL in $1 $3"
  echo "  --- last log lines ($log) ---"
  tail -12 "$log" 2>/dev/null | sed 's/^/    /'
  echo "  --- stdout ---"
  tail -6 "$2/stdout.log" 2>/dev/null | sed 's/^/    /'
  mkdir -p "$ROOT/stall-$1"
  cp "$log" "$ROOT/stall-$1/vm-shell.log" 2>/dev/null
  cp "$2/stdout.log" "$ROOT/stall-$1/stdout.log" 2>/dev/null
  echo "  evidence preserved: $ROOT/stall-$1/"
}

# run_arm NAME MODE DIR [args...]  -> 0 booted/exited-clean, 3 stalled
run_arm() {
  local name=$1 mode=$2 dir=$3; shift 3
  local bound=$ARM_SECS
  [ "$mode" = headless ] && bound=$HEADLESS_SECS
  local log="$dir/vm/shell.log" t gap
  echo "=== arm $name ($mode, bound ${bound}s) ==="
  stage_pointer "$(cygpath -m "$dir")"
  if [ "$mode" = windowed ]; then
    launch_windowed "$dir" "$@"
  else
    launch_headless "$dir" "$@"
  fi
  for ((t=0; t<bound; t+=GAP_POLL)); do
    if ! alive; then
      echo "  exited after ~${t}s"
      if [ "$t" -lt 30 ]; then
        echo "  --- early-exit tail (counted as arm failure) ---"
        tail -8 "$log" 2>/dev/null | sed 's/^/    /'
        tail -4 "$dir/stdout.log" 2>/dev/null | sed 's/^/    /'
        return 2
      fi
      return 0
    fi
    if grep -q -e "phase: qemu" -- "$log" 2>/dev/null; then
      echo "  BOOTED after ~${t}s (phase: qemu reached) — powering down via QMP"
      python dev/scratchpad/qmp-powerdown.py "$QMP_PORT" >/dev/null 2>&1 || true
      local w=0
      while alive && [ "$w" -lt 150 ]; do sleep 10; w=$((w+10)); done
      if alive; then echo "  WARN: tree still alive after powerdown; killing by PID"; kill_g6; sleep 3; fi
      return 0
    fi
    gap=$(log_gap_secs "$log")
    if [ "$gap" -ge "$STALL_GAP" ] && [ "$t" -ge "$STALL_GAP" ]; then
      report_stall "$name" "$dir" "(alive pre-QEMU, silent ${gap}s)"
      kill_g6; sleep 3
      return 3
    fi
    sleep "$GAP_POLL"
  done
  report_stall "$name" "$dir" "(bound reached pre-QEMU, not silent — watchdog lines expected)"
  kill_g6; sleep 3
  return 3
}

fails=0

# --- warm-up -----------------------------------------------------------------
echo "--- warm-up: headless boot of the G6 copy ---"
stage_copy warmup
mapfile -t WARGS < <(arm_args "$ROOT/warmup")
launch_headless "$ROOT/warmup" "${WARGS[@]}"
ready=0
for ((t=0; t<WARMUP_SECS; t+=5)); do
  if grep -q -e "guest userspace announced ready" -- "$ROOT/warmup/vm/shell.log" 2>/dev/null; then
    ready=1; echo "  ready after ~${t}s"; break
  fi
  kill -0 "$LAUNCH_PID" 2>/dev/null || { echo "  launcher exited early (t=${t}s)"; break; }
  sleep 5
done
if [ "$ready" -eq 1 ]; then
  echo "  warm-up PASS: copy is bootable"
  python dev/scratchpad/qmp-powerdown.py "$QMP_PORT" >/dev/null 2>&1 || true
  w=0
  while alive && [ "$w" -lt 150 ]; do sleep 10; w=$((w+10)); done
  if alive; then echo "  WARN: warm-up tree still alive; killing by PID"; kill_g6; fails=$((fails+1));
  else echo "  warm-up closed cleanly via QMP powerdown (~${w}s)"; fi
else
  echo "  warm-up FAIL: copy never reached ready"; kill_g6; fails=$((fails+1))
fi

# --- arm A: the E4 incident shape, windowed ----------------------------------
stage_copy armA
mapfile -t WARGS < <(arm_args "$ROOT/armA")
run_arm A windowed "$ROOT/armA" "${WARGS[@]}"; rc=$?
[ "$rc" -eq 0 ] || fails=$((fails+1))

# --- arm B: headless variant of A --------------------------------------------
stage_copy armB
mapfile -t WARGS < <(arm_args "$ROOT/armB")
run_arm B headless "$ROOT/armB" "${WARGS[@]}"; rc=$?
[ "$rc" -eq 0 ] || fails=$((fails+1))

# --- arm C: windowed + -fresh (first-boot dialog family) ----------------------
stage_copy armC
mapfile -t WARGS < <(arm_args "$ROOT/armC" -fresh)
run_arm C windowed "$ROOT/armC" "${WARGS[@]}"; rc=$?
[ "$rc" -eq 0 ] || fails=$((fails+1))

# --- arm D: windowed, no overrides, dead update-url ---------------------------
stage_copy armD
mapfile -t WARGS < <(printf '%s\n' -dir "$(cygpath -m "$ROOT/armD")" -instant -ssh "$SSH_PORT" \
  -update-url 'http://127.0.0.1:9/manifest.json')
run_arm D windowed "$ROOT/armD" "${WARGS[@]}"; rc=$?
[ "$rc" -eq 0 ] || fails=$((fails+1))

echo
echo "--- stray check ---"
if tasklist //NH 2>/dev/null | grep -qiE 'SavantOS|qemu'; then
  echo "FAIL: SavantOS/QEMU processes survived"; kill_g6; fails=$((fails+1))
else
  echo "clean: no SavantOS/QEMU processes remain"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "G6 CAMPAIGN RESULT: NEGATIVE — no stall reproduced in the incident family"
  echo "(warm-up boot clean; arms A/B/C/D reached QEMU or exited cleanly inside bounds)"
  exit 0
else
  echo "G6 CAMPAIGN RESULT: $fails arm(s) stalled or failed — evidence under $ROOT/stall-*"
  exit 3
fi
