# FID-2026-0910-001: SavantOS Rebrand and Governance Scaffold

## Metadata

- **Filename:** FID-2026-0910-001-savantos-rebrand-and-governance-scaffold.md
- **ID:** FID-2026-0910-001
- **Severity:** high
- **Status:** fixed
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
- Flagged for operator decision (not resolved in this pass): canonical go.md
  quality overrides (max_file_lines 350, max_function_lines 50,
  max_line_length 120) vs `protocol.config.yaml` quality block (600/60/120,
  advisory, main.go exemption note).
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