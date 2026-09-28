#!/bin/bash
# Close/relaunch acceptance driver for FID-2026-0915-002's verification
# gates: 10 close cycles with zero hangs, and 10 relaunch cycles including
# one forced-kill predecessor, on an operator-authorized disposable target.
#
# WHAT IT ASSERTS, PER SESSION
#   ready   - the guest announces userspace ready (app/main.go logf)
#   closed  - the REAL close path ran: the trigger probes the caption close
#             button's hit-test, clicks it, and accepts the confirmation
#             (scripts/dev/accept-close-trigger.ps1)
#   exited  - the launcher always exits, and leaves a logged reason
#             ("---- exiting ----" on success, "FATAL" on an error path)
#   rung    - which rung of the close ladder fired: graceful, escalated, or
#             forced. Ten samples of this is the actual signal.
#
# SAFETY RULES BUILT IN (see the decision register in the master plan)
#   * Refuses to start without --authorized-disposable-target, because VM
#     operations and data-dir resets are not implied by headless execution.
#   * Refuses to start if ANY qemu-system-x86_64w is already running. The
#     close trigger picks its window by process name, so a stray second VM
#     would mean clicking the wrong window's close button.
#   * Never kills by image name. Teardown is PID-scoped (taskkill /T) and
#     only ever touches processes this driver started, so an operator's own
#     interactive dev VM cannot be destroyed by a failed run.
#   * An EXIT/INT/TERM trap guarantees teardown: nothing here reaps orphans.
#   * Reseed guidance instead of touching the data dir itself.
#
# USAGE
#   scripts/dev/accept-close-cycles.sh --authorized-disposable-target
#   SAVANTOS_ACCEPT_DIR=/path/to/target scripts/dev/accept-close-cycles.sh \
#       --authorized-disposable-target
#
#   CLOSES=1 gives a single-cycle smoke run; the full gate wants CLOSES=10.
#   FORCE_AFTER=0 skips the forced-kill predecessor session entirely, which
#   is what a clean one-cycle smoke wants.
#   --preflight-only runs every authorization, target and build check and
#   exits without launching a VM, so a target can be validated before
#   committing to a run that takes tens of minutes.
#
# INVOCATION NOTE: this run takes tens of minutes and starts a VM, so run it
# detached with its own output redirected, or it will hold the calling
# terminal's stdout pipe open for the whole run:
#   nohup scripts/dev/accept-close-cycles.sh --authorized-disposable-target \
#       >/dev/null 2>&1 &

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="${SAVANTOS_ACCEPT_DIR:-$USERPROFILE/savantos-accept}"
SHARE_DIR="${SAVANTOS_ACCEPT_SHARE:-$USERPROFILE/savantos-accept-share}"
SSH_PORT="${SAVANTOS_ACCEPT_PORT:-2222}"
QMP_PORT=4450
OUT="${SAVANTOS_ACCEPT_LOG:-$REPO/dev/scratchpad/accept-close-cycles.log}"
TRIGGER="$REPO/scripts/dev/accept-close-trigger.ps1"
LAUNCHER_EXE="$REPO/app/SavantOS-dev.exe"

CLOSES="${CLOSES:-10}"          # close cycles required by the gate
FORCE_AFTER="${FORCE_AFTER:-5}" # force-kill session lands after this many
READY_TIMEOUT="${READY_TIMEOUT:-900}"  # first session provisions payload+runtime
EXIT_TIMEOUT="${EXIT_TIMEOUT:-240}"    # ladder worst case (~35s) + supervisor reap

shelllog="$DEV_DIR/vm/shell.log"
authorized=0
preflight_only=0
closes=0
sessions=0
failures=0
graceful=0
escalated=0
forced=0
declare -a qemu_baseline=()
rung_name=none

# ---------------------------------------------------------------- helpers

log() { printf '%s %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT"; }
red() { log "RED  $*"; }
qemu_pids() { tasklist //NH 2>/dev/null | parse_qemu_pids; }
# Parse QEMU PIDs out of `tasklist //NH` output rather than trusting
# tasklist's IMAGENAME filter: that filter matches nothing when the image
# name is given without its .exe suffix, and a probe that silently returns
# empty is indistinguishable from "no QEMU running" - which would make the
# preflight below vacuously safe and the forced-kill a no-op.
parse_qemu_pids() { awk '$1 ~ /^qemu-system-x86_64w(\.exe)?$/ && $2 ~ /^[0-9]+$/ {print $2}'; }
# True when `tasklist //NH` produced at least one line this parser can read.
# Checked by shape rather than by header text: tasklist's first line is blank
# on this host and the header is optional, so any header assumption is a
# brittle way to tell "no processes" from "no process list".
process_list_readable() {
    tasklist //NH 2>/dev/null | awk 'NF>=2 && $2 ~ /^[0-9]+$/ {found=1} END {exit found?0:1}'
}
port_busy() { netstat -an 2>/dev/null | grep -q ":$1 .*LISTENING"; }
pid_alive() { kill -0 "$1" 2>/dev/null; }

# Kill one process tree by PID. Never by name.
kill_tree() {
    local pid=$1
    pid_alive "$pid" || return 0
    taskkill //F //T //PID "$pid" >/dev/null 2>&1
    local t
    for t in $(seq 1 20); do
        pid_alive "$pid" || return 0
        sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null
    return 0
}

# Reap only QEMUs that appeared after the baseline - an operator's own VM is
# in the baseline and therefore never touched.
reap_new_qemu() {
    local pid
    for pid in $(qemu_pids); do
        local seen=0 b
        for b in ${qemu_baseline[@]+"${qemu_baseline[@]}"}; do
            [ "$b" = "$pid" ] && seen=1
        done
        [ "$seen" -eq 0 ] || continue
        log "teardown: killing QEMU $pid (started by this run)"
        taskkill //F //PID "$pid" >/dev/null 2>&1
    done
}

teardown() {
    local rc=$?
    trap - EXIT INT TERM
    if [ -n "${boot_pid:-}" ]; then
        log "teardown: releasing launcher tree $boot_pid"
        kill_tree "$boot_pid"
    fi
    reap_new_qemu
    log "teardown: done (driver exit $rc)"
}
trap teardown EXIT
trap 'log "interrupted"; exit 130' INT
trap 'log "terminated"; exit 143' TERM

# ---------------------------------------------------------------- preflight

for arg in "$@"; do
    case "$arg" in
        --authorized-disposable-target) authorized=1 ;;
        --preflight-only) preflight_only=1 ;;
        *) echo "error: unknown option: $arg" >&2
           echo "       this driver needs --authorized-disposable-target" >&2
           echo "       (add --preflight-only to check without launching)" >&2
           exit 2 ;;
    esac
done

log "=== accept-close-cycles start ==="
if [ "$authorized" -ne 1 ]; then
    red "refusing to start without --authorized-disposable-target"
    log "VM operations against a data dir are not implied by a headless run."
    log "Re-run with the flag once the target is authorized, or point"
    log "SAVANTOS_ACCEPT_DIR at a disposable directory you own."
    log "VERDICT: NOT RUN"
    exit 2
fi
log "authorized target: $DEV_DIR"
log "share:            $SHARE_DIR"
log "ssh port:         $SSH_PORT   qmp port: $QMP_PORT"
log "plan:             $CLOSES close cycles, force-kill predecessor after $FORCE_AFTER"
log "host:             $(cmd //c ver 2>/dev/null | tr -d '\r')"

# The process list must be readable at all: without it the QEMU check below
# cannot fail closed, so an unreadable list is a stop, not a pass.
if ! process_list_readable; then
    red "cannot read the Windows process list (tasklist failed)"
    log "The stray-VM check depends on it, so this run would not be able to"
    log "tell a clean host from a busy one. Refusing rather than running blind."
    log "VERDICT: NOT RUN"
    exit 2
fi
log "preflight: process list readable"

# Baseline QEMU set, captured before anything starts.
mapfile -t qemu_baseline < <(qemu_pids)
if [ "${#qemu_baseline[@]}" -gt 0 ]; then
    red "refusing to start: qemu-system-x86_64w already running (pids: ${qemu_baseline[*]})"
    log "The close trigger selects its window by process name, so a stray"
    log "second VM would mean driving the wrong window. Shut it down first."
    log "VERDICT: NOT RUN"
    exit 2
fi
log "preflight: no pre-existing QEMU"

if port_busy "$QMP_PORT" || port_busy "$SSH_PORT"; then
    red "refusing to start: QMP $QMP_PORT or SSH $SSH_PORT is already bound"
    log "Another launcher instance may be running. Stop it first."
    log "VERDICT: NOT RUN"
    exit 2
fi
log "preflight: QMP and SSH ports free"

if [ ! -d "$DEV_DIR" ]; then
    red "target data dir does not exist: $DEV_DIR"
    log "Create it with the dev tooling first, e.g."
    log "  SAVANTOS_DEV_DIR='$(cygpath -w "$DEV_DIR")' \\"
    log "    scripts/dev/dev-vm.sh init --seed-from DIR --reseed"
    log "VERDICT: NOT RUN"
    exit 2
fi
if [ ! -f "$DEV_DIR/dev-anchor.json" ]; then
    red "target has no dev-anchor.json - it is not a dev-vm.sh data dir: $DEV_DIR"
    log "Refusing to run the acceptance against a dir this tool did not set up."
    log "VERDICT: NOT RUN"
    exit 2
fi
log "preflight: target is a dev data dir with an anchor"

if [ ! -f "$TRIGGER" ]; then
    red "missing close trigger: $TRIGGER"
    log "VERDICT: NOT RUN"
    exit 2
fi

if [ ! -f "$LAUNCHER_EXE" ]; then
    log "building dev launcher from the current tree"
    ( cd "$REPO/app" && go build -o SavantOS-dev.exe . ) || {
        red "launcher build failed"
        log "VERDICT: NOT RUN"
        exit 1
    }
fi
log "launcher: $(sha256sum "$LAUNCHER_EXE" | cut -c1-16)  (head $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null))"
log "tree:    $(git -C "$REPO" status --porcelain 2>/dev/null | wc -l) modified/untracked path(s)"

if [ "$preflight_only" -eq 1 ]; then
    log "preflight-only: every check passed; no VM was launched"
    log "VERDICT: PREFLIGHT OK"
    exit 0
fi

# ---------------------------------------------------------------- one session

# Classify which rung of the ladder fired from the session's own log slice.
# Sets rung_name and bumps the tally directly: running this inside $(...)
# would put the increments in a subshell and lose every count.
classify_rung() {
    local slice=$1
    rung_name=none
    if printf '%s' "$slice" | grep -q "forcing QEMU to stop"; then
        rung_name=forced
        forced=$((forced + 1))
    elif printf '%s' "$slice" | grep -q "shutting down after escalation"; then
        rung_name=escalated
        escalated=$((escalated + 1))
    elif printf '%s' "$slice" | grep -q "no escalation needed"; then
        rung_name=graceful
        graceful=$((graceful + 1))
    fi
}

run_session() {
    local kind=$1 n=$2
    sessions=$((sessions + 1))
    log "--- session $n ($kind) ---"

    local t
    for t in $(seq 1 60); do
        port_busy "$QMP_PORT" || break
        sleep 2
    done
    if port_busy "$QMP_PORT"; then
        red "session $n: QMP $QMP_PORT still bound before launch"
        failures=$((failures + 1))
        return 1
    fi

    local before=0
    [ -f "$shelllog" ] && before=$(wc -l < "$shelllog")
    SAVANTOS_DEV_DIR="$DEV_DIR" SAVANTOS_DEV_SHARE="$SHARE_DIR" \
        SAVANTOS_DEV_PORT="$SSH_PORT" \
        bash "$REPO/scripts/dev/dev-vm.sh" boot \
        >"$REPO/dev/scratchpad/accept-session-$n.log" 2>&1 &
    boot_pid=$!
    log "session $n: launched (driver pid $boot_pid, log accept-session-$n.log)"

    # Ready gate.
    local ready=0 elapsed=0
    for ((elapsed = 0; elapsed < READY_TIMEOUT; elapsed += 5)); do
        if tail -n +"$((before + 1))" "$shelllog" 2>/dev/null |
           grep -q "guest userspace announced ready"; then
            ready=1
            break
        fi
        if ! pid_alive "$boot_pid"; then
            log "session $n: launcher exited before the guest was ready"
            break
        fi
        sleep 5
    done
    if [ "$ready" -eq 1 ]; then
        log "session $n: guest ready after ${elapsed}s"
    else
        red "session $n: no guest ready signal within ${READY_TIMEOUT}s"
        failures=$((failures + 1))
    fi

    if [ "$kind" = force ]; then
        # Forced-kill predecessor: QEMU dies under the launcher, so the
        # launcher must notice and exit with a logged reason. Killing the
        # launcher instead would prove nothing about its own exit discipline.
        log "session $n: force-killing QEMU (predecessor ends hard)"
        for pid in $(qemu_pids); do taskkill //F //PID "$pid" >/dev/null 2>&1; done
    else
        # The real close contract, retried because a window that is not yet
        # mapped cannot be hit-tested.
        local ok=0 attempt res
        for attempt in 1 2 3; do
            res=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$TRIGGER" 2>&1)
            log "session $n: close trigger $attempt: $(printf '%s' "$res" | tr '\n' ' ')"
            if printf '%s' "$res" | grep -q 'RESULT=OK-CLOSE-CONFIRMED'; then
                ok=1
                break
            fi
            sleep 5
        done
        if [ "$ok" -ne 1 ]; then
            red "session $n: close trigger failed 3x"
            failures=$((failures + 1))
        fi
    fi

    # Exit gate: the launcher must always exit. This is the hang detector.
    local gone=0
    for ((elapsed = 0; elapsed < EXIT_TIMEOUT; elapsed += 5)); do
        pid_alive "$boot_pid" || { gone=1; break; }
        sleep 5
    done
    if [ "$gone" -ne 1 ]; then
        red "session $n: launcher still running ${EXIT_TIMEOUT}s after close (HANG)"
        failures=$((failures + 1))
        kill_tree "$boot_pid"
    fi
    wait "$boot_pid" 2>/dev/null
    log "session $n: launcher exit code $?"

    # Evidence: this session's slice of the durable log.
    local slice
    slice=$(tail -n +"$((before + 1))" "$shelllog" 2>/dev/null)
    if [ -n "$slice" ]; then
        printf '%s\n' "$slice" |
            grep -E 'close confirmed|close ladder|guest powered off|---- exiting ----|FATAL |exit:' |
            while IFS= read -r line; do log "session $n | $line"; done
    else
        red "session $n: no new shell.log lines - the launcher logged nothing"
        failures=$((failures + 1))
    fi

    # The ladder must have actually run, not merely the process have exited.
    if [ "$kind" = close ]; then
        if printf '%s' "$slice" | grep -q "close ladder:"; then
            classify_rung "$slice"
            log "session $n: ladder rung = $rung_name"
        else
            red "session $n: launcher exited without running the close ladder"
            failures=$((failures + 1))
        fi
    fi

    # Never-silent-exit property.
    if printf '%s' "$slice" | grep -qE -- '---- exiting ----|FATAL '; then
        log "session $n: logged exit reason present"
    else
        red "session $n: no logged exit reason"
        failures=$((failures + 1))
    fi

    if [ "$kind" = close ]; then
        closes=$((closes + 1))
        log "session $n: close cycle $closes/$CLOSES"
    fi
    boot_pid=""
    return 0
}

# ---------------------------------------------------------------- main

session=1
while [ "$closes" -lt "$FORCE_AFTER" ]; do
    run_session close "$session"
    session=$((session + 1))
done
if [ "$FORCE_AFTER" -gt 0 ]; then
    run_session force "$session"   # the forced-kill predecessor
    session=$((session + 1))
fi
while [ "$closes" -lt "$CLOSES" ]; do
    run_session close "$session"   # the first of these relaunches after the kill
    session=$((session + 1))
done

verdict=RED
if [ "$closes" -eq "$CLOSES" ] && [ "$failures" -eq 0 ]; then
    verdict=GREEN
fi
log "=== accept-close-cycles end ==="
log "SUMMARY closes=$closes/$CLOSES sessions=$sessions failures=$failures"
log "SUMMARY ladder: graceful=$graceful escalated=$escalated forced=$forced"
log "VERDICT: GATE $verdict"
[ "$verdict" = GREEN ] && exit 0
exit 1
