# Session Summary: 2026-09-16 (evening) — completion plan approval + stage 1

**Session ID:** 2026-09-16-2100-completion-plan-stage1
**Duration:** single session, 2026-09-16
**Status:** completed (handoff to operator's main model)

---

## Initial State

### Environment

- **OS:** Windows (pwsh host); WSL Ubuntu available (no Go toolchain on PATH)
- **Language/Runtime:** Go 1.27.0 windows/amd64; bun/markdownlint; Python 3.14
- **Branch:** main @ `fd5a888`
- **Pre-existing dirty state (preserved, untouched):** `guest-image/build.sh`
  modified (missing-runtime warning → fail-closed `exit 1`); untracked
  `.agents/`, `.freebuff/`, `dev/scratchpad/*` artifacts.

### Known Issues (inherited)

- FID-2026-0916-001: D1/D1b/D1c designed, not implemented; D3 modal scope
  incomplete; G4 evidence weak; G5 partial.
- Static-audit findings across 14 active FIDs (see master-plan addendum).

---

## Planned Work

1. [x] Read ECHO 0-EOF; ground in project; inventory all pending work
2. [x] Outline eight-stage completion plan at automation level 3
3. [x] On operator approval: execute stage 1 (scope/baseline)
4. [ ] Stage 2+ (handed off)

---

## Work Completed

### Task 1: Grounding + pending-work inventory

- **Status:** completed
- Read ECHO.md, protocol.config.yaml, ARCHITECTURE.md, AGENTS.md, all 14
  active FIDs, SCOPE.md, master plan 0915-001, CI workflow, release
  tooling. Three read-only explore subagents produced per-FID inventories
  distinguishing implemented / awaiting-proof / missing / operator-decision.
- **Verification:** findings carry file:line citations in the master-plan
  addendum. Key: D1 unimplemented (`data_location.go:33-53` has no override
  guard); assemble.sh chmods daemon files AFTER image creation (lines
  217-224 vs 91-98); release workflow builds guest before prepare-assets,
  which then rejects the runtime entry prepare-assets must add; Cursor
  dual-build digest comparison PASSED in saved logs before publication
  failed; daemon `KILL` changes state but severs no capability
  (`control.go:171-183`).

### Task 2: Eight-stage completion plan (presented + approved)

- **Status:** completed — operator approved verbatim ("approve")
- Stages: 1 scope/baseline → 2 launcher protection/reliability → 3
  factory/release repair → 4 current-image desktop+Cursor proof → 5 probes
  → 6 casync deltas (casync-only permitted; sysupdate separately ruled) →
  7 agent safety/observation/interaction → 8 integrated release.
- L3 contract defined in SCOPE.md: autonomous implementation/tests/gates/
  evidence; explicit approval for destructive ops, production dirs,
  architecture changes, commits/pushes, publication, scope changes.

### Task 3: Stage 1 execution

- **Status:** completed (stage exit reached; residual items owned)
- **Changes Made:**
  - `SCOPE.md` (gitignored by design, `.gitignore:51`): replaced historical
    scope with approved program, L3 boundaries, current state.
  - `dev/fids/FID-2026-0915-001-master-plan.md`: added "Approved completion
    addendum" (execution sequence table, per-FID disposition table, defect
    register, decision register, stage-1 gate evidence).
  - `app/phase.go`: added `//go:build windows` (the file always was
    Windows wiring; its missing constraint broke Linux vet).
  - `app/qemu_nonwindows_test.go`: added `preboot` tracker to the
    non-Windows test harness (platform-neutral modal tests reference it;
    Windows build constraint exposed this second dependency).
  - `dev/fids/FID-2026-0916-001-launcher-hardening.md`: stage-1 correction
    evidence section.
- **Verification (fresh runs):**
  - `app/`: build PASS; `vet -unsafeptr=false` PASS; `test -count=1` ok
    9.320s; gofmt empty.
  - `guest-daemon/savant-core/`: vet/test/gofmt clean (Windows-native).
  - Linux-target (`GOOS=linux GOARCH=amd64 CGO_ENABLED=0`): vet PASS;
    compiled launcher suite ran under WSL: PASS (incl. 10× watchdog/modal
    repetition).
  - Release helpers: py_compile PASS; 10 unittests OK; lock validation ok;
    `bash -n` clean.
  - Repo: `bun run lint:md` + `git diff --check` clean after every doc edit.

### Issue 1 (discovered + fixed): `app/phase.go` missing build constraint

- **Severity:** medium (breaks Linux-target vet, which CI runs)
- **FID:** FID-2026-0916-001 (evidence recorded there)
- **Status:** resolved — constraint added + test-harness tracker; both
  platforms verified.

### Issue 2 (discovered, NOT fixed — static findings, owned)

- **Severity:** high (several)
- **Status:** open, recorded in master-plan addendum:
  - D3 "all modal sites" not met: `fatal→errorBox` (`main.go:102-107`),
    `confirmResetBackup` (`recovery_windows.go:94-112`), WHP prompts
    (`setup.go:188-217`), prefs-repair dialogs, first-run chooser converts
    headless refusal into a modal fatal. `modalFatal` has no production
    caller.
  - Watchdog goroutine race (tests don't stop/join goroutines; global
    timing restore while watchers run). NOT reproduced — no local race
    detector (host gcc missing; `-race` needs cgo). CI (ubuntu) is the
    designed race gate.
  - Watchdog retires at `main.go:731` BEFORE `proc.Start()`.
  - Early pre-log window: watchdog starts at settings; `shell.log` opens
    later; early logs in-memory only.
  - Guest-contract gate could not run in WSL (`go: command not found` —
    environment PATH, not code).

---

## Validation Results

- [x] `go build ./...`: PASS
- [x] `go vet -unsafeptr=false ./...`: PASS (Windows + Linux target)
- [x] `go test ./...`: PASS (app 9.320s fresh; savant-core clean; WSL
      Linux-test-binary PASS)
- [x] `gofmt -l .`: PASS (empty)
- [x] `markdownlint`: PASS (after every doc edit)
- [ ] `go test -race ./...`: NOT RUN locally (no gcc; CI owns this gate —
      ci.yml ubuntu runner). Static race finding recorded.
- [ ] `build-guest.sh --contract-only`: snapshot-lock OK, shell/content
      checks PASS, then `go: command not found` in WSL (environment).
      Daemon gate verified natively on Windows instead.

---

## Final State

### Code Changes

- **Files Modified (tracked):** 4 — `app/phase.go`, `app/qemu_nonwindows_test.go`,
  `dev/fids/FID-2026-0915-001-master-plan.md`, `dev/fids/FID-2026-0916-001-launcher-hardening.md`
  (+ pre-existing `guest-image/build.sh` modification, not mine)
- **Net product-code change:** 2 files, ~8 lines, both build-boundary only;
  zero behavior change on Windows.
- **SCOPE.md:** rewritten locally (gitignored; durable record lives in the
  master-plan addendum).

### Git Status

- **Branch:** main (direct-push flow per current governance)
- **Uncommitted Changes:** yes — 5 tracked files (4 mine + inherited
  build.sh), untracked scratch preserved
- **New Commits:** none (commit is an operator checkpoint per L3 contract)

---

## Open Questions / Operator Checkpoints

1. **Commit approval** for the 4 session-modified files (suggested:
   `fix(launcher): windows build constraint for phase wiring
   (FID-2026-0916-001)` + `docs(fids): approved completion program,
   stage-1 baseline (FID-2026-0915-001)`).
2. **Stage-2 design checkpoint was presented, NOT answered.** Four rulings
   requested: (a) damaged/missing install-state must not authorize override
   replacement (fail-closed); (b) guard covers runtime-only overrides +
   portable/default-dir cases on effective values; (c) anchors written by
   BOTH `dev-vm.sh init` AND `guest-image/boot-proof.sh`, refusing to stamp
   production dirs; (d) D1c receipt fields with absent→unknown logged,
   never enforced. Defaults recommended; implementation blocked on this.
3. Untracked-work dispositions (scratchpad scripts, `.agents/`, `.freebuff/`).
4. Linux Go toolchain for local race/contract gates, or accept CI as the
   race gate and WSL limitation as recorded.

---

## Lessons Learned

- A file's comment claiming a platform does not make it so — vet on the
  OTHER target is the cheap check that catches it.
- Fixing one build constraint exposed a second (hidden) dependency; treat
  build-boundary fixes as surface, not spot, repairs.
- The repo's defined gates are the acceptance bar — I briefly over-imposed
  a local `-race` requirement CI already owns; recorded and converged.
- Historical FID proof ≠ current artifact proof (Cursor dual-build passed
  while publication failed; payload replacement ≠ fresh guest disk).

---

## Next Session

### Priority Tasks

1. [ ] Operator: answer stage-2 D1/D1b/D1c checkpoint (4 rulings above)
2. [ ] Implement D1 refusal guard → G1 table tests → G2
       no-network-before-refusal regression
3. [ ] D1c receipt provenance (backward-compatible) → D1b anchors in both
       provisioning callers → G3
4. [ ] Modal-site audit completion (D3 full scope) + `modalFatal` wiring
5. [ ] Commit checkpoint for current tree (operator)

### Blockers

- Stage 2 implementation: operator rulings (checkpoint 2)
- Local race/contract gates: environment (checkpoint 4) — CI remains green
  path
- No others; stages 3–8 unblocked by design once stage 2 lands

### Notes for Next Agent

- The approved program + L3 boundaries live in the master-plan addendum
  (FID-2026-0915-001) and SCOPE.md — read those first; they supersede stale
  ordering in the plan body and stale status lines in child FIDs.
- Child FIDs are canonical owners; the addendum's per-FID table says what
  each still owes. Do NOT reimplement historically proven work (desktop
  D1–D5, keyring, PowerDevil fix) — only their missing current-artifact
  proof.
- casync-only work is approved to proceed; do not treat the sysupdate
  decision as blocking it.
- Never test override/protection work against `C:\savantos` (production).
  Disposable dev dirs only; `-headless` is not consent for resets.
- Pre-existing dirty state (`guest-image/build.sh`, untracked scratch) is
  the operator's; leave it until dispositioned.
