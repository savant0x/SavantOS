# Session Summary: 2026-10-05 (ECHO re-bootstrap, drift closure, capability bound fix, changeset committed)

**Session ID:** 2026-10-05-drift-closure-and-commit
**Duration:** 2026-10-05 15:59 — 16:15
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 host (Git Bash at `C:\Program Files\Git\bin\bash.exe`; `bash` is not on PATH)
- **Language/Runtime:** Go 1.27.0 windows/amd64
- **Branch:** `main`
- **Last Commit:** `1b93430` — T2.2 range re-verification record and double-resume lifecycle proof

### Known Issues

- A large, gate-green 2026-10-03 changeset sat uncommitted in the working tree
  (10 tracked modifications, +539/−34, plus four new `app/` files and one new
  test script) while `main` was in sync with `origin/main`.
- Record drift: SCOPE.md's current-state section described a read-only pass
  for a date that also carried implementation work; FID-2026-0914-002 read
  `converged` ("no code written yet") while its steps were implemented; the
  2026-10-03 session summary did not exist.
- Two defects in the new `app/capability_windows.go`: the documented 64 KiB
  manifest bound was not enforced (`os.ReadFile` read the whole file before a
  truncation), and `UTF16PtrFromString`'s error was discarded with `_`.

### Dependencies

- None added.

---

## Planned Work

1. [x] Re-read the ECHO protocol and ground the session in the tree, not the records.
2. [x] Close the record drift (SCOPE.md, the missing session summary, the FID status).
3. [x] Fix the two `app/capability_windows.go` findings.
4. [x] Prepare and execute the path-scoped commit plan for the changeset.

---

## Work Completed

### Task 1: ECHO re-bootstrap and grounding

- **Status:** completed
- **Changes Made:** none (read-only)
- Protocol re-read 0-EOF (`dev/echo-v0.1.2-single-agent.md`, `ECHO.md`,
  `protocol.config.yaml`). Grounding established two facts that the records
  did not state: the 2026-10-03 product work is uncommitted, and SCOPE.md
  itself is gitignored operator-local state (`.gitignore:55`), as is
  `savant-docs/`.
- **Verification:** HEAD, tree state, and all gates measured directly.

### Task 2: Record drift closed

- **Status:** completed
- **FIDs:** FID-2026-0914-002
- **Changes Made:**
  - `SCOPE.md`: a dated correction on the 2026-10-03 status-audit section
    (the pass was read-only, but the date also carries an uncommitted
    implementation workstream); the stale "session-summaries stops at
    2026-09-27" finding corrected against ground truth (both later summaries
    exist); a new dated section recording this pass's approved scope and step
    statuses.
  - `dev/session-summaries/2026-10-03-capability-probes-stage3-and-e2e.md`
    (new): the missing summary, reconstructed from the FID sections, the
    master-plan rows and the build logs, with a provenance banner.
  - `dev/fids/FID-2026-0914-002-factory-and-trust.md`: status `converged` →
    `fixed`, with closure explicitly blocked on the operator's commit (G2)
    and step 6 (Omarchy kill list) still gated on sign-off.
  - `CHANGELOG.md`: four backfilled entries (Added: host capability probes,
    delta fallback/interruption coverage; Changed: stage-3 one owner, the
    measured consecutive-release delta transfer). This was the one action
    beyond the three approved items as literally worded — the same
    landed-work-missing-from-CHANGELOG gap class the operator ruled on
    2026-09-27 — and it is flagged as such in SCOPE.md.
- **Verification:** `bun run lint:md` exit 0; every corrected claim re-checked
  against the tree.

### Task 3: Capability probe defects fixed

- **Status:** completed
- **FIDs:** FID-2026-0914-002 (steps 3b/3c)
- **Changes Made:**
  - `app/capability_windows.go`: new `readVulkanManifest` bounds the read
    BEFORE allocation using the repo's own idiom (`os.Open` + `defer
    f.Close()` + `io.ReadAll(io.LimitReader(f, max+1))`, mirroring
    `app/disk_space.go:35-46`). An oversize manifest is now an error rather
    than a partial parse, so `app/capability.go`'s bounded-read contract is
    true. `UTF16PtrFromString`'s error is handled and surfaces as
    `registry key path invalid`.
  - `app/capability_windows_test.go`: three tests pin the bound —
    `TestReadVulkanManifestOversize`, `TestReadVulkanManifestAtLimit` (the
    boundary, so it cannot drift off by one), `TestReadVulkanManifestMissing`.
- **Verification:** 8/8 capability tests PASS; the defect is inside files that
  were still untracked, so the fix rides the feature commit rather than a
  separate one (a standalone fix commit would require rewriting history).

### Task 4: The changeset committed

- **Status:** completed
- **Changes Made:** four path-scoped commits (G3/G4, G8 messages), each
  staged with explicit paths — never `git add .`:
  - `501c379` — `feat(launcher): probe host vulkan and avx2 support
    (FID-2026-0914-002)` (8 files)
  - `65abd6a` — `fix(release): builder owns runtime acquisition
    (FID-2026-0914-002)` (3 files)
  - `eee056f` — `test(launcher): cover delta reconstruct fallback
    (FID-2026-0914-002)` (1 file)
  - `d2b2b61` — `docs(records): land the stage-3 and probe evidence
    (FID-2026-0914-002)` (7 files, including the three session summaries)
- **Verification:** per-slice `git diff --cached --name-only` matched the
  intended path list exactly before each commit; `git ls-files --eol`
  confirmed `i/lf` for every staged file, so no CRLF reached the blobs.
  `main` is **ahead 4** and unpushed.

### Pre-commit checks that found nothing to fix

- `scripts/dev/test-prepare-assets.sh` is auto-wired into CI: the
  `windows-launcher` job runs `for suite in scripts/dev/test-*.sh; do bash
  "$suite"; done` (`.github/workflows/ci.yml:79-83`), so the new suite runs on
  every push without a workflow edit. Run standalone via Git Bash to confirm
  it is CI-ready: **10 passed, 0 failed**, exit 0.
- File mode: `scripts/dev/*.sh` are all tracked `100644` and invoked through
  `bash`, so the new script at 644 matches its siblings — no repeat of the
  documented exit-126 exec-bit trap.

---

## Issues Discovered

### Issue 1: the publish tail has no previous-payload protection

- **Severity:** high
- **FID:** FID-2026-0914-002 (chain incident section)
- **Status:** open — named follow-up, not implemented
- The hardened tail preserves the NEW payload; nothing guards the PREVIOUS one
  during the publish removal. The 2026-09-29 run destroyed the published
  release while its replacement never published.

### Issue 2: this host is missing `/usr/bin/head`

- **Severity:** low (fails closed)
- **FID:** none
- **Status:** open — operator's call
- Re-confirmed at the filesystem level this session: `C:\Program Files\Git\usr\bin`
  holds 363 files and no `head.exe`, so `check-snapshot-lock.sh:42`'s `| head -1`
  dies into the parse and the contract gate reports a misleading
  `snapshot <none>`. Repair the host toolchain, or make the lock check awk-only.

### Issue 3: capability facts are captured only on the runtime-resolved path

- **Severity:** low
- **FID:** FID-2026-0914-002
- **Status:** open — operator to confirm intended
- `app/main.go:665` sits inside `if gpuRoot != ""`, so a launch resolving no
  runtime writes a probe record with the `vulkan`/`avx2` fields omitted
  (`omitempty`). The diagnostics bundle still reports both facts
  (`app/diagnostics_windows.go:34`), so nothing user-visible is lost.

### Issue 4: G1 is stated two ways

- **Severity:** low (process)
- **FID:** none
- **Status:** open — operator's call
- The vendored reference copy `savant-docs/savant-code/ECHO.md:431` amends G1
  to permit agents to stage, commit, and push, while the tracked
  `dev/echo-v0.1.2-single-agent.md:431` says the agent never executes git.
  `savant-docs/` is gitignored, so the tracked rule is the stricter one. This
  session committed only on the operator's explicit instruction ("complete
  anything then commit") and did not push.

---

## Validation Results

- [x] `go build ./...`: PASS (exit 0)
- [x] `go vet -unsafeptr=false ./...`: PASS (exit 0)
- [x] `go test -count=1 ./...`: PASS (`ok github.com/savant0x/SavantOS/app 10.183s`)
- [x] `gofmt -l .`: PASS (empty)
- [x] `markdownlint` (`bun run lint:md`): PASS (exit 0)
- [x] `bash -n` on touched scripts: PASS (via Git Bash)
- [x] `scripts/dev/test-prepare-assets.sh`: PASS (10/10, standalone)
- [x] Capability test suite: PASS (8/8)

---

## Final State

### Code Changes

- **Files Modified:** 19 paths across the four commits (8 new files, 11 modified)
- **Lines Added:** 1,595
- **Lines Removed:** 37
- **Net Change:** +1,558

### Git Status

- **Branch:** `main`, **ahead 4** of `origin/main` — **not pushed**
- **New Commits:** `501c379`, `65abd6a`, `eee056f`, `d2b2b61` (plus this record commit)
- **Uncommitted Changes:** none in tracked files; 18 untracked
  `dev/scratchpad/` files remain pending the standing operator disposition
  call (`dev/scratchpad/commit-slices.py` is now dead — its CHANGELOG/FID
  anchors no longer match)

---

## Open Questions

- Push the four commits, or hold them locally?
- Close any FID now that the work is committed? FID-2026-0914-002 is NOT
  eligible: step 6 (Omarchy kill list) is still gated on operator sign-off.
- Should the publish tail gain previous-payload protection, or is
  hand-publish the accepted fallback?
- Host repair or lock-check rewrite for the missing `/usr/bin/head`?

---

## Lessons Learned

- A clean working tree is not the same as a committed one: the same date held
  both a read-only audit pass and an uncommitted implementation workstream,
  and the record described only the first. Re-baseline from the tree before
  trusting a current-state section.
- `SCOPE.md` is gitignored by design, so audit-trail edits never appear in
  `git status`; a reader checking tree state alone would conclude no scope
  record changed.
- PowerShell pipelines re-join native command output with CRLF, so counting
  CR bytes that way measures the pipeline, not the blob. `git ls-files --eol`
  is the authoritative check.
- A new `scripts/dev/test-*.sh` needs no CI edit — the job globs the directory
  and invokes each suite through `bash`, which also makes 644 the correct mode.

---

## Next Session

### Priority Tasks

1. [ ] Decide the push, and whether to reconcile the two G1 statements.
2. [ ] Finish the N+1 release chain against the survivor payloads.
3. [ ] Decide the publish tail's previous-payload protection (the open
   high-severity gap).

### Blockers

- Pushes, releases, and destructive operations remain the operator's.
- The polkit F1 and T1.2 live proofs need an image rebuild and an authorized
  disposable target.

### Notes for Next Agent

- `main` is ahead of `origin/main` by four commits, all gate-green and
  path-scoped. The 2026-10-03 work is no longer uncommitted — do not re-derive
  its state from the pre-commit record.
- The rebuild's falsifiable digest prediction was tied to a dirty tree at
  `1b93430`; committing moves the VCS stamp, so a rebuild at the new HEAD will
  legitimately differ. Compare two clean-tree assemblies against each other,
  not against `094df621…`.
