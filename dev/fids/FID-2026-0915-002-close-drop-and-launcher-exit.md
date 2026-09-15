# FID: Intermittent close-drop and silent launcher exit (dev-loop reliability)

**Filename:** `FID-2026-0915-002-close-drop-and-launcher-exit.md`
**ID:** FID-2026-0915-002
**Severity:** medium-high
**Status:** analyzed (both reproduced with evidence; fixes designed, not implemented)
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
