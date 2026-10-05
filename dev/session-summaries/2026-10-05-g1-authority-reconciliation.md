# Session Summary: 2026-10-05 (G1 commit-authority reconciliation)

**Session ID:** 2026-10-05-g1-authority-reconciliation
**Duration:** 2026-10-05 17:00 — 17:36
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 host (Git Bash; `core.autocrlf=true`, so tracked
  files are LF in the index and CRLF in the working tree)
- **Branch:** `main`, ahead 6 of `origin/main`, unpushed
- **Last Commit:** `9c640b5` (FID-2026-0914-002 closure-gap record)

### Known Issues (intake)

- The G1 two-statement conflict recorded as `[OPEN-OUT-OF-SCOPE]` in
  `SCOPE.md`: `dev/echo-v0.1.2-single-agent.md:431` said "the agent never
  executes git (G1)" while the vendored reference copy
  `savant-docs/savant-code/ECHO.md:431` carries the 2026-09-05 operator
  amendment permitting agents to stage, commit, and push granular local
  commits. Root `ECHO.md`'s abridged G1–G9 list stated no commit authority
  at all — the structural cause of the drift.
- Ground truth established this pass: `gh api .../rulesets` returns only
  `main: no force pushes`, classic branch protection 404s, and CHANGELOG's
  Unreleased → Governance entry records the PR-required ruleset's removal —
  so `dev/agenda.md:23-27` ("PR + 1 approval … Direct pushes to main are
  gone") was stale.

### Dependencies

- None added.

---

## Planned Work

1. [x] Present the reconciliation directions as blocking questions (Law 2).
2. [x] Make the tracked records self-contained: `ECHO.md` (+ paired
   `protocol.config.yaml` protocol version) and
   `dev/echo-v0.1.2-single-agent.md`.
3. [x] Align `SCOPE.md`'s current-authorization boundary with the ruling
   and close the G1 open item.
4. [x] Correct `dev/agenda.md`'s stale PR-ruleset claim (operator-authorized
   this pass).
5. [x] CHANGELOG Governance entry; verify with `bun run lint:md`.

### Follow-on task (operator, same session): snapshot-lock head fix

- **Status:** completed
- **Changes Made:** `guest-image/check-snapshot-lock.sh` — both `| head -1`
  uses (lines 42 and 55) replaced with `awk 'NR==1{print; exit}'`; the
  file now contains no `head`. Records: SCOPE.md head item →
  `[RESOLVED 2026-10-05 — the lock-check half]` with evidence; new
  `[OPEN-OUT-OF-SCOPE]` for the two remaining host-side same-class sites;
  CHANGELOG Fixed entry; this summary.
- **Verification (all on this head-less host, `command -v head` → 1):**
  `bash -n` exit 0; direct run `snapshot-lock: OK (Arch snapshot
  20260811)` exit 0; parse proof — conf pinning 2026/08/10 fails with the
  PARSED date (the old `<none>` regression), absent pin still fails
  `<none>`; second-pin sandbox conf fails "pins a second snapshot:
  repos/2026/08/10/"; **`bash scripts/release/build-guest.sh
  --contract-only` → GATE_EXIT=0** with no shim.
- **Same-class findings recorded, not absorbed (Law 2):**
  `guest-image/build.sh:358` fails silently (delta chain skipped, no
  error) and `scripts/dev/test-dev-vm-init.sh` (lines 33, 63) is measurably
  red on this host — `bash scripts/dev/test-dev-vm-init.sh` → 27 passed,
  6 failed, exit 1, with `head: command not found` at both lines and every
  failure zero/empty-shaped; the product paths under test all passed.
  Both parked as `[OPEN-OUT-OF-SCOPE]` in SCOPE.md (the operator's
  instruction scoped this pass to the lock check).

---

## Work Completed

### Rulings received (blocking questions, Law 2)

1. **The permissive amended G1 governs this repo** — agents may stage,
   commit, and push granular local commits; the vendored copy's 2026-09-05
   amendment wins over the tracked "agent never executes git" wording.
2. **The vendored copy stays byte-untouched** (mtime still 2026-09-10);
   tracked records are made self-contained instead.
3. **`SCOPE.md`'s current-authorization boundary aligns with G1** —
   commits/pushes no longer need per-instance approval under G1's
   guardrails; release publication, signing-provider actions, and secret
   access still do.
4. **`dev/agenda.md`'s stale PR-ruleset claim corrected in this pass.**

### Changes made (all records, no product code)

- `ECHO.md`: Version 0.2.1 → **0.2.2**; new first bullet in the
  abridged G1–G9 list stating G1 commit authority explicitly (the tracked
  bootstrap previously stated none — why the single-agent doc's "G1 in
  `ECHO.md`" citation could silently disagree with the vendored full text).
- `protocol.config.yaml`: `protocol.version` → **0.2.2** (paired-bump
  pattern from `4c8c384`).
- `dev/echo-v0.1.2-single-agent.md`: Version 0.1.2-single-agent →
  **0.1.3-single-agent**; the version-control blockquote now states the
  amended G1 (with guardrails: one committer, path-scoped staging per G4,
  releases/tags/published artifacts operator-only, force-push/history
  rewrite/tag mutation prohibited) and drops the superseded "never executes
  git / the operator executes or approves" line. G2/G3/G6/G8 unchanged.
- `SCOPE.md` (4 edits): current-authorization boundary aligned; the
  2026-10-05 drift-closure pass's G1 pointer marked resolved; the
  `[OPEN-OUT-OF-SCOPE] G1 is stated two ways` item closed
  `[RESOLVED 2026-10-05]` with the ruling; new dated section
  "2026-10-05 — G1 commit-authority reconciliation (operator-directed)"
  recording both questions, all four rulings, the applied list, and one
  new open item.
- `CHANGELOG.md`: Governance entry for ECHO 0.2.2.
- `dev/agenda.md`: the "branch rulesets active / everything lands by PR"
  paragraph replaced with the ground-truth ruleset history.

### Issue found and recorded this pass (Law 2 Additional Rule)

- `[OPEN-OUT-OF-SCOPE]` `protocol.config.yaml` has no `single_agent` key,
  yet the single-agent protocol cites `single_agent.protocol` in that file
  as its machine-readable contract. Doc/contract mismatch, no runtime
  effect; owner: operator (add the key or correct the sentence).

---

### Follow-on task 2: publish-tail FID (FID-2026-1005-001, converged)

- **Status:** completed — FID opened and converged; implementation NOT
  started (design-only task; no code authorized or written).
- **Changes Made:** `dev/fids/FID-2026-1005-001-publish-tail-previous-payload-protection.md`
  (new, severity high, status `converged`); SCOPE.md's dangling-record item
  resolved with the FID pointer; one new `[OPEN-OUT-OF-SCOPE]` (missing
  `/usr/bin/find`, found during the design's host probe).
- **Design of record:** assemble the entire payload on `build-a/contract`
  first → staged self-check (`sha256sum -c`) → atomic rename swap parking
  the old payload as `out/contract.prev` → post-swap re-verify → cleanup
  and `release-base.json` last. Extracted into `guest-image/publish-tail.sh`
  (production caller: `build.sh`) with `scripts/dev/test-publish-tail.sh`
  proving every failure state; glob/`sort`/`awk` only — this host lacks
  `head` AND `find`.
- **Evidence:** every `file:line` citation re-grepped against the 493-line
  `build.sh` read 0-EOF (322, 329-347, 358, 367, 381, 456, 483); incident
  quotes from FID-2026-0914-002:703-712, the 2026-09-29 summary, RUNBOOK;
  host probes (same-device `stat` 3495259774; `head`/`find` missing);
  Ground-Truth check that `publish-tail.sh` and the suite do NOT exist and
  `build.sh` has zero call sites (correct for `converged`); `bun run
  lint:md` exit 0 after this record landed.

### Follow-on task 3: staging plan + scratchpad disposition (prepared)

- **Status:** plan prepared and presented; **nothing executed** — no
  stage, commit, push, or delete performed (the operator asked for the
  plan; deletions and pushes get their go-ahead separately).
- **Ground truth established:** the six unpushed commits need no staging
  (already committed, path-verified per commit: `501c379` 8 files `app/`,
  `65abd6a` 3 release files, `eee056f` 1 test, `d2b2b61` + `ebe875a` +
  `9c640b5` records — all FID-2026-0914-002); their only step is the push.
  Of ~65 scratchpad entries, exactly 18 are untracked-and-not-ignored
  (the rest match `*.log`, `__pycache__/`, or are empty dirs git skips).

**Slices for the uncommitted session work (explicit paths, G8 messages,
G4: stage each slice, verify `git diff --cached --name-only`, then
commit):**

1. `fix(builder): make the snapshot-lock check awk-only`
   → `guest-image/check-snapshot-lock.sh`
2. `docs(governance): adopt amended G1 commit authority, ECHO 0.2.2`
   → `ECHO.md`, `protocol.config.yaml`,
   `dev/echo-v0.1.2-single-agent.md`, `dev/agenda.md`
3. `docs(fid): open the publish-tail previous-payload protection FID (FID-2026-1005-001)`
   → `dev/fids/FID-2026-1005-001-publish-tail-previous-payload-protection.md`
4. `docs(records): record the G1 reconciliation, the lock fix, and the FID`
   → `CHANGELOG.md`,
   `dev/session-summaries/2026-10-05-g1-authority-reconciliation.md`
   (CHANGELOG carries both this session's entries — one records commit,
   precedent `d2b2b61`; noted in the message body)
5. `chore(dev): keep the evidence and gated-proof drivers in the repo`
   → `dev/scratchpad/stage2-exit-evidence.sh`,
   `dev/scratchpad/g6-stall-campaign.sh`,
   `dev/scratchpad/g4-headless.sh`,
   `dev/scratchpad/t21-gated-proofs.sh`

**Scratchpad disposition — commit (4):** `stage2-exit-evidence.sh` and
`g6-stall-campaign.sh` are cited as evidence by tracked
`FID-2026-0916-001` (lines 429, 447) and SCOPE.md:270 — cited paths must
exist in the repo to stay verifiable, and committing in place keeps the
citations true; `g4-headless.sh` is the G4 re-verification driver (the
fresh-install variant stays unexercised); `t21-gated-proofs.sh` is the
still-pending operator-gated proofs recipe (T2.1 live proofs, polkit/T1.2
owed) — active tooling for open work.

**Scratchpad disposition — delete, untracked so a plain `rm`, no commit
(14):** `commit-slices.py` (record-declared dead — anchors no longer
match), `scope-accept.py`, `scope-driver.py`, `scope-l3.py`,
`scope-reseed.py`, `scope-session.py`, `scope-t13.py`, `scope-t21.py`
(one-shot SCOPE ledger writers; outcomes fully absorbed into SCOPE.md),
`heartbeat.ps1`, `heartbeat.sh`, `launch-beats.sh`, `poll-beats.sh`
(reaper hypothesis falsified; experiment concluded),
`dump-confirm-dlg.ps1` (one-off diagnostic; its fix landed in
`scripts/dev/accept-close-trigger.ps1`), `qmp-powerdown.py` (no
references; the close ladder/`dev-vm.sh` cover real-target poweroff).
None of the 14 is cited by any tracked record (verified by
`git grep`).

**Push plan for the six existing commits:** nothing to stage; their step
is `git push origin main` (fast-forward; the only ruleset is
`main: no force pushes`). Recommended order: push the six FIRST, then
commit slices 1-5, then push again — two pushes isolate which change
turns CI red (CI runs on every push; the six have never been through CI).
Alternative: one push with everything — cheaper, but CI blame mixes.

**Open points for the operator:** (a) approve slices 1-5 as written
(with or without the recommended split), (b) approve the 14 deletions,
(c) choose push order, (d) optionally un-ignore
`dev/scratchpad/stage2-exit-evidence.log` (FID-2026-0916-001 cites it,
but `*.log` is gitignored) or accept run-logs as ephemeral history.### Follow-on task 4: implement FID-2026-1005-001 (operator-approved)

- **Status:** completed — all five steps implemented; FID status
  `converged` → `fixed`; gates green. The staging plan from task 3 stays
  untouched (no commits, no pushes, no deletions) — operator's instruction.
- **Perfection Loop (run before code, per the operator's trigger):**
  Loop 4 recorded in the FID — RED re-verified every citation (`git diff`
  empty on build.sh) and caught one design gap (the delta-entries block's
  own `find | xargs`, old line ~474, would die under pipefail here);
  GREEN implemented decision 8 there too; AUDIT = double method with
  greps proving the destructive path is GONE (`rm -rf "$out/contract"`,
  `cp -r build-a`, `cd "$out/contract"` → zero matches in build.sh);
  ADVERSARIAL challenges (first-run suite pass, recovery-command claims,
  cross-device reach, rotation-guard scope) all answered in the FID.
- **Changes Made:** `guest-image/build.sh` (490 lines: reorder, glob
  delta-prev @347, glob chunk enumeration @472, publish-tail call @489),
  `guest-image/publish-tail.sh` (163 lines, new),
  `scripts/dev/test-publish-tail.sh` (180 lines, new, CI-globbed),
  `scripts/release/build-guest.sh` (`bash -n` list extended),
  `guest-image/RUNBOOK.md` (failure modes rewritten — husk case retired;
  green-run log now shows the `[publish]` lines), FID-2026-1005-001
  (status + Loop 4 + implementation evidence), SCOPE.md (item →
  IMPLEMENTED; find-item (b) fixed / (a) rotation guard still open),
  CHANGELOG Fixed entry.
- **Validation Results (all after the last edit of each file):**
  `bash -n` on build.sh + publish-tail.sh + test-publish-tail.sh +
  build-guest.sh → **exit 0**; `bash scripts/dev/test-publish-tail.sh` →
  **RESULT: 42 passed, 0 failed, exit 0** (twice);
  `bash scripts/release/build-guest.sh --contract-only` → **exit 0**;
  `bun run lint:md` → exit 0 (re-run pending this record — see below);
  call-graph `grep publish-tail.sh` → `build.sh:489`;
  `.github/workflows/ci.yml:79` glob wires the suite into CI.
- **Staging plan amendment (task 3, records only — not executed):** one
  slice must be added: `feat(builder): publish by verified rename swap
  (FID-2026-1005-001)` → `guest-image/build.sh`,
  `guest-image/publish-tail.sh`, `scripts/dev/test-publish-tail.sh`,
  `scripts/release/build-guest.sh`, `guest-image/RUNBOOK.md`; slice 4's
  message becomes "…and the publish-tail fix" (its CHANGELOG now carries
  that entry too).

Intent log note (Law 8): this section's intent paragraph was written
before any code; the completion block above was appended after the gates
ran.

## Validation Results

- [x] `bun run lint:md`: PASS (exit 0) — covers `ECHO.md`, `SCOPE.md`,
  `dev/agenda.md`, `dev/echo-v0.1.2-single-agent.md`, and this summary
  (`CHANGELOG.md` and `savant-docs/` are in `.markdownlintignore`).
- [x] `git diff --check`: PASS (exit 0), no whitespace errors.
- [x] EOL invariants: `git ls-files --eol` shows every touched file in its
  original working-tree style (`w/crlf` for CHANGELOG/agenda/single-agent,
  `w/lf` for ECHO.md/config; index `i/lf` throughout). Python raw-byte
  counts confirm no mixed endings: SCOPE.md 780/780 CRLF,
  single-agent 466/466 CRLF.
- [x] Stale-statement sweep: `git grep "never executes git|the operator
  executes or approves"` returns only the two deliberate "superseding the
  earlier …" quotes and the historical 2026-10-05 drift-closure session
  record — no operative stale text remains.
- [x] Vendored copy untouched: `savant-docs/savant-code/ECHO.md` mtime
  2026-09-10, size 51193 — unchanged.
- [x] No Go/product files touched → Go gates not applicable this pass.
- `git status`: exactly the five intended tracked modifications plus this
  new summary; the 18 pre-existing untracked `dev/scratchpad/` files are
  untouched and still pending the standing disposition call.

---

## Final State

### Git Status

- **Branch:** `main`, ahead 6 of `origin/main`, unpushed; **nothing
  committed this pass** — the five modified files and this summary sit
  uncommitted, staging plan on request (G1 now permits agent commits;
  the operator did not direct one this session).

---

## Open Questions

- Whether the 18 untracked `dev/scratchpad/` files get committed, moved,
  or removed (standing disposition call).
- The still-open high-severity publish-tail previous-payload gap, the
  missing `/usr/bin/head`, and the push decision for the six existing
  commits — all unchanged by this pass.

---

## Lessons Learned

- A protocol citation ("G1 in `ECHO.md`") can drift from the text it
  points at when the full text lives only in a gitignored vendored copy —
  the fix is to make the tracked document state the rule itself, not just
  cite it.
- This host's shell mangles `$'\r'` and strips CR from some piped output,
  so `grep`/`sed`/`od` pipelines gave contradictory line-ending answers;
  Python raw-byte counting is the only trustworthy EOL check here (and
  `git ls-files --eol` agreed with it).
- Tool-layer file access is gitignored-aware: `read_files`/`str_replace`
  report SCOPE.md as `[BLOCKED]`/nonexistent, so audit-trail edits on
  gitignored files must go through shell-side scripting with explicit
  exact-match assertions.

---

## Next Session

### Priority Tasks

1. [x] DONE (same session, 2026-10-05): blanket-approved plan executed —
   the six pre-existing commits and six new slices pushed to origin/main
   (`1193c44` lock fix, `185b711` governance, `03a50b2` FID, `a5aa557`
   publish-tail implementation, `c518e8f` records, `de8ee41` scratchpad
   drivers), the 14 stale scratchpad scripts deleted, and the
   rotation-guard `find` at build.sh:254 glob-ified (`49bca9b`) with
   gates re-run green (suite 42/42, contract-only 0).
2. [ ] Rule on the new `[OPEN-OUT-OF-SCOPE]` `single_agent` config key.
3. [ ] Operator schedules the FID-2026-1005-001 real-build swap proof
   (the FID's last closure obligation; ~2h build, headroom present).
4. [ ] Continue the standing queue (test-dev-vm-init.sh `head` uses at
   lines 33/63 — suite 27/6 RED on this host; `stage2-exit-evidence.log`
   un-ignore decision — the FID cites it and `*.log` is ignored; N+1
   release chain).
