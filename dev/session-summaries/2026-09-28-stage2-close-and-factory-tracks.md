# Session Summary: 2026-09-28 (stage-2 closure; factory + delta tracks)

**Session ID:** 2026-09-28-stage2-close-and-factory-tracks
**Duration:** 2026-09-28 (commits `8dc034f` 10:37 → `38c77e1` 17:13)
**Status:** completed

> **Provenance note:** this summary was RECONSTRUCTED on 2026-10-03 from the
> commit history, FID-2026-0916-001 / -0915-002 / -0928-001 / -0914-002, and
> SCOPE.md's 2026-09-28 sections, per the operator's standing backfill
> ruling (2026-09-27). It is an evidence-based record, not a witness
> account; the primary records remain canonical.

---

## Initial State

- **Branch:** main, at `6b529ff` (close-ladder verdict fix, landed 09-28
  with operator approval); the 09-27 FID/CHANGELOG reconciliation pass had
  just closed.
- **Known issues:** stage-2 acceptance was GATE GREEN but uncommitted
  tooling and the polkit/ladder/T1.2 work sat uncommitted in the tree
  (commit grouping = operator call); G6 ruled out sample staging.

## Work Completed

### Dev tooling + shell suites in CI (`8dc034f`, 10:37)

- **Status:** completed (FIDs 0916-001, 0915-002, 0928-001, 0922-001)
- Re-seedable `dev-vm.sh init` (`--reseed` via rename-to-backup, no
  `rm -rf`; refuses under a live guest; empty-dir path fail-closed) —
  `scripts/dev/test-dev-vm-init.sh` 33/33.
- Close/relaunch acceptance driver (`scripts/dev/accept-close-cycles.sh` +
  the PowerShell trigger) with PID-scoped recovery, QEMU-stray preflight,
  and a teardown trap; superseded scratchpad copies removed (one truth).
- Three Windows-only shell suites moved from scratchpad to
  `scripts/dev/test-*.sh` and wired into the `windows-launcher` CI job
  (33 + 28 + 31 = 92 assertions).

### Polkit authorization for the close ladder (`0131c9d`, 12:18)

- **Status:** completed (FID-2026-0928-001, ruling F1)
- `guest-image/skeletons/etc/polkit-1/rules.d/50-savantos-power.rules`
  grants `savant` the whole power-off action family (bare,
  `-multiple-sessions`, `-ignore-inhibit`) — the escalation rung can now
  succeed; live proof owed to the next image.

### Stage-2 exit evidence + G6 ruling record (`dbc9e59`, 12:19)

- **Status:** completed (FID-2026-0916-001)
- Stage-2 exit table (damaged/partial installs refuse before network I/O;
  runtime-only and anchored dirs proceed; the pointer-shaped incident
  re-refuses) and the G6 ruling (real targets only, approval per launch)
  recorded.

### T1.2 headless `-fresh` reset (`5559cf7`, 12:19)

- **Status:** completed (T1.2, FID-2026-0916-001)
- `-headless` is the explicit reset confirmation; honors a pending cancel;
  unit-locked (`TestHeadlessResetConfirmProceeds`,
  `TestHeadlessResetConfirmHonorsCancellation`); consumer documented as
  `dev-vm.sh boot -fresh -headless`. Live proof on a real target remains
  operator-gated.

### T1.3 dual-build baseline + publish-tail hardening (`f8c6014`, 16:59)

- **Status:** completed (FID-2026-0914-002 / master plan T1.3 / 0928-001)
- Dual-build gate green twice (run 2 byte-identical: rootfs
  `a2dbea53…`); baseline published to `out/contract` + `release-base.json`
  carrying the polkit rule; the recurring publish-tail busy-handle fixed
  (trap released after the verdict, 6×10 s retries, residual failure keeps
  `build-a/contract` + hand-publish instructions).

### T2.1 delta design of record (`38c77e1`, 17:13)

- **Status:** completed (FID-2026-0914-002 T2.1 section)
- casync-only design over the F1–F7 contract; format facts
  probe-verified; reader + emission implementation followed same day
  (recorded in the 2026-09-29 summary).

## Validation

- App gates green both targets; shell suites green from their new
  location; `bun run lint:md` green; CI green on the pushed commits
  (runs for `8dc034f` and later all success, including the ubuntu race
  suite).

## Issues Discovered

- Publish-tail busy-handle, third occurrence — hardened in `f8c6014`
  (resolved this session; see the 09-29 summary for the next occurrence).
- The ladder-verdict loss (`6b529ff`, landed earlier the same day) —
  resolved.

## Next Session

- Land the T2.1 reader + builder emission; run the E2E N+1 chain; the
  T1.2/polkit live proofs stay operator-gated.
