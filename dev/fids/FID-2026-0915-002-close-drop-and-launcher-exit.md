# FID: Intermittent close-drop and silent launcher exit (dev-loop reliability)

**Filename:** `FID-2026-0915-002-close-drop-and-launcher-exit.md`
**ID:** FID-2026-0915-002
**Severity:** medium-high
**Status:** verified — both fixes implemented 2026-09-27; the 10-cycle close
and relaunch acceptance passed 2026-09-28 (see Acceptance evidence below)
**Created:** 2026-09-15
**Parent:** FID-2026-0914-003 (window close / PowerDevil) — this is a
regression-shaped intermittent residue of the same mechanism
**Master plan:** FID-2026-0915-001 T0.3 finding

---

## Summary

During the 2026-09-15 committed-tree boot proof, two launcher-reliability
defects surfaced in one session:

1. **Intermittent close-drop (the seed did not always work).** The
   operator's 13:20:45 EDT close of a healthy, seeded guest produced
   `close confirmed - graceful guest shutdown` in the launcher log, the
   ACPI event arrived in the guest (`systemd-logind: Power key pressed
   short.` at 17:20:45 UTC — exact match), and then **nothing**: no
   shutdown target, no job, no further logind line. PowerDevil was alive
   since boot and still holding its `handle-power-key` block inhibitor,
   and the seed file was intact
   (`[AC][HandleButtonEvents] powerButtonAction=8`). The identical setup
   at 11:46 shut the guest down in ~5 s. Conclusion: PowerDevil's
   power-button handler **silently dropped the event** — an intermittent
   failure mode, plausibly timing- or session-state-dependent (the failed
   session had been running ~70 minutes with heavy host-side GPU
   interaction), that no external observer can distinguish from the
   pre-fix bug.
2. **Silent launcher exit during boot.** The launcher launched at 14:06
   logged `taskbar identity set` (14:06:53) and then exited with no log
   line, no Windows Error Reporting record, and no crash dump, orphaning
   QEMU (which kept running; the guest reached multi-user with zero
   failed units). A relaunched instance at 14:17 (stderr redirected to a
   file, this time surviving) completed the boot proof in ~12 s — so the
   exit is intermittent and plausibly a race with the just-killed
   predecessor's ports/disk handle (this was the second launch after a
   forced QEMU cleanup).

## Root cause status

- (1) Not root-caused: PowerDevil's event-handling path is inside KDE
  source; the observable contract break is enough to design around.
- (2) Not root-caused: no crash artifact exists; the exit was silent by
  definition. Needs a launcher-side change to even be observable.

## Proposed fix (design of record)

**Stop depending on PowerDevil for the close contract — make the launcher
authoritative.** The close flow should not rely on a guest desktop daemon
that (a) can silently drop events and (b) is a moving KDE target. The
already-proven fallback sequence (which worked both times the seed failed
or was absent) should be the PRIMARY mechanism, with the ACPI powerdown as
the graceful first attempt:

1. QMP `system_powerdown` (graceful, works when PowerDevil cooperates).
2. After a short bounded window (e.g. 10 s), verify via QMP
   `query-status`/SHUTDOWN event that the guest is actually going down.
3. If not: guest-side `systemctl poweroff -i` through the existing
   privileged path (the launcher's ssh/lifecycle plane), then QMP
   `system_powerdown` again.
4. Final fallback (already exists): `waitExit`'s wedged-QEMU kill.

This keeps every property of today's flow (graceful when possible) and
removes the single point of silent failure. Filing in T1 scope: it is
launcher-only, no image rebuild needed, and it retires the depend-on-
PowerDevil assumption without redoing the Option B seed (which remains
correct for the in-guest power-button UX).

For (2): the launcher must never exit silently — before any exit path
during boot (`logf` wrapper and the `fatal()` path in main.go), write the
reason to `vm/shell.log`. A port-collision race deserves an explicit
pre-flight check (bind the lifecycle port before touching the disk) with a
user-visible error, not a silent exit.

## Verification

- Close contract: 10 consecutive close cycles on the dev loop with zero
  hangs (powerdown accepted OR fallback executed; QEMU always exits).
- Boot: 10 consecutive relaunch cycles including one forced-kill
  predecessor — launcher never exits without a logged reason.

## Verification Gates

- gate: build/vet/test/fmt per protocol.config.yaml
- gate: the 10-cycle close + relaunch evidence pasted into this FID

## Perfection Loop

### Loop 1 — Diagnosis (2026-09-15, boot-proof session)

- **RED:** "The seed regressed" — tested and rejected: config byte-identical
  to the 11:46 proof; PowerDevil alive; inhibitor held. The difference is
  the RESPONSE, not the config. "The launcher was killed externally" —
  rejected: no WER record, no crash dump, no stderr output (stderr was
  unredirected in the failing run; the successful run redirected it, which
  is itself the mitigation evidence).
- **GREEN:** Both defects converted to designed fixes (above) with named
  verification gates. The 13:20 stall was first misread as "old log"
  because the tail grep matched stale content — the shell.log-grep pattern
  must always anchor on the last `---- SavantOS starting ----` marker
  (lesson recorded in the session summary).
- **ADVERSARIAL:** "Just kill QEMU on close." — Rejected: discards guest
  state and defeats the graceful contract; the ladder keeps graceful
  first.
- **CHANGE DELTA:** n/a (new document).
- **Convergence declared:** analyzed; implementation queued under T1 of
  the master plan.

## Implementation evidence — 2026-09-27 (Stage 2 pass 1)

Both fixes from the design of record are implemented (launcher-only, no
image change):

- **Bounded close ladder** (`app/close_ladder.go`, wired from
  `runCloseGuard`): a confirmed close now runs the full ladder — QMP
  `system_powerdown`, a bounded 10 s verify (QEMU pid plus QMP
  `query-status`; only an explicit shutdown status reads as "going
  down"), then the guest-side privileged shutdown over the session's
  ssh plane (`systemctl poweroff -i` — `-i` is `--ignore-inhibitors`,
  verified against systemd's docs; the PowerDevil block inhibitor is
  exactly what dropped the original event — authorized by the factory
  polkit rule 50-savantos-power.rules shipped for FID-2026-0928-001;
  until that rule landed the rung was polkit-denied and fell through
  to the forced stop) with a second powerdown, a
  20 s verify, and finally the forced stop this confirmed close already
  authorizes (the waitExit-class QEMU kill, reaped by the supervisor).
  Every step logs to `vm/shell.log`, so a dropped power event can never
  again look like a clean close. Sessions without an ssh forward log
  the missing escalation plane and stay bounded. The policy core is
  platform-neutral and unit-tested: graceful, escalate-then-down,
  force-stop, and no-plane paths all green.
- **Never-silent-exit:** `fatal()` flushes the durable early log
  (`vm/shell.log`) before exiting; `main` drains it on quiet returns;
  every boot exit path logs its reason (`exit: …`); the bare
  `errorBox`+`os.Exit` sites route through `fatal`. The port-collision
  pre-flight from the design already existed (`runLifecycleListener`
  binds before the disk is touched and fatals with a user-visible
  error) and its reason is now durable too. Proven live: the
  incident-shape regression run of FID-2026-0916-001 (its G2) wrote the
  FATAL line to `vm/shell.log` from an exit path that predates the
  session log.
- **Verification:** build/vet/test/fmt clean on both targets; ladder
  unit suite green. **Blocked (needs an approved disposable VM
  target):** this FID's Verification gates — 10 close cycles with zero
  hangs, and 10 relaunch cycles including a forced-kill predecessor.

## Acceptance evidence — 2026-09-28

The Verification gates above are met. Evidence:
`dev/scratchpad/accept-close-cycles.log` (run) and
`dev/scratchpad/accept-close-cycles-20260927.log` (the first run).

**Result:** `SUMMARY closes=10/10 sessions=11 failures=0`,
`ladder: graceful=10 escalated=0 forced=0`, `VERDICT: GATE GREEN` against
`C:\Users\spenc\savantos-accept` (disposable, operator-authorized), launcher
digest `5d1465dd086a3878` at HEAD `9da3650`. Every session logged an exit
reason; no hang; the session-6 forced-kill predecessor (QEMU killed by PID)
had its relaunch complete normally.

### Record drift found and corrected (Ground-Truth rule)

The first run of this gate happened on 2026-09-27 at 20:23 and was already
GATE GREEN (10 cycles, 11 sessions, 0 failures). `SCOPE.md`,
this FID's status line, and FID-2026-0916-001 all still described the
acceptance as blocked/pending. The record was wrong, not the code: the
evidence existed and nobody had reconciled it. Per the Ground-Truth rule
the record now carries the verified result.

### Defect found while assembling the evidence: the ladder verdict was lost

`close_ladder.go` promises that "every step is logged so a dropped power
event can never again look like a clean close". That promise was not met in
any of the 11 sessions run on 2026-09-27: the rung line ("guest is shutting
down ...", "forcing QEMU to stop") appeared **0 times** while "close ladder:
power button sent" appeared 11 times.

Cause: `runCloseGuard` started the ladder as a bare `go runCloseLadder(...)`.
The main goroutine sits in `supervise()`, which returns the moment QEMU
exits; main then logs `---- exiting ----` and returns, killing the ladder
goroutine mid-poll before it could log which rung fired. `logf` is
unbuffered, so this was a lost line, not a flush artifact. The consequence is
exactly the ambiguity the ladder exists to remove — a dropped power event
would still have looked like a clean close, because the one line that proves
the ladder confirmed anything was the line that vanished.

Fix (launcher-only): `startCloseLadder` registers the ladder as in flight and
signals a verdict channel; `main` calls `awaitCloseLadderVerdict` before
`---- exiting ----`, bounded by `ladderWorstCase()` (the ladder's own two
verify windows plus a 10 s margin, so the wait can never be shorter than the
work). A ladder that cannot finish is logged and the process still exits — an
exit with a missing line beats an exit that never happens. Unit coverage:
idle returns immediately, an in-flight ladder is waited for, the wait is
bounded and says so, and `ladderWorstCase` exceeds the ladder it waits for.

Live proof: after the fix the rung line precedes `---- exiting ----` in
every close session, and the target's own `vm/shell.log` carries 17 rung
lines where it previously carried none.

### Defect found in the acceptance driver itself

The driver's first full run reported a false RED: "session 6: launcher still
running 240s after close (HANG)". The launcher was healthy; the driver had
failed to kill QEMU. `tasklist //FI "IMAGENAME eq qemu-system-x86_64w"`
matches nothing when the image name is given without its `.exe` suffix, so
the PID list was always empty — which made the stray-VM preflight
vacuously true and the forced-kill a no-op. The QEMU was still running and
still exchanging clipboard traffic three minutes after the "kill".

Fixed by parsing `tasklist //NH` output directly (matching the image name
with or without `.exe`) and by adding a `process_list_readable` guard: if
the process list cannot be read, the driver refuses to run rather than
reporting a clean host. Regression coverage drives all three states through
the driver with a shimmed `tasklist`: a stray QEMU (refuses, names the PID),
a clean host (passes), and an unreadable list (refuses).
