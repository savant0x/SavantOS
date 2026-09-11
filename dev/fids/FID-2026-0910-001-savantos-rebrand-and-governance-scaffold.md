# FID-2026-0910-001: SavantOS Rebrand and Governance Scaffold

## Metadata

- **Filename:** FID-2026-0910-001-savantos-rebrand-and-governance-scaffold.md
- **ID:** FID-2026-0910-001
- **Severity:** high
- **Status:** analyzed
- **Created:** 2026-09-10
- **Author:** Orchestrator (Savant)

## Problem

This repository is a zip download of omacom/try-omarchy-windows (lineage:
tsouth89/try-omarchy-windows, architecture from themartiano/try-omarchy) with
no .git directory. The operator is converting it into SavantOS — a sovereign
agentic OS host — as a hard fork. The fork must (1) shed all Try Omarchy /
omacom / tsouth89 product identity, (2) adopt the Savant system governance
scaffold (ECHO Protocol, dev/ tree, templates, coding standards, Savant
Versioning), (3) repoint its signed-update trust anchors at savant0x/SavantOS
with a new Ed25519 update keypair, and (4) establish a pristine git baseline
so the lineage is auditable from commit one.

## Impact Analysis (RED — evidence)

- Identity tokens are pervasive: case-insensitive
  `TryOmarchy|tryomarchy|try-omarchy|omacom|tsouth89` matches ~90 of ~120 files
  under app/ (sources and tests), all 44 guest-build patches, scripts/guest/*,
  scripts/release/*, all 5 .github/workflows, all 6 .github/release-notes
  files, README.md, CHANGELOG.md, and docs/. Detective grep maps with
  file:line evidence captured 2026-09-10 in the session record.
- Trust anchors: app/update.go pins `currentVersion = "v0.0.14-preview"`,
  `updatePublicKeyHex` (omacom-owned Ed25519 public key), `defaultUpdateURL`
  (omacom latest), `legacyReleaseBase` (tsouth89), `transferredReleaseBase`
  (omacom), `officialReleaseBase` (omacom/omarchy-win);
  `validateUpdateManifest` accepts any of these bases. app/manifest.go pins
  `defaultReleaseURL` (omacom v0.0.14-preview release), `defaultSumsSHA256`,
  and embeds app/testdata/SHA256SUMS.v0.0.14-preview.
- The guest image is built from the exact commit in guest-build/source.lock.json
  (jorge-huxley/try-omarchy-win) plus the 44 numbered patches, whose
  host<->guest interface words are `tryomarchy.*` kernel-cmdline flags. The
  currently published omacom factory image reads those words — after renaming
  the interface to `savantos.*`, a NEW image must be built and published under
  savant0x/SavantOS before first-run download can succeed. Until then the
  rebranded launcher fails closed on download (acceptable: zero SavantOS
  installs exist).
- app/versioninfo.rc + app/rsrc_windows_amd64.syso carry "Try Omarchy" /
  "Brandon South" branding; app/versioninfo_test.go enforces the .syso stays
  in sync with currentVersion, so the version block must be rewritten (v0.0.1)
  and the .syso regenerated from a SavantOS icon.
- Instant-trial constants in app/provision_mode.go (`omarchy`/`omarchy`) are
  baked into guest patch 0005 — host hint and guest account must change
  together (to `savant`/`savant`) or the setup splash lies.
- No .git directory: `git init` + a pristine baseline commit must land before any rebrand commits.
- No dev/, templates/, coding-standards/, ECHO.md, protocol.config.yaml,
  VERSION, or NOTICE — the Savant system scaffold is absent.
- Operator-supplied SavantOS icon set exists at assets/favicon/ (favicon.ico +
  PNG sizes + webmanifest); app/icon.ico must be replaced from it.
- Guest-build lock files (guest-build/source.lock.json,
  guest-build/runtime.lock.json) and runtime-build/sources.lock.json pin
  upstream commits/archives by name — they must NOT be token-swept (they are
  external pins, not our identity).

## Proposed Solution (GREEN — operator-approved)

Identity: `appTitle = "SavantOS"`; exe `SavantOS.exe`; data dir
`%LOCALAPPDATA%\SavantOS`; kernel-cmdline words `savantos.*`; guest
service/path names `savantos-*` and `/usr/share/savantos`; export tool
`savantos-export`; window classes `SavantOSTray` / `SavantOSSettings`;
registry uninstall entry keyed to SavantOS.
Repository: savant0x/SavantOS (created private initially via gh CLI / operator token in .env.local — token never committed).
Versioning: Savant Versioning (docs/SAVANT-VERSIONING.md) — new lineage starts
at v0.0.1; CHANGELOG.md keeps the inherited Try Omarchy history below a
divider line for provenance.
Trial account: `savant`/`savant` — host hint in provision_mode.go and guest patch 0005 changed in the same pass.
Trust: generate a NEW Ed25519 update keypair locally; the private half is
written outside the repo for the operator to move to GitHub release secrets;
only the public hex replaces `updatePublicKeyHex`; `validateUpdateManifest`
accepts only `https://github.com/savant0x/SavantOS/releases/download/` going
forward (legacy tsouth89/omacom bases removed with the preview-bridge logic
that no SavantOS install needs). `defaultReleaseURL`/`defaultSumsSHA256`/
embedded fixture are repointed to the savant0x v0.0.1 release once the first
SavantOS image is built by the Release workflow.
Icon: regenerate app/icon.ico from assets/favicon/favicon.ico; versioninfo
becomes CompanyName "Savant", ProductName/FileDescription "SavantOS",
FileVersion/ProductVersion "v0.0.1", copyright "Copyright (c) 2026 Savant";
.syso regenerated (or favicon.ico used directly if it is already a
multi-size ICO) so versioninfo_test.go passes.
License/attribution: **Apache-2.0** (operator directive, 2026-09-10 session
record lastses.md: "the new license is Apache-2.0 license
https://github.com/savant0x/savant-code" — matches savant-code; supersedes
the earlier MIT-retention plan). LICENSE replaced with the canonical
Apache-2.0 text, copyright "Copyright 2026 Savant"; the inherited MIT grant
from Brandon South remains honored via NOTICE.md attribution (the upstream
code was received under MIT; Apache-2.0 is a permissive grant that permits
relicensing of the fork by its new maintainer). New NOTICE.md credits Try
Omarchy (omacom), try-omarchy for macOS (themartiano), Omarchy
(Basecamp/DHH — its mark is NOT ours and leaves all visible branding),
WINQ-EMU (cmspam), jorge-huxley/try-omarchy-win (x86_64 builder + WHPX
recipe), Chainfire (prior art), each with license and origin.
docs/FINDINGS.md and other technical history keep upstream facts under a
provenance banner.
Savant scaffold: ECHO.md (the 15 Laws + Perfection Loop, adapted to this Go
repo), protocol.config.yaml (Go commands: build `go build ./...`, test
`go test ./...`, vet `go vet ./...`, fmt `gofmt -l`), ARCHITECTURE.md
(launcher/guest/control-plane architecture), AGENTS.md (contributor + agent
guide), coding-standards/go.md, templates/FID-TEMPLATE.md +
templates/SESSION-SUMMARY.md, dev/ tree (fids/, fids/archive/,
session-summaries/, scratchpad/, nova/inbox/, nova/outbox/, LEARNINGS.md,
agenda.md), VERSION file (0.0.1), docs/SAVANT-VERSIONING.md.
Sweep order-safety: global token replacement applied longest-token-first —
`tryomarchy.` → `savantos.`, `try-omarchy` → `savantos`, `TryOmarchy` →
`SavantOS`, `tryomarchy` → `savantos`, `Try Omarchy` → `SavantOS`, `Omarchy`
→ context-sensitive — while upstream proper nouns needed for attribution and
external pins (repo URLs in NOTICE, guest-build/source.lock.json,
guest-build/runtime.lock.json, runtime-build/sources.lock.json, FINDINGS
provenance banner) are excluded from the sweep and hand-checked after.
Behavioral freeze: identity-only change set. Supervisor state machine, boot
recipe, retry ladders, clipboard protocol frames, update state machine
semantics, port layout, and disk handling are unchanged byte-for-byte in
behavior.

## Unanswered Questions (all resolved by operator, 2026-09-10)

- First-milestone priority → Rebrand-first. (Agent payload work follows as M2+.)
- Guest posture → own distro identity; stop tracking the Omarchy version line.
- Upstream relationship → hard fork; ours entirely, different direction.
- Repo strategy → rename in place + git init (this checkout becomes SavantOS).
- GitHub org/repo → savant0x/SavantOS.
- App icon → operator-supplied SavantOS favicon set.
- Trial credentials → savant/savant.
- Version scheme → Savant Versioning, v0.0.1.
- GitHub access → operator token in .env.local and/or installed gh CLI.
- License → Apache-2.0, matching savant-code (operator directive mid-session
  2026-09-10; recorded in lastses.md immediately before the crash; supersedes
  the initial MIT-retention answer).

## Verification Plan

1. `cd app && go build ./... && go vet ./... && go test ./...` — zero errors, zero warnings, zero failures.
2. `go test ./... -run TestVersionInfo` (versioninfo_test.go) — syso and currentVersion in sync at v0.0.1.
3. Zero-remnant grep: `TryOmarchy|tryomarchy|try-omarchy|omacom|tsouth89`
   returns matches ONLY inside NOTICE.md, attribution lines,
   guest-build/*.lock.json, runtime-build lock/pins, and the FINDINGS
   provenance banner.
4. `gofmt -l app` → empty.
5. `git log --oneline` shows atomic commits: baseline → scaffold →
   rebrand (host) → rebrand (guest/scripts/CI) → docs → keys.
6. `bun run lint:md` → exit 0 — tree-wide docs gate, run from the repo
   root (`markdownlint` on changed `*.md` alone is not sufficient once
   exemptions exist; the tree-wide run proves the ignore set).

## Resolution

(pending — completed sections and evidence are appended when the Perfection Loop reaches COMPLETE)

### Continuation state (2026-09-10, session resumed after crash)

- Crash point: immediately before `git init`. Disk verified on resume:
  `.gitignore` hardened ✅, no `.git` ❌, no scaffold ❌, no rebrand ❌
  (currentVersion still v0.0.14-preview), LICENSE still upstream MIT ❌.
- Resumed session folds the Apache-2.0 directive (above) into the plan before continuing.
- lastses.md is a session-crash artifact, NOT product content — excluded from
  the baseline commit and deleted at closure (gitignored via *.log? No —
  explicitly added to .gitignore at Phase A before the first `git add .`).

### Scaffold correction: canonical coding-standards/go.md (2026-09-10, operator directive)

- Operator flagged that `coding-standards/go.md` had landed as a
  SavantOS-adapted variant, not the real Savant standard. Replaced
  byte-for-byte with the canonical savant-code `coding-standards/go.md`
  (SHA256 `60e80e8ec308f91d6e5eb886e62d837cee35e539cc85288f0d2223edae5d8928`,
  2366 bytes; hash-verified after write).
- SavantOS-specific contracts remain governed where they live: `AGENTS.md`
  (doc-comment naming, `%w` wrapping, win32 interop contract, colocated
  tests), `protocol.config.yaml` (vet gate `go vet -unsafeptr=false ./...`),
  this FID (behavioral freeze). Two adapted-variant rules with no other home
  (`filepath.Join` path building; test-fixture skip-or-fail message) were
  dropped with the canonical replacement.
- Flagged for operator decision in this pass; resolved same day (see
  "Quality-limits conflict resolved" below).
- 2026-09-10 compliance pass: markdownlint (savant-code `.markdownlint.json`,
  MD013/MD040) applied — this FID reflowed to ≤120 columns and ECHO.md's FSM
  fence tagged `text`; wording unchanged (reflow only).

### Execution pass (2026-09-10, session 3)

Ground truth on resume (supersedes the crash-point note above):

- Baseline import and license commits already landed by session 2:
  2804e7a "chore: import try-omarchy-windows v0.0.14-preview upstream
  baseline" and 61cfa17 "chore(license): relicense SavantOS under Apache-2.0
  with lineage attribution" (LICENSE = Apache-2.0, NOTICE.md = full lineage
  attribution). The .gitignore was already hardened (lastses.md, .env*,
  *.key excluded).
- Remaining at resume: governance scaffold completion (templates/, VERSION,
  docs/SAVANT-VERSIONING.md, dev/ tree), Ed25519 keypair generation, the
  identity sweep, .syso regeneration, and the docs rebrand.
- Recorder routing note: the Recorder agent stalled twice on this update
  ("read without write"); per the HYBRID-mode exception the Orchestrator
  wrote this FID directly. Change set is ~40 added lines, under the
  100-line escalation threshold.

Operator decisions (2026-09-10, this session):

- Inherited .github/release-notes/*.md (v0.0.6-v0.0.14-preview): DELETE. The
  history is preserved verbatim in the baseline commit; deleting avoids
  growing the remnant-gate exemption set.
- Host scripts with omarchy filenames: RENAME (launch-savantos.ps1,
  launch-savantos-gpu.ps1, start-savantos.ps1, boot-savantos-test.ps1); all
  callers updated in the same commit.
- Remnant-gate exemption set (final): NOTICE.md, CHANGELOG.md below the
  provenance divider, guest-build/*.lock.json, runtime-build lock/pins, and
  the docs/FINDINGS.md provenance banner. The docs/images/ binaries predate
  the rebrand and are exempt as artifacts.
- CI branch trigger: `branches: [master]` → `branches: [main]` in
  .github/workflows/ci.yml (the SavantOS lineage uses main).

Commit sequence (G8): scaffold -> rebrand(host) -> rebrand(guest/scripts/CI)
-> docs -> keys. Interim trust posture per the approved plan: the launcher
pins savant0x/SavantOS v0.0.1 (first-run download fails closed until the
Release workflow publishes the first SavantOS image; zero installs exist),
and the guest-build lock files keep their upstream pins (external pins, not
our identity). Status moves analyzed -> fixed as the sweep commits land.

### Docs gate institutionalized (2026-09-10, operator directive)

- Repo-local markdownlint gate so docs verify without borrowing
  savant-code's node_modules: `.markdownlint.json` byte-copied from
  savant-code (SHA256
  `b8fb8b6408873697a3abc6622440d0db483936112c3c4b7706bbfd308f1e9bb9`),
  `.markdownlintignore` (every entry dated and reasoned), `package.json`
  (`lint:md` script, markdownlint-cli `^0.49.1`), `.bun-version` (1.3.14),
  `bun.lock` tracked, `node_modules/` gitignored.
- Wired into the gates: `protocol.config.yaml` `commands.lint_md`, and the
  Validation section of `AGENTS.md` (docs verify with lint:md — the Go
  gates never exercise root-level markdown).
- First tree-wide run: 63 violations in 6 files, all inherited upstream
  docs. Fixed 26 in the 5 living docs (23 MD013 reflow + 3 MD040 fence
  tags, content-preserving; wording unchanged). README.md exempted in
  `.markdownlintignore` — its 37 violations ride the wholesale rebrand
  rewrite; the exemption is removed only when the rewritten README lints
  clean.
- Verification: `bun run lint:md` exit 0 tree-wide; YAML parse of
  protocol.config.yaml OK (an indent slip that de-keyed `commands.lint`
  was caught by `python3 -c yaml.safe_load` and fixed). No Go files
  touched — Go gates unaffected by this change set.

### Quality-limits conflict resolved (2026-09-10, operator directive)

- Decision: **align** — `protocol.config.yaml` quality block now holds the
  canonical go.md Go-override values (max_file_lines 350,
  max_function_lines 50, max_line_length 120) directly. This is a pure-Go
  repo, so the default/override split in the go.md table is moot; the
  config carries the Go-effective values. Law 13 (one truth) — two
  disagreeing limit sets are noise, not governance.
- Evidence base (2026-09-10): 66/73 non-test Go files already ≤350 lines;
  7 exceed (main.go 1061, ui.go 564, winapi.go 462, download.go 434,
  backup.go 431, setup.go 392, settings_dialog_windows.go 375) and 33 of
  385 functions exceed 50 lines (longest main() 549) — all inherited
  upstream, all protected by the behavioral freeze. Grandfathered via a
  dated comment in the config; refactor target post-rebrand, new code
  within limits.
- Rationale for align over document-divergence: the limits are advisory
  (no enforcement tool in this repo), so alignment costs nothing
  operationally, while keeping 600/60 would silently bless future files at
  twice the canonical ceiling. Limits are targets, not descriptions of
  inherited code.
- Cleared from `dev/agenda.md` Waiting-on-operator; lesson recorded in
  `dev/LEARNINGS.md`.

### Crash recovery: session 3 died mid-sweep (2026-09-11, session 4)

- Session 3 went inert ~00:59 2026-09-11 (operator "resume"/"hey" returned
  empty replies; last instruction — operator banner for the README rewrite —
  never executed). Forensics were read-only: 4 local commits, nothing pushed
  (first session, no remote exists); 10 files modified-uncommitted; 5
  untracked (app/testdata/SHA256SUMS.v0.0.1 all-zero placeholder,
  app/versioninfo.json, assets/banner.jpg|svg operator content, deadses.md
  3 MB crash transcript).
- The tree does NOT compile: install_state.go, install_state_test.go,
  runtime_state_test.go still reference legacyReleaseBase/
  transferredReleaseBase removed from update.go by the partial sweep;
  cmd/sign-update/main_test.go still references the removed verifyBridge;
  seven files lost leading tabs (gofmt -l). Status reverted fixed →
  analyzed: the rebrand commits have not landed.
- Key forensics (no secret material printed): deadses.md and all 66
  .savant/evidence traces contain no private-key bodies (the "PRIVATE
  KEY" and "MC4CAQAw" hits are quoted grep commands and regex echoes).
  The ~/.savantos-keys trio is internally consistent (private PEM derives
  the public PEM; the b64 file is its PKCS8 DER) and yields public
  af8f488e7656c550579e81cddb3270720bc8e689f30714d2387d4a116d296626. The
  f1edc8c2… hex still in update.go is the UPSTREAM omacom key (git log -S:
  it arrived in baseline commit 2804e7a); the keys commit never ran, so
  there is no mismatch — af8f488e… is the SavantOS key the keys commit
  pins.
- Operator decisions (2026-09-11): salvage & continue — keep the partial
  sweep, finish per the FID commit sequence; delete deadses.md (crash
  transcript lineage lastses.md → ses.md → deadses.md, removed before
  any git add; no .gitignore entry needed); session-3 directives stand.
- Recovery execution (GREEN, session 4): restore the build by completing
  the sweep of install_state.go + tests and dropping the verifyBridge
  tests; gofmt -w the seven dedented files; complete the host identity
  sweep (appTitle, stableLauncherName, TRYOMARCHY_* env words, OMARCHY
  splash, tryomarchy.* cmdline words, data-dir/uninstall paths); rename
  the four host scripts and update callers; sweep scripts/, workflows,
  docs; sweep guest patches on added lines only (context lines carry
  upstream truth — patches must apply against the pinned upstream;
  recorded as a provenance exemption of the remnant gate); regenerate
  icon.ico from assets/favicon/favicon.ico and the .syso via
  goversioninfo from versioninfo.json (versioninfo.rc retired); keys
  commit swaps updatePublicKeyHex to af8f488e… and repoints manifest.go
  at savant0x v0.0.1 (all-zero placeholder SHA256SUMS keeps first-run
  fail-closed until the Release workflow publishes the real image);
  README rewritten with the operator banner and removed from
  .markdownlintignore; full gates; atomic commits per sequence;
  Verifier + Adversary audit; closure.
- Recorder stalled a third time on this update ("read without write");
  Orchestrator wrote it directly per the recorded precedent. Change set
  ~50 added lines, under the 100-line escalation threshold.