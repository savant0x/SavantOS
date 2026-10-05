# Session Summary: 2026-09-29 (T2.1 implemented + N+1 build; T2.2 recorded)

**Session ID:** 2026-09-29-t21-implementation-n1-build-t22
**Duration:** 2026-09-29 (commits `4fdec4d` 00:09 → `1b93430` 00:20; the N+1
build itself ran later that day, `out/t21-n1-build.log`)
**Status:** completed

> **Provenance note:** this summary was RECONSTRUCTED on 2026-10-03 from
> the commit history, FID-2026-0914-002's T2.1 sections, SCOPE.md, and the
> build log, per the operator's standing backfill ruling (2026-09-27). It
> is an evidence-based record, not a witness account.

---

## Initial State

- **Branch:** main at `38c77e1` (T2.1 design of record); builder emission
  and the launcher-side reader were the next approved steps.

## Work Completed

### T2.1 implementation (`4fdec4d` + `25710ec` + docs `6ee5861`/`1a10feb`/`c2236b1`, 00:09–00:11)

- **Status:** completed (FID-2026-0914-002 T2.1)
- Launcher: platform-neutral casync reader (`app/casync_reader.go`) —
  caibx parse, SHA-512/256 chunk verification, zstd chunk decode,
  sharded-directory + HTTP store backends, sparse seed-aware
  reconstruction; integrated at the `ensureGuest` rootfs branch with the
  unchanged full-image digest as the acceptance gate; fixtures committed
  under `app/testdata/casync`.
- Builder: `assemble.sh` emits `rootfs.ext4.caibx` + the sharded
  `rootfs.castr/` per assembly (explicit `--store` — the default store
  lands beside the index, not the cwd, which killed the first delta
  build); the caibx joined the dual-build gate (seven files); delta
  finalization runs pre-copy in the publish tail
  (`guest-image/delta-finalize.py`, validated by a 5-scenario battery on
  real casync bytes).
- Delta-build 2 GATE GREEN twice (`rootfs.ext4 ea574cb3…`, caibx
  `1b97d068…`); the first delta-capable release published as the bare
  caibx (sums `93add1f6…`); the N→N live reconstruction probe passed
  (44 s, digest-exact).
- RUNBOOK distilled (`guest-image/RUNBOOK.md`): prerequisites, procedure,
  every observed failure mode, post-run checklist.

### T2.2 range re-verification record (`1b93430`, 00:20)

- **Status:** completed (master plan T2.2)
- Resume suite (27 tests, real httptest servers) re-verified with
  Range-offset assertions, cross-call `.part` retention, and a
  double-interruption lifecycle test; operational caveat recorded
  (`python -m http.server` ignores Range — use docker for the delta E2E).

### The N+1 build (later that day, `out/t21-n1-build.log`)

- **Status:** gate green; publish FATAL
- A second payload built from the same tree: dual-build gate green
  (`rootfs.ext4 094df621…`, caibx `11792f4f…`, zero NONDETERMINISM).
- **The publish tail FATALed** on the busy `out/contract` handle: the
  published N payload was rm'd down to a husk before the handle blocked.
  Per the hardened tail, the gate-passed payload survived intact in
  `build-a/contract`. (Disposition + full analysis: FID-2026-0914-002's
  2026-10-03 E2E section; the 2026-10-03 session protected the survivors
  and measured the N→N+1 delta.)

## Issues Discovered

- **Publish-tail FATAL destroyed the previous release** (`out/contract`
  husked) — severity high; recorded and analyzed 2026-10-03 in
  FID-2026-0914-002; the previous-payload-protection gap is a named
  follow-up in SCOPE.md.

## Validation

- App gates green both targets; `bun run lint:md` green; CI green through
  `1b93430` (run 36521168277, all three jobs including the race suite).

## Next Session

- Protect the survivor payloads, measure the N→N+1 transfer, restore the
  local release base, and finish the E2E chain (done: see the 2026-10-03
  summary when written).
