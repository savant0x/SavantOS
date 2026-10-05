# Session Summary: 2026-10-03 (capability probes 3b/3c, stage-3 runtime ownership, E2E N+1 measurement)

**Session ID:** 2026-10-03-capability-probes-stage3-and-e2e
**Duration:** 2026-10-03 (the restore rebuild ran across the day; `out/t13-dual-build-20261003.log`
→ `out/t13-dual-build-20261003b.log`)
**Status:** completed

> **Provenance note:** this summary was RECONSTRUCTED on 2026-10-05 from
> FID-2026-0914-002's 2026-10-03 sections, the master plan's 2.1/3.2/3.3 rows,
> the `out/` build logs, and working-tree ground truth, per the operator's
> standing backfill ruling (2026-09-27). It is an evidence-based record, not a
> witness account.

---

## Initial State

### Environment

- **OS:** Windows 11 host; Arch Linux guest (pinned snapshot 20260811)
- **Language/Runtime:** Go 1.27.0 windows/amd64; Docker Desktop 28.4.0
- **Branch:** `main`
- **Last Commit:** `1b93430` — T2.2 range re-verification record and double-resume lifecycle proof

### Known Issues

- The 2026-09-29 N+1 build's publish tail FATALed on the busy `out/contract`
  handle; the published N payload was rm'd to a husk. Survivor disposition was
  the open question entering this session.
- The E2E N+1 transfer measurement (target < 100 MB) was owed.
- Stage 3's double breakage: the release runner has no local runtime archive
  (`out/runtime-archive/` is not in git), and `prepare-assets.sh` refuses the
  runtime name already present in the payload's SHA256SUMS — the next tag would
  have died twice.
- This host's Git Bash is missing `/usr/bin/head`, which kills
  `check-snapshot-lock.sh` fail-closed (recorded in SCOPE.md).

### Dependencies

- None added. casync and systemd-sysupdate were already verified present at the pin.

---

## Planned Work

1. [x] Preserve the survivor payloads and measure the N→N+1 delta.
2. [x] Close stage 3 with one owner for runtime acquisition.
3. [x] Implement launcher capability probes 3b (Vulkan 1.3) and 3c (AVX2).
4. [x] Add direct fallback/interruption coverage for `deltaReconstruct`.
5. [x] Restore the local release base (rebuild).

---

## Work Completed

### Task 1: E2E N+1 measured transfer and chain incident

- **Status:** completed
- **FIDs:** FID-2026-0914-002
- **Changes Made:**
  - Record: the 2026-09-29 publish-tail FATAL destroyed the PUBLISHED N
    payload; the hardened tail preserved the new one. Survivors verified by
    digest: the N index at `out/baseline-published-N-caibx/rootfs.ext4.caibx`
    (`1b97d068…`) and the complete N+1 payload moved to
    `out/n1-payload-20260929/` (rootfs `094df621…`, caibx `11792f4f…`);
    assembly B re-hashed byte-identical as a fresh determinism witness.
  - Measurement: the published N index parsed against the N+1 index (82844
    refs / 76679 unique chunks each) shares 76676 chunk IDs — **3 new chunks,
    87,522 compressed bytes = 0.1 MiB**. The < 100 MB target is met by three
    orders of magnitude.
  - Root cause of the drift: the 3 chunks sit at image offsets 721–723 MiB and
    carry the embedded savant-core ELF; the builds differ by the VCS stamp of
    the commit that landed between them. Cross-run digest drift
    (`a2dbea53` → `ea574cb3` → `094df621`) is explained by the stamp, not by
    tooling drift.
- **Verification:** index parse + chunk diff against the two survivor payloads;
  digests re-verified.

### Task 2: Stage 3 — one owner for runtime acquisition

- **Status:** completed
- **FIDs:** FID-2026-0914-002
- **Changes Made:**
  - `guest-image/build.sh`: the runtime block reads `filename`/`sha256`/`url`
    from `scripts/release/runtime.lock.json` (the single pin), resolves
    `RUNTIME_ZIP` → `~/Downloads` → durable home with `set -u`-safe expansions
    (the old `${RUNTIME_ZIP:-$USERPROFILE/…}` died on an unset `USERPROFILE`
    under `set -u` — a latent ubuntu-runner break fixed in the same block),
    fetches from the lock's url into the durable home when no local copy
    exists (fetch → digest-verify → then land; `.part` removed on failure),
    verifies EVERY staged copy against the lock before staging, and copies
    under the lock's filename into the payload.
  - `scripts/release/prepare-assets.sh`: the runtime role now ASSERTS the
    pinned sums entry shipped (fail-closed with an actionable message) and
    stages only the source archive, whose attribution obligation no payload
    carries.
  - `scripts/dev/test-prepare-assets.sh` (new): 10 assertions, all network
    access synthetic (`file://`) — syntax, offline positive with the source
    staged and the runtime entry untouched, missing-entry refusal,
    drifted-digest refusal, duplicate guard.
  - `release.yml`: untouched, as designed (its publish list already uploads
    the payload's runtime archive verbatim).
- **Verification:** `bash -n` clean on both scripts; `build.sh
  --contract-only` → `Unknown argument`, exit 2 (fail-closed CLI intact);
  `build-guest.sh --contract-only` → `snapshot-lock: OK (Arch snapshot
  20260811)` + daemon gates, exit 0; `test-prepare-assets.sh` 10/10;
  release.yml YAML-parses clean.

### Task 3: Launcher capability probes 3b (Vulkan 1.3) and 3c (AVX2)

- **Status:** completed
- **FIDs:** FID-2026-0914-002 (steps 3b/3c)
- **Changes Made:**
  - `app/capability.go` (platform-neutral, CI-testable): `vulkanProbe`,
    `vulkanICD`, `parseVulkanICDAPIVersion`, `parseVulkanVersion`,
    `supports13`, `vulkanSupports13`, `describe` rendering exactly one stable
    fact string per state.
  - `app/capability_windows.go`: `probeVulkanSupport` walks the Khronos ICD
    manifests under `HKLM\SOFTWARE\Khronos\Vulkan\Drivers` (FILE_NOT_FOUND =
    the ordinary no-driver case, not an error; fail-open throughout),
    `probeAVX2Support` answers via `IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE)`.
  - Three design corrections against the Loop-2 sketches, recorded not silent:
    (1) no adapter enumeration — `displayDriverIdentity` is the one adapter
    truth and re-enumerating would duplicate it (Law 13); (2) 3c uses IFPI, not
    `GetLogicalProcessorInformationEx`, which carries no CPUID feature bits;
    (3) no new guest compositing flag — the guest already keys compositing off
    `savantos.render`, and a cmdline word with no guest consumer would fail
    Law 4.
  - Consumers wired (Law 4): the provenance log line at `app/main.go:668`, the
    probe-record fields at `app/main.go:1130` (additive, schema stays 1),
    and the diagnostics facts at `app/diagnostics_windows.go:34`.
- **Verification:** measured live — this host is the honest NEGATIVE Vulkan
  case (loader DLLs present, Khronos key absent) and AVX2 = True. Gates: build
  + `vet -unsafeptr=false` + `test -count=1` (`ok ... 10.795s`) + `gofmt -l`
  clean; linux-target vet + test-compile clean.

### Task 4: `deltaReconstruct` fallback and interruption coverage

- **Status:** completed
- **FIDs:** FID-2026-0914-002 (stage 6)
- **Changes Made:** five tests against the committed fixtures —
  `TestDeltaReconstructEndToEnd` (full fetch-verify-reconstruct-verify-cleanup
  chain through an httptest release),
  `TestDeltaReconstructFallsBackWithoutDeltaArtifacts` (no-advertisement
  fallback touches nothing), `TestDeltaReconstructCleansUpWhenIndexUnreachable`,
  `TestDeltaReconstructCleansUpOnMissingChunks` (no scaffolding survives for
  the zst fallback), `TestReconstructReplacesStalePartial` (a leftover `.dpart`
  is consumed, never merged).
- **Verification:** both targets green.

### Task 5: Restore rebuild (first attempt died, diagnosed, relaunched)

- **Status:** gate green; publish still owed
- **Changes Made:** the first attempt (`out/t13-dual-build-20261003.log`) died
  at the rootfs zstd write (`zstd: error 70 : Write error : Input/output
  error`) after the mode assertion. Ground truth: the output targets the Docker
  Desktop file-sharing host bind — the same layer the RUNBOOK documents for
  virtiofs write failures — while the 6 GiB read from that bind had succeeded
  and the Docker VM disk measured 947G free, so this was a transient
  file-sharing failure, not a builder defect. At relaunch the engine itself was
  wedged (`docker info` hung while the docker-desktop distro reported Running);
  Docker Desktop was restarted, answered in ~20 s (28.4.0), and the dead run's
  stale volume is pruned by build.sh's own rotation guard. The relaunch
  (`out/t13-dual-build-20261003b.log`) additionally required the recorded
  head-shim workaround.
- **Verification:** the reproducibility prediction was CORRECTED by ground
  truth — `go version -m` on the first attempt's binary shows
  `vcs.revision=1b93430…` with `vcs.modified=true`, so the dirty working tree
  stamps into buildinfo (that attempt's savant-core digest `739698ad…` already
  differed from the N+1 build's `2e567e59…`). The savant-core CODE is still
  exactly the committed `1b93430` tree, so the rebuild is a valid release base;
  the falsifiable prediction for the operator's post-commit run is that a
  clean-tree build at `1b93430` reproduces `2e567e59…` / `094df621…`.

---

## Issues Discovered

### Issue 1: the publish tail has no previous-payload protection

- **Severity:** high
- **FID:** FID-2026-0914-002 (chain incident section)
- **Status:** open — named follow-up
- The tail's hardened path preserves the NEW payload but nothing guards the
  PREVIOUS payload during the publish `rm`. The 2026-09-29 run destroyed the
  published release while its replacement never published. The rotation
  guard's `contract-.*` pruning is unrelated.

### Issue 2: this host is missing `/usr/bin/head`

- **Severity:** low (fails closed)
- **FID:** none
- **Status:** open — operator's call
- `check-snapshot-lock.sh:42` pipes through `head -1`; without it the contract
  gate reports `mkosi.conf pins snapshot <none>` and exits 1. Green contract
  evidence was produced with a temp-dir PATH shim (no repo change). Repair the
  host toolchain, or make the lock check awk-only.

### Issue 3: FID-2026-0914-002's status lagged its implementation

- **Severity:** low (record integrity)
- **FID:** FID-2026-0914-002
- **Status:** resolved 2026-10-05
- The FID read `converged` ("no code written yet") while steps 3b/3c and stage
  3 were implemented in the working tree. Corrected to `fixed` on 2026-10-05,
  with closure explicitly blocked on the operator's commit (G2).

---

## Perfection Loop Summary

| Loop | Target | RED | GREEN | Fixes | AUDIT | Delta |
|------|--------|-----|-------|-------|-------|-------|
| 1 | E2E N+1 transfer | transfer unmeasured; survivors unverified | parse both indices, diff chunk IDs | 3 chunks / 87,522 bytes | digests re-verified | — |
| 2 | Stage 3 double breakage | runner has no archive; sums collision | builder owns acquisition, prepare asserts | lock-driven fetch + assert | `test-prepare-assets.sh` 10/10 | — |
| 3 | 3b/3c probes | sketch corrections (DXGI, GLPIE, flag) | ICD walk + IFPI | three corrections recorded | live probes + gates | — |

---

## Validation Results

- [x] `go build ./...`: PASS
- [x] `go vet -unsafeptr=false ./...`: PASS
- [x] `go test ./...`: PASS (`ok github.com/savant0x/SavantOS/app 10.795s`)
- [x] `gofmt -l .`: PASS (empty)
- [x] `markdownlint` on changed docs: PASS
- [x] Linux-target vet + test-compile: PASS
- [x] `bash -n` on touched scripts: PASS
- [x] `test-prepare-assets.sh`: PASS (10/10)
- [x] `build-guest.sh --contract-only`: PASS (with the temp-dir head shim)

---

## Final State

### Code Changes

- **Files Modified:** 10 tracked
- **Lines Added:** 539
- **Lines Removed:** 34
- **Net Change:** +505 (plus four new `app/` files and one new test script)

### Git Status

- **Branch:** `main`
- **Uncommitted Changes:** yes — the entire changeset above
- **New Commits:** none (commits are the operator's per G1)

---

## Open Questions

- Should the publish tail gain previous-payload protection (the named gap), or
  is hand-publish the accepted fallback?
- Is the missing `/usr/bin/head` a host repair or a lock-check rewrite?
- The sysupdate guest-pull-vs-host-contract decision remains open (D2).

---

## Lessons Learned

- A fully green dual verdict does not make a release safe: the publish tail's
  `rm` and its handle failure are a data-loss window. Preserve before replace.
- A dirty working tree stamps `vcs.modified=true` into embedded Go buildinfo,
  so "rebuild at the same commit" cannot reproduce a digest while the tree is
  dirty. Digest predictions must state the tree state with the commit.
- Registry-sourced paths need a bounded read at the read, not a truncation
  after it: `os.ReadFile` then slicing a manifest enforces nothing.

---

## Next Session

### Priority Tasks

1. [ ] Commit the 2026-10-03 changeset (operator executes; staging plan prepared).
2. [ ] Finish the N+1 release chain against the survivor payload.
3. [ ] Decide the publish tail's previous-payload protection.

### Blockers

- Commits and pushes require operator approval (G1/G2 as ruled repo-locally).
- The polkit F1 and T1.2 live proofs need an image rebuild and an authorized target.

### Notes for Next Agent

- The entire 2026-10-03 changeset is uncommitted at HEAD `1b93430`; the gates
  are green with it in the tree. Do not re-derive its state from the FID
  metadata alone.
