# Session Summary: 2026-09-27

**Session ID:** 2026-09-27-fid-record-reconciliation
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 host (bash shell, bun docs toolchain)
- **Branch:** `main` @ `9b4789d` (feat(clipboard): symmetric guest-to-host
  image push)
- **Protocol:** ECHO single-agent (`dev/echo-v0.1.2-single-agent.md`),
  automation level 3 within the SCOPE.md-approved program

### Known Issues

- 17 active FIDs in `dev/fids/` with un-audited status metadata
- CHANGELOG.md last covered the 0916/0917-era work; 0917-002 and 0922-001
  landed commits with no entries

---

## Planned Work (operator-approved 2026-09-27)

1. [x] Audit the FID record (placement, status values, ground truth)
2. [x] Organize misplaced FIDs (close/archive, normalize metadata)
3. [x] Bring CHANGELOG.md fully in line (backfill + taxonomy)
4. [x] Verify with the docs gate and record everything

---

## Work Completed

### Task 1: FID audit (RED)

- **Status:** completed
- **Findings:** closed-but-unarchived FID-2026-0915-006; invalid status
  values on FID-2026-0914-003 (`proven`) and FID-2026-0917-002 (free
  prose); FID-2026-0912-001 carried a Closed-Date claim against a
  `converged` status plus an empty `REQUIRED for closed` placeholder;
  FID-2026-0915-005's "implementation queued" was stale (m1+m2 landed);
  FID-2026-0912-002's absorbed proofs had since been delivered by
  FID-2026-0913-001. All commit references verified to exist.

### Task 2: FID organization

- **Status:** completed
- **Archivals (this is the auto-archive log):** FID-2026-0912-002 (high,
  closed 2026-09-15), FID-2026-0914-003 (high, closed 2026-09-15), and
  FID-2026-0915-006 (medium, closed 2026-09-16) moved from `dev/fids/`
  to `dev/fids/archive/` with completed Resolution records.
- **Record fixes:** status values normalized to the allowed set;
  FID-2026-0912-001 placeholder replaced with a closure evidence map;
  FID-2026-0914-003's Loop 3 moved above Resolution (was after it).
- **Verification:** grep of section order + status fields; active set is
  14 FIDs, none claiming `closed`.

### Task 3: CHANGELOG.md

- **Status:** completed
- **Changes Made:**
  - 10 missing landed-work entries backfilled (FID-2026-0912-001,
    0912-002, 0913-001, 0914-002 step 2, 0914-003, 0915-005, 0915-006,
    0917-002, 0922-001, cursor fix)
  - Features section merged into Added (one taxonomy:
    Added/Changed/Removed/Fixed/Documentation/Governance)
  - FID closure record added under Documentation
- **Verification:** heading map + FID-reference count greps; docs gate.

---

### Task 4: Stage-1 re-baseline (completion program)

- **Status:** completed
- **Changes Made:**
  - `app/provision_contract.go` (new): platform-neutral
    `provisionSentinel` const — fixes Linux-target vet/test compile
    (`undefined: provisionSentinel`, regression from the provisioning
    landings); `provision_key.go` now points at it
  - `scripts/release/build-guest.sh` + `guest-image/build.sh`: direct
    execs of 644-mode scripts → explicit `bash` invocation (remote CI
    run #91 Guest-contract died at exit 126; invisible under Git Bash)
  - Stage-1 re-baseline recorded in the master plan addendum + SCOPE.md
- **Verification:** full gate set green on the current tree (app both
  targets, guest-daemon, `--contract-only`, release tooling 10/10,
  runtime lock, docs); remote CI run #91 decoded via read-only API
  (both red-job root causes identified and fixed in-tree)

### Task 5: Watchdog race fix (CI run #92 finding)

- **Status:** completed
- **FIDs Created/Updated:** FID-2026-0916-001 (race confirmed + fixed)
- **Changes Made:** `app/phase_core.go` (tuning snapshot into the
  watchdog goroutine + `stopWatchdog()`), `app/phase_core_test.go`
  (cleanup retirement in every phase test)
- **Verification:** build/vet/test/fmt green both targets; CI race suite
  on the fix commit is the `-race` acceptance evidence (no gcc locally)

### Task 6: Scope rulings pass (mislabels, build.sh CLI, T1.1, trio)

- **Status:** completed
- **Operator rulings received (all four SCOPE.md open items):**
  1. fix the mislabels (FID-2026-0915-002's status stays — it is
  correct); 2. fix the `build.sh` CLI now; 3. implement T1.1 now;
  4. close the historical trio as resolved.
- **Changes Made:**
  - Mislabels corrected (ground truth `git log -- app/closeguard.go`:
    untouched since the rebrand — no close-flow fix ever landed):
    FID-2026-0915-006's Sep-16 clean-exit note reattributed to the
    0914-003 PowerDevil seed (`powerButtonAction=8`); FID-2026-0917-002's
    two reset-refusal notes reattributed to the pre-existing
    `guestPending` reset guard (`payload-update-state.json`)
  - `guest-image/build.sh`: fail-closed arg loop — any argument →
    `Unknown argument: …` + exit 2 before any build work (parity with
    `build-guest.sh`); closes the accidental-`--contract-only` defect
    recorded in FID-2026-0915-006 (annotated there)
  - T1.1 (FID-2026-0915-001): `guest-image/assemble.sh` normalizes
    `/usr` + `/usr/share` to 0755 before the tar stream (per-path policy
    per the decision register — a flat 0755 would strip setuid/0600
    modes) and the daemon-file normalization moved there too (it sat
    AFTER the tar stream — dead code, a stage-1 defect-ledger item);
    debugfs image-content mode assertion gates the shipped modes
    (`/usr`+`/usr/share` 755, savant-core 755, unit+preset 644)
  - Records: SCOPE.md ruling record + all six open items closed
    (incl. the historical trio, evidence-verified); master plan T1.1
    row, decision point 4, defect ledger, and a same-day status update
- **Verification:** `bash -n` both scripts; negative run
  (`build.sh --contract-only`) exits 2 with the rejection message;
  mode-extraction probe verified against 4- and 6-digit debugfs `Mode:`
  formats; full gate set green below.

## Validation Results

- [x] `bun run lint:md` on changed docs: PASS (zero violations)
- Go gates not run in tasks 1–3 — zero product-code changes there

Rulings-pass gates (2026-09-27, fresh, all green):

- [x] `app/`: build + `go vet -unsafeptr=false` + `go test -count=1`
  (ok 10.6s) + `gofmt -l` — clean
- [x] `app/` Linux target (`GOOS=linux GOARCH=amd64 CGO_ENABLED=0`):
  vet + `go test -c` compile — clean
- [x] `guest-daemon/savant-core/`: vet + test (ok 0.24s) + gofmt — clean
- [x] `scripts/release/build-guest.sh --contract-only` — PASS
  (snapshot-lock OK, savant-core gate OK)
- [x] `bun run lint:md` + `git diff --check` — clean
- [x] `bash -n` on `guest-image/build.sh` + `guest-image/assemble.sh`;
  negative run exits 2 as designed

---

## Open Questions

- None — the three SCOPE.md `[OPEN-OUT-OF-SCOPE]` items and the
  historical trio were all ruled on 2026-09-27 and are settled (Task 6
  + the ruling record in SCOPE.md).

---

## Next Session

### Priority Tasks

1. [x] DONE 2026-09-27: the operator ratified incorporation and
   directed "all work pushed in full" — everything landed through
   `8f8874b`; CI runs 36351604844 (`82e1ded`) and 36352329369
   (`8f8874b`) are green on all three jobs including the race suite
   (the watchdog race was confirmed there and fixed)
2. [ ] Stage 2 (launcher protection) per the approved sequence

### Notes for Next Agent

- FID status metadata was reconciled against the codebase on 2026-09-27;
  treat `dev/fids/archive/` as complete through FID-2026-0915-006.
- SCOPE.md has zero open items after the 2026-09-27 rulings pass; the
  full-tree permissions policy (beyond T1.1's per-path set) is the
  factory-design-checkpoint decision.
