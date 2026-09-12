# FID: SignPath-pending track — repo metadata, badge, release playbook, submission finalization

**Filename:** `FID-2026-0911-001-signpath-pend-track.md`
**ID:** FID-2026-0911-001
**Severity:** medium
**Status:** fixed
**Created:** 2026-09-11 20:40
**YAGNI-Compliance:** Verified

---

## Summary

While the SignPath Foundation application is under review, the operator directed a
four-part "pending track": (1) set the GitHub repo description/topics, (2) add a
download/CI badge row to the README, (3) write `docs/RELEASE.md` as the operator
playbook for the prepare → pin → publish cycle under the new PR-only `main`
flow with the three-way `signing` input, and (4) confirm GitHub MFA and walk
through the block-by-block submission. Grounding these requests against the repo
surfaced two additional findings folded into scope: `docs/RELEASING.md` is
inherited upstream text describing a pipeline that no longer exists (and is
still linked from `docs/TESTING.md`), and a local session-transcript file
(`sesh.md`) was tracked-and-ignored in the working tree — resolved by deletion
at operator direction before this FID was filed.

## Environment

- **OS:** Windows 11 Pro, Git Bash (MSYS2) shell
- **Language/Runtime:** Go 1.27 (`app/`), Python 3.x (release tooling), Actions on `windows-2025` runners
- **Tool Versions:** gh CLI (authenticated as `savant0x`), bun (docs gate), markdownlint via `bun run lint:md`
- **Commit/State:** `main` @ `6c76d49` (PR #5, SignPath activation runbook),
  clean tree, branch protection active (rulesets `22986289` force-push ban,
  `22986292` PR + required checks)

## Detailed Description

### Problem

The pending-track work existed only as conversation requests with no FID, which
violates Law 8 (log intent before coding) for anything landing in the public
tree. Ground-truth checks exposed concrete inconsistencies:

1. **Repo metadata is half-set.** `gh repo view` reports description present
   ("Sovereign agentic OS host for Windows: signed, self-updating launcher
   running a Linux desktop guest under QEMU/WHPX") but `repositoryTopics: null`
   and `homepageUrl: ""`. SignPath reviewers and organic visitors see a bare
   repo face.
2. **README has no badges.** Verified lines 1–40: title → banner → intro →
   status line; no shields. The download link exists only as a fenced URL in
   Install step 1.
3. **`docs/RELEASING.md` describes a pipeline that no longer exists.** It
   documents `master` (branch is `main`), the `release` environment pinned to
   `master`, an Azure-only Authenticode path, `UPDATE_SIGNING_KEY` as the
   secret name (actual: `SAVANTOS_UPDATE_SIGNING_KEY`), and a
   `LEGACY_UPDATE_BRIDGE_TAG` stable-transition scheme with **zero** matches
   for `LEGACY_UPDATE_BRIDGE`/`bridge` in `release.yml`. It is inherited
   upstream text that survived the rebrand's branding-token sweep and is still
   linked from `docs/TESTING.md:4`, so an operator following it fails at step
   one.
4. **The submission's last open item is already closed.**
   `dev/signpath-submission.md` carries "(ACTION before submitting: confirm MFA
   is on …)"; the GitHub API reports `two_factor_authentication: true` for
   `savant0x`. The doc asks the operator to do what is already done.

### Expected Behavior

- Repo face matches project identity: description (already correct), a curated
  topic set, homepage pointing at the latest release.
- README carries a release/download badge row and a CI status badge.
- One authoritative release playbook documents the shipped three-phase flow
  (`prepare` / `signing-check` / `publish`), the `signing` input
  (`azure` | `signpath` | `none`), the pin-commit step, draft testing, and the
  PR-only `main` mechanics branch protection now mandates.
- The SignPath submission states MFA as verified, not as an action.
- No session-transcript files in the working tree (operator: "sesh should be
  deleted, it was a temp file and i thought i deleted it").

### Root Cause

- RELEASING.md staleness: the rebrand docs sweep (FID-2026-0910-001) rewrote
  branding tokens but did not audit *behavioral* claims of inherited docs;
  `release.yml` was later rewritten (signing input, secret rename, bridge
  scheme dropped) with no doc back-pressure.
- Tracked-and-ignored `sesh.md`: the file was staged at some earlier point,
  later added to `.gitignore` — which does not untrack an already-tracked
  file. Verified harmless: `git log -- sesh.md` empty, remote contents API
  404, zero token-pattern matches → never committed, never pushed. Deleted
  from the working tree 2026-09-11 ~20:38 at operator direction; nothing to
  scrub from history.

### Evidence

```text
$ gh repo view savant0x/SavantOS --json description,repositoryTopics,homepageUrl
{"description":"Sovereign agentic OS host for Windows: signed, self-updating
 launcher running a Linux desktop guest under QEMU/WHPX","hasIssuesEnabled":true,
 "homepageUrl":"","repositoryTopics":null}

$ grep -c "BRIDGE\|bridge" .github/workflows/release.yml
0        (docs/RELEASING.md documents the bridge scheme in detail)

$ gh api user --jq '{login, two_factor_authentication: .two_factor_authentication}'
{"login":"savant0x","two_factor_authentication":true}

$ git log --oneline -- sesh.md; gh api repos/savant0x/SavantOS/contents/sesh.md
(empty)  404 Not Found   → never committed, never pushed

$ grep -n "SAVANTOS_UPDATE_SIGNING_KEY" .github/workflows/release.yml
143:      SAVANTOS_UPDATE_SIGNING_KEY: ${{ secrets.SAVANTOS_UPDATE_SIGNING_KEY }}
226:      SAVANTOS_UPDATE_SIGNING_KEY: ${{ secrets.SAVANTOS_UPDATE_SIGNING_KEY }}

$ grep -n "phase ==\|^name:" .github/workflows/release.yml .github/workflows/ci.yml
release.yml:48:    if: inputs.phase == 'prepare'
release.yml:132:    if: inputs.phase == 'signing-check'
release.yml:214:    if: inputs.phase == 'publish'
ci.yml:1:name: CI
```

## Impact Assessment

### Affected Components

- GitHub repo metadata (topics, homepage — description already correct)
- `README.md` (badge row)
- `docs/RELEASE.md` (new) + `docs/RELEASING.md` (delete) + `docs/TESTING.md:4` (repoint)
- `dev/signpath-submission.md` (MFA line only)

### Risk Level

- [ ] Critical
- [ ] High
- [x] Medium — externally visible docs/metadata inconsistent with the shipped
      product; an operator following RELEASING.md fails at step one; SignPath
      reviewers see an unfinished face. No code, data, or security impact.
- [ ] Low

## Proposed Solution

### Approach

Four work items under one FID. Repo metadata is one `gh repo edit` command
against the live repo (not a tree change — no PR possible or needed). All
file-based items land through the PR-only `main` flow (which doubles as
continued demonstration of the protection posture for SignPath's audit trail).
This FID is presented for operator approval per Law 2 before any file is
edited.

### Steps

1. **Repo metadata** — one `gh repo edit` invocation:

   ```bash
   gh repo edit savant0x/SavantOS \
     --homepage "https://github.com/savant0x/SavantOS/releases/latest" \
     --add-topic windows --add-topic qemu --add-topic whpx \
     --add-topic linux-desktop --add-topic virtualization --add-topic go \
     --add-topic hyprland --add-topic gpu-acceleration \
     --add-topic self-updating --add-topic agentic
   ```

   Topics chosen for discoverability by the intended audiences (Windows
   virtualization seekers, Go developers, agentic-OS crowd); all are plausibly
   searched terms with existing topic pages on GitHub. Status: **proposed —
   needs operator approval** because it changes the public repo face
   immediately on execution (Law 2).
2. **README badge row** — four badges on one line under the status line
   (`README.md:18`), GitHub's own badge endpoints first, shields.io for the
   rest: release version (`/releases/svg` via shields GitHub tag badge),
   release downloads count, CI status
   (`/actions/workflows/ci.yml/badge.svg` — workflow name `CI` verified at
   `ci.yml:1`), Apache-2.0 license. All link to their targets (latest release,
   Actions tab, LICENSE). Status: **proposed**.
3. **`docs/RELEASE.md`** — new operator playbook, structured as: (a) a
   grep-able claims block at the top stating the machine-checkable facts
   (phase lines 48/132/214, secret name, `currentVersion` pin site
   `app/update.go:19`) so future editors must re-verify or break the block;
   (b) three-phase table with dispatch commands; (c) the pin commit recipe
   (`app/manifest.go` + `app/testdata/SHA256SUMS.vX.Y.Z` +
   `scripts/release/validate-pin.py TAG`); (d) PR-only `main` mechanics
   (rulesets, no self-approval, admin override as the documented solo-
   maintainer path); (e) the three `signing` choices with when to use each;
   (f) draft-testing procedure carried over from RELEASING.md where still
   valid, corrected for current names; (g) pointer to
   `dev/signpath-activation-runbook.md` for post-approval signing. Then
   **delete `docs/RELEASING.md`** and repoint `docs/TESTING.md:4` to
   RELEASE.md (grep confirmed TESTING.md is the only inbound doc link;
   archived FIDs and CHANGELOG carry no RELEASING references — audit output
   below). Status: **proposed**.
4. **Submission MFA line** — in `dev/signpath-submission.md`, Team-and-roles
   block: replace the ACTION parenthetical with "verified enabled (GitHub
   API, 2026-09-11); will also be enabled on the SignPath account." Status:
   **proposed**.

Operator approval received 2026-09-11 (~20:50): **all four steps**. Execution
record below; statuses updated as steps landed:

1. **Repo metadata — implemented** (live, no PR involved):

   ```text
   $ gh repo view savant0x/SavantOS --json repositoryTopics,homepageUrl
   {"homepageUrl":"https://github.com/savant0x/SavantOS/releases/latest",
    "topics":["agentic","go","gpu-acceleration","hyprland","linux-desktop",
     "qemu","self-updating","virtualization","whpx","windows"]}
   ```

2. **README badge row — implemented** (README.md:20–24, four badges,
   release/downloads/CI/license).
3. **`docs/RELEASE.md` — implemented** (new operator playbook with claims
   block; `docs/RELEASING.md` deleted via `git rm`; `docs/TESTING.md:4`
   repointed). One addition beyond the proposal: an **Unreleased** CHANGELOG
   section recording this FID's docs changes (Law 10).
4. **Submission MFA line — implemented** (ACTION parenthetical replaced with
   the API-verified statement).

Completed within this FID before filing (no tree change):

- `sesh.md` deleted at operator direction — **implemented** (evidence above).

Remaining: land the file-based steps via the PR-only main flow; run the
declared gates; then Verification Gates paste + archive decision.

### Verification

- Step 1: `gh repo view` output shows the topic list + homepage.
- Steps 2–4: `bun run lint:md` green; `grep -rn "RELEASING.md" docs/` returns
  no dangling references; badge URLs return HTTP 200 when the README renders
  (visually confirmed by the operator).
- Step 3: every factual claim in RELEASE.md grep-verified against
  `release.yml`/`app/` source before commit (claims block makes this
  self-enforcing).

## Verification Gates

Executed 2026-09-11 on branch `docs/release-playbook` (before status flip to
`fixed`):

```text
$ bun run lint:md
$ markdownlint .
(exit 0 — clean)

$ grep -rn "RELEASING" --include="*.md" --include="*.yml" --include="*.py" . \
    | grep -v node_modules | grep -v .freebuff | grep -v dev/fids/
(no matches — sole tree reference eliminated with the repoint)

$ grep -n "badge" README.md
20:[![Release](https://img.shields.io/github/v/release/savant0x/SavantOS)]...
21:[![Downloads](https://img.shields.io/github/downloads/savant0x/SavantOS/total)]...
22:[![CI](https://github.com/savant0x/SavantOS/actions/workflows/ci.yml/badge.svg)]...
23:[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Go gates (build/vet/test/fmt): WAIVED — zero Go files touched (docs, FID,
CHANGELOG only). Waiver void if any Go file becomes touched.
```

Declared gates (for the `verified` flip at merge time): docs gate — done,
link integrity — done, claims audit — every factual claim in RELEASE.md was
written from the grep evidence in this FID (phase lines 48/132/214, secret
name at 143/226, `currentVersion` at app/update.go:19, input list, update-feed
step names verified in the same session); final re-grep due at archive time.

## Perfection Loop

### Loop 1 — RED

- **RED:** (a) topics null, homepage empty; (b) no badges; (c) RELEASING.md
  describes a master/Azure-only/bridge-scheme pipeline that does not exist,
  still linked from TESTING.md; (d) submission says "confirm MFA" though the
  API confirms MFA on; (e) tracked-and-ignored `sesh.md` in tree. Filing the
  FID itself produced two more: (f) the first draft of this document marked
  steps 2–4 "implemented" before any edit existed — a metadata-claims-vs-truth
  violation of exactly the kind the protocol prohibits; (g) the same draft
  fabricated a "scoping error at execution time" as the deferral reason for
  step 1 — no such execution ever happened; the true reason is Law 2 (public
  face changes need approval).
- **GREEN:** (a)–(d) → Proposed Solution above; (e) → deleted, evidence
  preserved; (f) → all steps restated as **proposed**, Implementation Evidence
  left unchecked pending real landings; (g) → deferral rationale corrected to
  the honest one.
- **AUDIT:** Independent method = tool output only: `gh repo view` for (a),
  `gh api user` for (d), greps for (c) and secret/phase names, `git log` +
  remote contents API for (e). For (f)/(g) the check is this document itself —
  no "implemented" label appears for unlanded steps.
- **ADVERSARIAL:** "You filed an FID whose proposed fix includes deleting a
  doc that TESTING.md links to — breakage on merge." Answered: the same PR
  repoints the link; gate 2 (dangling-ref grep) verifies. Second challenge:
  "step 1 executed before the PR would leave metadata ahead of docs." Accepted
  ordering constraint: step 1 runs only after or with the docs PR, so the repo
  face and README agree.
- **CHANGE DELTA:** ~30% (draft→honest rewrite; scope was stable, claims were
  not).

### Missed Questions

1. **Rewrite `docs/RELEASING.md` or replace with `docs/RELEASE.md`?** The
   operator explicitly named `docs/RELEASE.md`. Keeping both near-identically
   named playbooks guarantees confusion. Answer: create RELEASE.md, delete
   RELEASING.md, repoint the single inbound link. The still-valid physical
   draft-testing procedure moves across (corrected) so no real content is
   lost.
2. **Do badges leak anything or add third-party dependence?** shields.io is
   rendered by the viewer's browser only; no repo data leaves GitHub. The CI
   badge uses GitHub's own badge endpoint to keep one dependency fewer.
3. **Is a downloads-count badge honest at v0.0.1 scale?** Yes, and it is
   positioned last in the row so it informs without leading.
4. **Does deleting RELEASING.md break anything else?** Audit grep (Loop 2)
   covers the whole tree, not just docs/.
5. **Why is repo metadata approval-gated when `gh repo edit` is one command?**
   Because Law 2 applies to public-facing changes, not just tree changes; the
   topic list is a presentation choice the operator should see before it goes
   live. Cost of asking: seconds; cost of guessing wrong: public face mis-
   represents the project.
6. **Should RELEASE.md live in `docs/` or `dev/`?** `docs/` — it is operator
   documentation for a public workflow (SignPath reviewers may read it as
   maintainership evidence), not internal agent state. Cross-link from
   `dev/signpath-activation-runbook.md` happens at SignPath activation, not
   now (the runbook is post-approval material).

### Implementation Evidence (REQUIRED for `closed`)

> To be filled when steps land. A `closed` status without this section is
> invalid.

- [ ] **Commit SHA:** (PR that lands steps 2–4)
- [ ] **File:line ranges:** README.md badge row; docs/RELEASE.md (new);
      docs/TESTING.md:4 repoint; dev/signpath-submission.md MFA line
- [ ] **Gate output:** (pasted at verification time)
- [ ] **Reproducibility:** `ls docs/RELEASE.md` exists; `ls docs/RELEASING.md`
      absent; `grep -rn RELEASING docs/` empty; `grep -n "img.shields.io\|actions/workflows" README.md` non-empty
- [ ] **Step statuses:** 1 pending approval; 2–4 pending implementation;
      sesh.md deletion implemented (evidence in Loop 1 AUDIT)

### Code Verification Evidence

- [ ] Files referenced in Affected Components exist in the intended end state
- [ ] Implementation matches the Proposed Solution
- [ ] Gates pass with pasted tool output
- [ ] Production call-graph evidence: N/A — no wiring changed
- [ ] FID status reflects the actual implementation state (currently
      `analyzed`: all fix-steps proposed, none begun)

> Every PASS/FAIL must cite file:line or exact command output at audit time.

### Loop 2 — Independent audit and self-correction

- **RED:** Ran the full-tree RELEASING reference audit the first draft only
  asserted (self-reporting prohibition): results below. Also re-verified every
  line-cited claim in Evidence after the rewrite.
- **GREEN:** Any discrepancy found gets corrected here.
- **AUDIT:**

```text
$ grep -rn "RELEASING" --include="*.md" --include="*.yml" --include="*.py" . \
    | grep -v node_modules | grep -v .freebuff | grep -v dev/fids/
docs/TESTING.md:4:backup untouched. Follow [RELEASING.md](RELEASING.md) for running a signed draft
(sole tree reference outside this FID; re-run recorded at closure)
```

- **ADVERSARIAL:** "The claims block in RELEASE.md can rot like RELEASING.md
  did." Accepted residual with mitigation: the block is grep-able, dated, and
  the FID process is the backstop; risk rated low.
- **CHANGE DELTA:** ~10% (audit-run section added; no structural change).

### Loop 3 — Final convergence

- **RED:** Residual risks: (1) step 1 awaits operator approval — deliberate;
  (2) topics `agentic`/`self-updating` are newer topic names — if GitHub
  rejects any, drop it and proceed with the accepted set (command is
  idempotent per topic).
- **GREEN:** n/a — no text corrections required in this pass.
- **AUDIT:** Convergence check: two consecutive passes with no substantive
  change (Loop 2 delta ~10% was additive audit evidence; Loop 3 zero text
  change). Meets `protocol.config.yaml` convergence thresholds.
- **ADVERSARIAL:** "Convergence claimed by the author is self-reporting."
  Conceded — the ADVERSARIAL verdict for this FID is recorded as: the loop
  output is honest as far as tool-verifiable, with the explicit caveat that
  file-based steps have not run; final verification is deferred to the
  implementation PR's gates, which are independent of this document's author.
- **CHANGE DELTA:** 0%.

## Resolution

- **Closed Date:** (pending — blocked on step-1 approval + steps 2–4 landing)
- **Fix Description:** (at closure)
- **Tests Added:** No (docs/metadata only; gates: lint:md + claims greps)
- **Verification Evidence:** (pasted at closure)
- **Archived:** (set on move to `dev/fids/archive/` + CHANGELOG entry)

## Lessons Learned

1. **Docs sweeps must audit behavior, not just branding.** The rebrand sweep
   correctly replaced tokens but left RELEASING.md asserting a pipeline later
   rewritten out from under it. Rule adopted: any doc describing a workflow
   gets a claims-vs-workflow re-audit whenever the workflow changes (encoded
   as RELEASE.md's top claims block).
2. **`.gitignore` does not untrack.** A file staged before being ignored stays
   tracked until `git rm --cached`. The audit reflex that matters:
   `git ls-files <suspect>` + remote contents check — which is what proved
   `sesh.md` never leaked before deletion.
3. **FIDs describing future work must not borrow completed-work language.**
   The first draft of this file marked unexecuted steps "implemented" — caught
   in its own Loop 1. Rule: a proposed step's status word is "proposed" until
   tool output proves otherwise; drafting convenience is not evidence.
4. **External state gets the same evidence discipline as code.** Repo topics,
   MFA status, release state are all API-queryable; every claim about them in
   this FID comes from tool output, not memory or assumption.
