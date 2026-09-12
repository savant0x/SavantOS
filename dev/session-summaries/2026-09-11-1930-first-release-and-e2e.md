# Session Summary: 2026-09-11 19:30

**Session ID:** 2026-09-11-1930-first-release-and-e2e
**Duration:** 2026-09-11 ~19:30–20:15 (continuation of the 18:30 lineage)
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 (Git Bash + PowerShell toolchain)
- **Language/Runtime:** Go (app/, github.com/savant0x/SavantOS/app)
- **Branch:** main @ e558911 (post-publish-recording docs commit)
- **Prior state:** v0.0.1 draft built (release run 34656706573), manifest
  pin landed (dc55d47), publish blocked only on Authenticode decision.

### Known Issues

- Azure Trusted Signing costs $9.99/mo — operator wants free routes.
- Two CRLF-class test failures already fixed locally (1c53ca2).

---

## Planned Work

1. [x] Publish v0.0.1 (signing path resolved: unsigned via `signing=none`).
2. [x] Verify the public release end-to-end as a user.
3. [x] Pre-wire the free signing future (SignPath) without activating it.
4. [x] README Install section; lessons + tracking updates.

---

## Work Completed

### First release shipped: v0.0.1 (public, Latest)

- **Status:** completed
- **Changes:** exec-bit fixes (4244ffc `.sh`, e987f79 `.py`), guest lock
  refresh merged from PR #1 (69822b1), `signing` input on the publish
  phase (afccf23), unsigned publish run 34657848398, checksum asset
  re-uploaded with LF after the CRLF find, LF rule added to both
  workflow checksum steps (f5a01fd).
- **Verification:** anonymous download digest-matched; `isDraft false`,
  `isPrerelease false`, published 2026-09-11T23:27:12Z;
  `releases/latest` redirects to v0.0.1; verify-public.ps1 passed inside
  the workflow (launcher digest, both Ed25519 feeds, manifest pin).

### End-to-end first-run proof (as a user)

- **Status:** completed
- **Evidence:** fresh download dir `~/Downloads/savantos-e2e`; README
  PowerShell checksum command verbatim → `checksum OK`; `sha256sum -c`
  green after the LF fix; first run created the data dir, downloaded and
  pinned-digest-verified the 506 MB runtime + 1.7 GB image, materialized
  the 6 GB sparse disk, and booted **GPU-accelerated on attempt 1**
  (virtio-vga-gl + Venus, `-cpu host`, WHPX); guest userspace ready
  ~11 s after QEMU start; shell.log shows the swept contract live
  (`savantos.tz/locale/kb`), tray, agent 4451, clipboard 4448/4449,
  winkey QMP 4446.

### SignPath Foundation track (free Authenticode future)

- **Status:** completed (pre-wired, not active)
- **Changes:** `signing=signpath` option (913bf34) — unsigned artifact →
  signpath/github-action-submit-signing-request@v2 (pin c92b9587) →
  promote signed exe → unchanged Authenticode check + Ed25519 feeds;
  application package at `dev/signpath-application.md`; policy stub
  `.signpath/policies/savantos/release-signing.yml` with
  `require_github_hosted` + `disallow_reruns` and branch-ruleset rules
  staged commented until branch protection exists; CODEOWNERS scopes
  `.signpath/` to @savant0x (2df3505).
- **Also:** app-scoped build-output ignores (8a9d3be) after a local
  `app/SavantOS.exe` was found untracked-and-unignored.

### Docs

- **Status:** completed
- **Changes:** README Install section (60f9f35): latest-release URL,
  checksum verification (PowerShell + Git Bash forms), SmartScreen note,
  first-run flow, self-update note; status line corrected to "shipped".

---

## Validation Results

- [x] Anonymous public download: PASS (digest match)
- [x] `sha256sum -c` on published checksum: PASS (after LF re-upload)
- [x] First-run download → verify → provision → boot: PASS (GPU path)
- [x] YAML parse of release.yml after every edit: PASS
- [x] lint:md after README/docs edits: PASS
- [x] GitHub-hosted-runner constraint for SignPath OSS: satisfied

---

## Final State

### Git Status

- **Branch:** main, clean; pushed through 8a9d3be
- **Commits this segment:** 4244ffc, e987f79, 69822b1 (PR #1), dc55d47,
  afccf23, 60f9f35, f5a01fd, 913bf34, 2df3505, 8a9d3be

### Releases

- **v0.0.1:** published, Latest, 11 guest/runtime assets + launcher +
  checksum + two Ed25519-signed update feeds. Launcher unsigned
  (SmartScreen one-time bypass); SignPath track pre-wired for free
  Authenticode later.

---

## Lessons Learned

- Windows-checkout repos must audit exec bits and CRLF boundaries before
  first Linux-runner use; both failed loudly only in CI.
- PowerShell `Set-Content` is CRLF-poisoned for cross-platform artifacts;
  use `[IO.File]::WriteAllText` with an explicit `` `n ``.
- Actions cannot create PRs by default; enable the workflow-permission
  toggle for any cron that opens refresh PRs.
- Details recorded in `dev/LEARNINGS.md` (2026-09-11 entries).

---

## Next Session

### Priority Tasks

1. [ ] Operator submits the SignPath application.
2. [ ] Optional: branch protection + policy branch_rulesets uncomment.
3. [ ] Next release cycle exercises the playbook end-to-end.

### Blockers

- SignPath review latency (external).

### Notes for Next Agent

- v0.0.1 is LIVE and Latest — any pin/fixture change now ripples to real
  first-run installs; treat manifest.go/testdata as release-critical.
- `signing=none` publishes unsigned; do not "helpfully" switch the
  default to azure — the Azure account does not exist.
- The e2e test install at `~/Downloads/savantos-e2e` is disposable
  (~6.3 GB); delete or `-uninstall` when done.
