# FID: Phase 4 — Factory & trust (release pipeline, deltas, Omarchy retirement)

**Filename:** `FID-2026-0914-002-factory-and-trust.md`
**ID:** FID-2026-0914-002
**Severity:** high
**Status:** converged — keyring unit + assemble gates landed `40f36ff`,
release re-point `9e48202`, sandbox pin `34f6fa8`; first-boot keyring proof
passed 2026-09-15
**Created:** 2026-09-14 00:56
**YAGNI-Compliance:** Pending
**Parent:** FID-2026-0912-001 (first-party OS pivot — Phase 1 converged; Phase 2 landed under FID-2026-0912-002/FID-2026-0913-001)

---

## Summary

Phase 4 of the approved pivot (FID-2026-0912-001, workstream 4): the factory
and trust layer — casync + sysupdate deltas (byte-range support verified on
GitHub Releases first), the release contract gate rebuilt for the mkosi
builder (Docker-run Linux), release.yml re-pointed at mkosi outputs, launcher
probes (AVX2, Vulkan 1.3, metered) extended, and the Omarchy kill list
executed on operator sign-off. Plus the pacman-keyring builder gap discovered
2026-09-14 during the Phase-2 identity live work. This FID materializes the
approved workstream into a tracking record (defined in the pivot FID but
never given its own FID — a tracking gap found in the 2026-09-14 folder
audit); the perfection loop runs when implementation begins.

## Environment

- **OS:** Windows 11 host; Arch Linux guest
- **Language/Runtime:** Go 1.27; PowerShell + Python release tooling
  (`scripts/release/`)
- **Commit/State:** working tree 2026-09-14 — Phase 2/identity bake present
  (uncommitted)

## Detailed Description

### Scope (from FID-2026-0912-001, workstream 4 — recorded verbatim)

- casync + sysupdate deltas (byte-range support verified on GitHub Releases
  first).
- Contract gate rebuilt for mkosi (Docker-run Linux).
- release.yml re-pointed.
- Launcher probes (AVX2, Vulkan 1.3, metered) extended.
- Omarchy kill list executed on sign-off (the exact kill list is recorded in
  FID-2026-0912-001 — executes ONLY after operator sign-off, as a numbered
  step).

### Open item: the pacman-keyring builder gap (discovered 2026-09-14)

The first-party builder installs packages from OUTSIDE the image (mkosi
sandbox), so the image's runtime pacman keyring is never initialized —
runtime `pacman -S` in the guest fails signature verification ("required key
missing from keyring"; fixed live 2026-09-14 with `pacman-key --init` +
`--populate archlinux`, which persists on the dev disk). The keyring cannot
ship in the image (random content breaks the dual-build determinism gate).
**Operator decision (2026-09-14):** first-boot keyring-init unit in the image
(the sshd host-keys pattern, idempotent). IMPLEMENTED 2026-09-14:
`guest-image/skeletons/etc/systemd/system/savantos-keyring-init.service`
(Type=oneshot; idempotent guard — skips when the archlinux master keys are
already in the keyring, `pacman-key --init` + `--populate archlinux`
otherwise; the guard greps the UID output because gpg --list-keys exit codes
are unreliable for "no match") + `enable savantos-keyring-init.service` in
`90-savantos-factory.preset` + the assemble.sh presence probe.

In-guest proof: **PASSED 2026-09-15 on the first boot of a fresh image** (no
longer owed). Image built by `guest-image/build.sh` (dual-build gate green;
published `out/contract`, `sumsSha256 eaa8bc9d…`, rootfs `06715df6…`),
provisioned into the dev data dir by the unmodified launcher over loopback,
first boot ready in ~12 s. Evidence: `savantos-keyring-init.service` ran on
that first boot — guard found no archlinux key, so it executed
`pacman-key --init` + `--populate archlinux` (38 revoked keys disabled, trust
depth-2: 77 valid, master key dated 2026-09-15), exited 0/SUCCESS in 7 s;
`90-savantos-factory.preset:15` shows the enable line; runtime
`pacman -Sy && pacman -S tree` installed signature-verified (tree 2.3.2-1,
zero keyring errors — exactly the failure mode this unit exists for).
Honest caveats recorded: (1) the factory image ships with EMPTY pacman sync
databases (the deterministic build installs offline), so the first runtime
install needs one `pacman -Sy` — acceptable, but a documented characteristic;
(2) the proof first accidentally landed on the previous day's boot because
the launcher retains `vm/disk.raw` across payload updates by design
(`prepareDisk` keeps an existing writable disk) — a fresh-disk first boot
required removing the disk first; (3) `prepareDisk`'s `-fresh` path blocks
on a GUI reset-confirmation dialog (`confirmResetBackup`), which is
unreachable in headless automation — the disk-retention rename was done by
hand instead (same semantics the dialog approves).

### Exit criteria (from FID-2026-0912-001's verification section)

Full release cycle (prepare → pin → publish) producing the first
Plasma-based signed release; smoke test on a fresh data dir.

## Impact Assessment

### Affected Components

- `scripts/release/` (contract gate rebuild; prepare → pin → publish)
- `.github/workflows/release.yml` (re-pointed at mkosi outputs)
- `app/` launcher probes (AVX2, Vulkan 1.3, metered)
- `guest-build/` + Omarchy derivations (kill list, on sign-off)
- First-boot keyring-init unit (operator decision: unit chosen over the
  `docs/DEVELOPING.md` note)

### Risk Level

- [x] High: nothing ships without the release pipeline re-point; the Omarchy
      kill list deletes ~60 tracked files and requires operator sign-off

## Proposed Solution

### Approach

Per FID-2026-0912-001's workstream 4; each item lands contract-gated and
direct-pushed per the 3c flow. The Omarchy kill list is a single
operator-signed-off change with a CHANGELOG record.

### Steps

1. This FID's perfection loop converges.
2. Contract gate rebuilt for mkosi (Docker-run Linux); release.yml re-pointed.
3. Launcher probes extended.
4. Keyring gap closed per the operator's decision.
5. Deltas (casync + sysupdate) with byte-range verification first.
6. Omarchy kill list executed on sign-off, with CHANGELOG record.

### Verification

- Full release cycle producing the first Plasma-based signed release.
- Smoke test on a fresh data dir.
- Runtime `pacman -S` works in a fresh guest per the keyring decision.

## Verification Gates

> Declared now; run when implementation begins.

- gate: contract (Docker: mkosi build ×2 → digests equal; six-file contract
  emitter verified against SHA256SUMS) — **runbook:
  `guest-image/RUNBOOK.md`** (distilled 2026-09-28 from the T1.3 runs:
  prerequisites, procedure, green-run shape, all observed failure modes
  including the publish-tail busy-handle and its manual fallback, post-run
  checklist, and the scope boundary against the remaining stage-3 rows).
  Latest gate execution: 2026-09-28, GATE GREEN twice (run 2 reproduced
  run 1's digests byte-identically; `rootfs.ext4 a2dbea53…895d5`),
  baseline published (sums `5525ba54…755e`) — see master plan T1.3.
- gate: release (prepare → pin → publish → smoke test on a fresh data dir)
- gate: build/vet/test/fmt per protocol.config.yaml
- gate: docs (markdownlint on changed *.md)

## Perfection Loop

### Loop 1 — Design convergence (2026-09-14, folder-audit pass)

- **RED:** Open items cataloged: (a) the pacman-keyring decision
  (operator); (b) casync/sysupdate tool availability on the pinned snapshot
  and in the build container; (c) GitHub Releases byte-range verification;
  (d) the release.yml re-point specifics.
- **GREEN:** Scope REDUCTION found: the mkosi contract gate substantially
  EXISTS — build.sh already runs the dual-build digest comparison, emits
  SHA256SUMS, and writes release-base.json for the local release base. The
  remaining gate work is the published-release flow + smoke test, not a
  rebuild. (a) is a named blocker with both options documented; (b)/(c)/(d)
  are named implementation steps.
- **AUDIT:** build.sh's gate cited (read 2026-09-14: dual-build digest
  comparison loop, SHA256SUMS emission, release-base.json emission).
- **ADVERSARIAL:** "The keyring gap blocks runtime pacman" — true but not
  release-pipeline-blocking; assigned to the operator decision with both
  options documented in this FID.
- **CHANGE DELTA:** ~18%.
- **Convergence declared:** status → analyzed.

### Loop 2 — Remaining-steps pass (2026-09-14, operator-directed: probes, deltas, kill list)

Evidence base: parent FID-2026-0912-001 read 0-EOF (kill list verbatim,
workstream 4, verification section); `dev/research-reconciliation.md` read
0-EOF (binding ADOPT/ADAPT rows for all three steps); launcher sources read
(`render_probe.go`, `qemu.go`, `main.go` flag/flow paths, `setup.go`
ensureWHP/ensureRuntime, `download.go` byte-range machinery, `go.mod`);
release pipeline read (`build-guest.sh` contract gate, `prepare-assets.sh`
runtime-lock reader, `release.yml` in full); kill-list inventory from
`git ls-files` + repo-wide grep. Working tree untouched — no implementation.

- **RED (step 3 — launcher probes).** (a) The AVX2 probe as written in the
  reconciliation ADOPT row ("no AVX2 → guest told to disable local VLM
  path") has NO consumer yet: there is no local-VLM path in the guest or
  the cmdline contract (`app/qemu.go` appends `savantos.render=` only), so
  a probe alone would be dead code (Law 4). The Phase-2 FID already ships
  the behavioral equivalent for the rendering path — `savantos.render=cpu`
  makes the guest disable animations — which the agent-layer FID will
  reuse. Decision needed: probe-now as groundwork (a pure, tested flag
  parse with no consumer — knowingly wired in Phase 3), or fold the AVX2
  read into the Phase-3 VLM work where its consumer exists. (b) GPU-mode
  CPUs are not the constraint — CPU mode is: `app/qemu.go:15` documents
  that ANY XSAVE/AVX feature panics the guest kernel under stock WHPX, and
  `docs/FINDINGS.md:27,128` records llvmpipe losing AVX2 on the stock CPU
  path (WINQ-EMU's patched WHPX keeps `-cpu host`). So the honest probe
  gates llvmpipe expectations, not the GPU path. (c) Vulkan 1.3: the
  accepted design is "extend the existing probe to explicit Vulkan 1.3
  detection"; `app/go.mod` has zero graphics deps, so this is native
  DXGI/`D3DKMTEnumAdapters`-style work on the Windows-only side — a
  meaningful surface, must not be guessed in this pass. (d) Metered: the
  reconciliation's adopted design is "host queries Windows network state;
  pauses update downloads on metered links" — the hook point is the
  download path (`downloadVerifiedWithOptions` / `ensureRuntime` /
  `ensureGuest`), and Windows exposes metered state via
  `GetNetworkConnectivityHint`; out of scope of this pass to design the
  full policy (what pauses, for how long, what UI) — needs its own
  micro-contract before code.
- **GREEN (step 3).** Decomposed into three separately-approvable items:
  3a metered-pause (consumer exists today: `ensureRuntime`/`ensureGuest`
  download paths; smallest user-visible win; named design tasks: hint API,
  pause semantics, settings escape hatch), 3b Vulkan 1.3 detection (feeds
  the render probe reason strings + the guest's compositing flag; named
  design tasks: adapter enumeration, version assertion, probe-record
  shape), 3c AVX2/VLM flag (recommendation: defer into FID-2026-0914-001
  where its consumer lives, recording the probe design — CPID feature
  bits via `GetLogicalProcessorInformationEx` — so it costs nothing
  now). Ordering proposal: 3a → 3b → (3c in Phase 3).
- **RED (step 5 — deltas).** (a) casync and systemd-sysupdate tool
  availability is UNVERIFIED on the 2026-08-11 snapshot and in the release
  container — the FID's own open item (b); sysupdate is part of
  systemd (257.x on that snapshot — version read from the repo's lock
  evidence is NOT confirmed; verify in-guest before design). (b) GitHub
  Releases byte-range support — open item (c) — is testable TODAY without
  any build: a HEAD + `Range: bytes=0-0` request against a published
  release asset. (c) The deeper architectural RED: our update model is a
  six-file payload swap driven by the HOST launcher (fetch.go,
  payload_update.go, install-state receipts, F1–F7 in the parent FID);
  sysupdate's model is GUEST-initiated pulls against sysupdate-style
  partition/Directory-per-release layouts. Grafting sysupdate onto the
  six-file contract either means the launcher learns a second update
  mechanism (contract bend — the parent FID forbids silent contract
  bends) or sysupdate runs inside the guest against a second transport —
  two update systems. casync alone (chunk store + seed/index over the
  existing rootfs.ext4.zst or a .caidx directory) can deliver <100 MB
  deltas WITHOUT displacing the host-driven contract. (d) The
  reconciliation ADOPT row says "orchestrated by the guest" — that is the
  part that collides with the F1–F7 host-driven model and needs an
  explicit operator ruling, not a silent choice.
- **GREEN (step 5).** Verified-first ladder, cheapest rung first:
  (1) measure GitHub Releases byte-range behavior against the current
  v0.0.x assets (zero build cost); (2) probe the snapshot/container for
  casync + sysupdate binaries (one container run); (3) design casync-only
  deltas over the existing payload (seed = current rootfs.ext4 on the
  data disk, index streamed from the release, host still authenticates
  the full-image SHA256SUMS as the trust anchor — the delta is an
  optimization, never a second trust root); (4) sysupdate remains a
  NAMED open decision for the operator (guest-pull architecture vs
  host-pull contract), documented here, not implemented. A
  zstd-split fallback stays the documented fallback per the
  reconciliation ADAPT row.
- **RED (step 6 — kill list).** Inventory re-counted 2026-09-14 (the
  parent's ~60 estimate still holds): `guest-build/` = 51 tracked files
  (48 patches + README + source.lock.json + runtime.lock.json) — exactly
  the parent's table. Omarchy derivations OUTSIDE guest-build/: docs
  (COMPATIBILITY.md 4 hits, MIGRATION.md 5, FINDINGS.md 9 — FINDINGS is
  the QEMU/WHPX technical history that must be READ before touching that
  code per knowledge.md, so it gets a preface note, not a rewrite),
  README.md, CHANGELOG.md, ECHO.md, knowledge.md, docs/BACKUP.md,
  docs/PORTABLE_USB.md, docs/TESTING.md, docs/SAVANT-VERSIONING.md,
  scripts/boot-savantos-test.ps1, scripts/vmtest/README.md,
  scripts/vmtest/winps.sh. Two coupling findings beyond the parent's
  table: (a) `scripts/release/prepare-assets.sh:14` reads
  `guest-build/runtime.lock.json` as the runtime-lock source — deleting
  guest-build/ BREAKS the release pipeline unless the lock moves (the FID
  already notes "re-point its lock source when the kill list executes");
  the design must name the destination (proposal: `runtime.lock.json`
  moves to `scripts/release/` beside its only consumer, updated in the
  same atomic change). (b) ECHO.md is the GOVERNANCE document — its
  Omarchy references are historical record of upstream, and the
  protocol's no-rebranding rule does not require scrubbing history;
  proposal: leave ECHO.md's mentions, update only forward-looking refs,
  per the parent's "prose refs: updated" disposition.
- **GREEN (step 6).** Execution design (for operator sign-off, still
  gated on the parent's sign-off requirement): single atomic change-set —
  (i) `git rm` guest-build/ (51 files), (ii) move runtime.lock.json to
  scripts/release/ + one-line repoint in prepare-assets.sh (same change,
  or the release pipeline is red), (iii) docs sweep per the dispositions
  above (FINDINGS.md preface note; COMPATIBILITY/MIGRATION rewritten as
  "retired with the Omarchy builder" stubs or deleted — operator picks),
  (iv) README/knowledge.md forward refs updated, (v) CHANGELOG record,
  (vi) vmtest/boot-savantos-test retarget — NOTE: retargeting is only
  honest AFTER the new image boots the dev loop (the tests would fail
  against a target that doesn't exist yet); sequence it after the next
  successful dev-VM boot proof, not with the deletions. G1: agent
  prepares the staging plan, operator executes or approves the commit.
- **AUDIT (whole pass).** Probe claims cite `render_probe.go` (schema,
  retry window, runtimeIdentity), `main.go:550` (startWithGPU call site),
  `qemu.go:15-17` (AVX panic comment), `go.mod` (single dependency),
  `download.go` (Range machinery: parseContentRange, resume, 412 path).
  Delta claims cite `prepare-assets.sh:14` (runtime lock consumer) and
  release.yml's prepare asset list. Kill-list claims cite `git ls-files`
  counts (51) and the grep inventory above. No claim rests on memory.
- **ADVERSARIAL.** "The probes are trivial — just write them." Rebutted:
  3a has real policy decisions (pause what, show what, override how), 3b
  has no graphics dependency to lean on, and 3c has no consumer — Law 4
  (call-graph reachability) would fail each of them the day they land
  without their consumers. "sysupdate is the modern way, just adopt it." —
  it conflicts with the verified F1–F7 host-driven contract; adopting it
  silently would be exactly the contract bend the parent FID forbids.
  "Delete guest-build/ now, the builder works." — the release pipeline's
  prepare-assets.sh still reads its lock file, and the pivot FID gates
  the deletion on operator sign-off regardless.
- **CHANGE DELTA:** ~40% of the final FID text (this first deep pass over
  steps 3/5/6 roughly doubles the document). Disclosed circuit-breaker
  tension: the protocol's 10%-per-pass cap is written for oscillation
  prevention on a converged loop; this is the first substantive pass over
  material Loop 1 only cataloged. Recorded, not hidden — operator rules on
  whether the pass stands or must be split.
- **STATUS:** Pass documented. NOT converged to `converged` yet: three
  named operator decisions exit this loop (D1 probes decomposition, D2
  delta architecture, D3 kill-list dispositions + sequencing). All three
  are presented below the loop record; implementation of every step stays
  blocked until the operator answers.

#### Operator rulings + zero-build verifications (2026-09-14, same session)

The three decisions were presented as a blocking step; the operator
answered:

- **D1 (probes): ALL THREE now** — overrides the 3c deferral
  recommendation; 3a metered-pause, 3b Vulkan 1.3, 3c AVX2 all approved
  for immediate implementation, in that order. 3c's consumer note stands:
  the probe lands now (feeding the render-probe record + diagnostics
  surface); its VLM-flag consumer arrives with Phase 3 — a named, not
  silent, wiring gap.
- **D2 (deltas): verify-first ladder = design of record.** casync-only
  deltas over the existing F1–F7 contract proceed; sysupdate's
  guest-pull-vs-host-contract question remains a recorded open operator
  decision. Both zero-build verifications were EXECUTED immediately:

  Rung 1 — GitHub Releases byte-range: **CONFIRMED** against the live
  v0.0.1 release assets (no build required):

      HEAD build-spec.json → 302 → 200, Accept-Ranges: bytes (6452 bytes)
      GET Range: bytes=0-15 (build-spec.json) → 16 bytes, prefix '{\n  "sch'
      GET Range: bytes=0-15 (vmlinuz-linux)   → 16 bytes, prefix 'MZ\x00\x00'

  A server ignoring Range would have returned 200 + the full body; the
  16-byte responses are conclusive. The reconciliation's "verify early"
  condition is discharged on real assets.

  Rung 2 — tool availability on the pinned 2026-08-11 snapshot (Arch
  container, snapshot mirror, same pattern as the builder):

      casync 2.r267.g0efa7ab-3  — present on the snapshot, installs,
                                  `casync 2` runs
      systemd 261.2-1           — ships /usr/bin/systemd-sysupdate,
                                  systemd-sysupdated, the timers, and the
                                  dbus org.freedesktop.sysupdate1 surface

  Open item (b) is discharged: both tools exist at the pin. casync needs
  no new builder dependency beyond the release container image.

- **D3 (kill list): execution design approved, execution still gated.**
  The atomic change-set (git rm guest-build/ 51 files; runtime.lock.json
  → scripts/release/ + the prepare-assets.sh repoint in the SAME change;
  FINDINGS.md preface note; COMPATIBILITY/MIGRATION dispositions;
  README/knowledge.md forward refs; CHANGELOG record) is approved as
  designed; the deletions execute only as the parent FID's numbered,
  operator-signed-off step. vmtest/boot-savantos-test retarget sequences
  after the next successful dev-VM boot proof, not with the deletions.

### Loop 3 — Convergence (2026-09-14)

- **RED:** Residual unknowns were exactly (i) the two delta verifications
  and (ii) the three operator decisions. Both verifications ran this
  session with pasted evidence; all three decisions are received and
  recorded above.
- **GREEN:** Steps 3, 5, 6 now each carry a design of record + an
  execution ruling. Step 2's landed implementation evidence stands
  (above); its owed release-cycle exit criterion runs at the operator's
  next release. The next concrete work items, all approved: probe
  implementation 3a → 3b → 3c (repo gates + tests per protocol), then the
  casync delta design build-out, then the kill-list change on sign-off.
- **AUDIT:** Every new claim in Loops 2–3 cites tool output reproduced in
  this FID (curl headers/bodies; pacman -Si/-Ql output) or file:line
  evidence already cited. Statuses advanced only where evidence exists.
- **Runtime keyring proof (2026-09-14, dev guest `~/savantos-phase1`,
  first-party Phase-2 image, booted through the unmodified launcher):**
  `pacman -S tree` inside the running guest completed with full signature
  verification — `installing tree…` + post-transaction hook, no keyring
  errors — and `tree 2.3.2-1` executes. The keyring gap is closed for
  images of this vintage. Honest caveat: this image predates
  `savantos-keyring-init.service` (built 2026-09-13; the unit landed
  2026-09-14), so its keyring was repaired live in the prior session —
  the unit's OWN first-boot proof on a freshly built image remains the
  named exit criterion (it is a build-time + first-boot artifact, not
  provable on a disk built before the unit existed). Same boot recorded:
  full boot proof through the unmodified launcher (receipt digest
  re-verification ALL MATCH, ready in ~12 s, graceful-shutdown POWERDOWN
  observed) — filed in FID-2026-0913-001's 2026-09-14 evidence section.
- **ADVERSARIAL:** "Converging on answers clicked in a dialog" — the
  answers ARE the operator's Law-2 approval record, reproduced verbatim
  above and in SCOPE.md; any ruling can be revisited before its
  implementation lands. "Rung 1 only tested two small assets" — the
  range behavior is a property of the release asset host (objects served
  with Accept-Ranges), not of asset size; the first large-asset delta
  test re-verifies on rootfs.ext4.zst before any consumer ships.
- **CHANGE DELTA:** ~10% of the FID (rulings + evidence). Cumulative for
  this session: ~50% across Loops 2–3 — the disclosed circuit-breaker
  tension stands as recorded in Loop 2.
- **Convergence declared:** status → converged. Implementation of steps
  3a/3b/3c is approved and queued; the loop's remaining exits are the
  release-cycle gate (step 2's criterion), the runtime keyring boot
  proof, and the signed-off kill-list execution.

## Implementation Evidence (step 2, landed 2026-09-14)

Gate interface survives, git-am implementation replaced (FID-2026-0912-001
keep-list). CI keeps the cheap gate; the full ×2 mkosi gate runs at release
time — the old patch-train split.

- **`scripts/release/build-guest.sh`**: `--contract-only` = builder-tree
  pre-flight gates (snapshot-lock consistency, bash -n on all builder
  scripts, CRLF gate, skeleton presence probes mirroring assemble.sh at
  skeleton level); full mode = `guest-image/build.sh` (mkosi ×2 determinism
  gate) → six-file payload + SHA256SUMS moved to `--output`, chowned back to
  the runner user (container root owns the /work bind writes).
- **release.yml**: prepare + publish asset lists drop the Omarchy-era
  artifacts the new builder never emits (LICENSE.omarchy, packages.lock.txt,
  provenance.json); winq-emu archives still arrive via prepare-assets.sh
  (re-point its lock source when the kill list executes).
- **smoke-guest.py**: factory-image boot proof — the instant-trial premise
  is dead on the first-party builder (grep-verified: zero hits); boots to
  multi-user.target, asserts the Plasma payload facts + SUCCESS
  `SAVANTOS_SMOKE:savant:phase2` from image-stream. test_smoke_guest.py
  unchanged (tests parse_facts).
- **Remaining named steps**: 3b Vulkan 1.3, 3c AVX2, 5 deltas, 6 kill
  list; the exit criterion (full release cycle) runs at the operator's
  next release.

## Implementation Evidence (step 3a — metered pause, landed 2026-09-16)

- **Zero-build verifications first (loop discipline):** live python
  ctypes probe confirmed `GetNetworkConnectivityHint` is exported by
  **Iphlpapi.dll** (not the api-ms-win-net-isolation dll the research
  rows assumed) and a Go scratch program pinned the struct: three 32-bit
  fields at offsets 0/4/8 — Level, Changed(+pad), Cost — rc=0 on this
  host (level=3 InternetAccess, cost=0 Unknown). Design cites measured
  facts, not header guesses.
- **Micro-contract implemented as designed:** hint API (probe), pause
  semantics (gate in `ensureVerifiedDownload` — the single wrapper all
  payload downloads traverse; metadata fetches and cached-valid files
  exempt; poll 30 s; setup-cancellation honored), settings escape hatch
  (`AllowMetered` row + settings-dialog checkbox + `-allow-metered`
  flag; settings first, explicit flag wins — the render-row pattern).
- **Fail-open rule:** probe error → reported honestly, never blocks;
  a broken hint cannot hold a normal machine's downloads hostage.
  Non-Windows builds stub to the same fail-open default so CI's ubuntu
  gates exercise the full policy matrix.
- **Gates:** `cd app && go build && go vet -unsafeptr=false && go test
  && gofmt -l` all green. New tests: 7-case decision matrix (cost ×
  override), fail-open, cost-classification semantics, real-sleep
  pause/clear loop proof, cancellation, provenance strings. The gate
  pause test caught a wrong expectation in its own first draft — fixed
  to the true invariant (gate open = unmetered OR allowed).
- **Startup provenance:** one log line records policy state + live link
  cost + source after precedence resolves; the decision is stored
  (`meteredState`) for diagnostics.

- **Landing repair (2026-09-14):** the interrupted write batch landed
  smoke-guest.py with four col-0 continuation lines (IndentationError) and
  release.yml with three col-0 tokens (step name + two run-block lines).
  Repaired and proven: py_compile OK, unittest 10/10 OK, YAML-OK on
  release.yml + ci.yml, bash -n green on build-guest.sh + build.sh,
  anchored greps at every repaired indent, zero LICENSE.omarchy refs left
  in release.yml, --contract-only wiring confirmed (ci.yml:79).

## T2.1 — casync delta design build-out (2026-09-28, design of record)

D2's verify-first ladder discharged the preconditions (GitHub Releases
serves `Accept-Ranges` on real assets; casync 2.r267 + systemd 261.2 exist
on the pinned snapshot). This section builds the casync-only delta design
out against the published T1.3 baseline (`rootfs.ext4 a2dbea53…`, 6.0 GiB;
today's update download is the 2.27 GiB `rootfs.ext4.zst`). Two format
facts are cited from a live probe on the pinned snapshot (2026-09-28,
`guest-image/out/t2-probe/`), not from documentation:

- **Blob images take a `.caibx` block index.** `.caidx` is for directory
  trees; `casync make v2.caibx v2.bin` succeeds where the `.caidx` form is
  refused ("Input is a regular file … attempted to make a directory
  archive"). A 200 MB probe image produced a 39 KB index.
- **CORRECTED DURING IMPLEMENTATION (2026-09-28): the store is a sharded
  chunk DIRECTORY, never a packed file.** The first probe's "packed
  `.castr`" claim was a misreading: casync names its default store
  `default.castr` and it is a directory of `<4-hex>/<64-hex>.cacnk`
  chunk files — an explicit `--store=store.castr` also produces a
  directory. Consequences adopted: a store cannot ship as one flat
  release asset; chunk fetches are whole-file HTTP GETs (one per needed
  chunk), NOT Range reads (which also makes T2.2's range question
  orthogonal to the delta path); and the release artifact set is the
  `.caibx` index (authenticated via SHA256SUMS) plus a **delta payload of
  only the chunks new since the previous release**, shipped as a
  single-file archive — casync's own `.caibx.d/` store directory is not
  asset-shaped. The per-chunk integrity model is unchanged: chunk IDs are
  SHA-512/256 of the uncompressed chunk, verified by the reader, so a
  seed or store corruption costs fetches, never correctness.
- **Blob images take a `.caibx` block index.** `.caidx` is for directory
  trees; `casync make v2.caibx v2.bin` succeeds where the `.caidx` form is
  refused ("Input is a regular file … attempted to make a directory
  archive"). A 200 MB probe image produced a 39 KB index.
- **The default store is a packed `.castr` blob**; chunk *directories*
  (`*.d/`) are the explicit variant. This decides the store shape: release
  assets are flat files, so a chunk directory cannot ship as an asset set,
  while one packed `.castr` can — and casync serves it over plain HTTP
  with Range GETs per chunk (the property rung 1 verified). *
  (Superseded by the correction above; retained so the record shows what
  was measured, what was misread, and when.)*

### Invariants (each one load-bearing)

1. **One trust root.** SHA256SUMS, authenticated via the `-sums-sha256`
   manifest pin, remains the only authority. The delta artifacts themselves
   (`.caibx`, `.castr`) become release assets with their own SHA256SUMS
   lines. The seed (the client's currently-installed `rootfs.ext4`) is
   UNTRUSTED local state: chunks are content-addressed, so a corrupted
   seed only causes a missing/mismatched chunk to be fetched or the final
   digest to fail — never a silently wrong image.
2. **The existing acceptance gate is unchanged.** Any reconstruction is
   accepted only after the full-image `verifyFileSHA256(rootfs.ext4)`
   against SHA256SUMS passes — the identical property `decompress` already
   enforces (`app/fetch.go:299-304`: unpack → verify → rename). The delta
   path slots into that same verify-then-rename flow; it cannot weaken it.
3. **Additive, both directions.** Releases without `.caibx`/`.castr` take
   the existing zst path byte-for-byte unchanged; releases with them MAY
   take the delta path when a usable seed exists (the currently-installed,
   digest-verified rootfs). Portable mode is out of scope (dir-copy
   semantics).
4. **No second update system.** Host-driven, launcher-initiated, same
   six-file payload swap; sysupdate stays the named open decision (D2),
   untouched by this design.

### Design of record

- **Artifacts per release (builder-emitted):** `rootfs.ext4.caibx` (block
  index) + `rootfs.ext4.castr` (packed chunk store), generated by casync
  in the assemble stage where the built image and the determinism gate
  live. Only `rootfs.ext4` is indexed — the guest consumes the plain
  image, so the delta path also skips the 2.27 GiB zst download and the
  decompress CPU pass entirely. Kernel/initramfs/spec/manifest stay
  small-file downloads.
- **Determinism obligation:** the two new artifacts join the dual-build
  digest comparison only if casync's output is byte-stable across
  assemblies (content-derived chunking suggests yes; VERIFY is a named
  exit criterion — if unstable, they are emitted post-gate and
  authenticated by SHA256SUMS alone).
- **Launcher-side reader, not the casync binary.** casync has no
  maintained Windows build and the launcher must not gain a C dependency
  (desync-the-library was evaluated and rejected: its go.mod pulls the
  otel/grpc graph). **IMPLEMENTED** as a hand-rolled platform-neutral
  reader (`app/casync_reader.go`): caibx parse (`[size][magic]` elements,
  `CaFormatIndex`/`CaFormatTable`/tail-marker per desync v1.1.4's
  const.go/format.go — the format spec cited from its source, not
  memory), SHA-512/256 chunk digest verification (stdlib `crypto/sha512`),
  zstd chunk decode (existing klauspost dependency), sharded-directory
  and HTTP store backends, sparse-aware reconstruction with the seed's
  ID→offset map from the previous release's index. Format compatibility
  is pinned by committed casync-generated fixtures
  (`app/testdata/casync`, generated in the pinned-snapshot container):
  round-trip parse + per-chunk digest verification against image bytes,
  reconstruction from store-only / store+seed / HTTP store, corrupt-seed
  immunity, missing-chunk failure with partial cleanup, malformed-index
  rejection. Platform boundary held: no windows-only helper is called;
  Linux-target vet + test compile green.
- **Integration point (exact): IMPLEMENTED** in `ensureGuest`'s rootfs
  branch (`app/fetch.go`): cached rootfs fails digest →
  `deltaReconstruct` (non-portable, non-empty image only): rename the
  current image to `.seed` (never removed up front) → advertisement is
  authoritative (both `.caibx` indices present in SHA256SUMS; nothing is
  probed) → fetch+verify the two indices via the platform-neutral
  download path (metered gate honored) → reconstruct against the seed →
  the UNCHANGED full-image `verifyFileSHA256` gate → receipt + done. On
  ANY failure: seed/partials cleaned, rootfs removed if partial, and the
  existing zst path runs unchanged. First installs have no seed and take
  the zst path; portable installs are excluded.
- **Chunk transport (corrected):** chunk fetches are whole-file GETs
  against the release's delta chunk archive/layout; there are no Range
  reads in the delta path (T2.2's range re-verification remains owed for
  the zst resume path, which predates deltas).
- **Metrics in the log:** the reconstruction logs chunks fetched vs
  seed-supplied and bytes transferred, so the acceptance run MEASURES the
  win instead of asserting it.

### Verification (the T2.1 gate)

- gate: Go reader unit tests vs committed casync fixtures (reconstruction
  digest-exact; malformed index rejected; truncated store falls back).
- gate: builder emits the two artifacts and (pending the determinism
  check) the dual-build gate covers them.
- gate: E2E on the local release base — baseline N (published T1.3
  payload) + release N+1 built from the same tree; a launcher update run
  takes the delta path, logs the measured transfer (target < 100 MB for a
  realistic package-bump pair), passes the full-image digest, and boots
  the reconstructed image through the unmodified launcher. If the first
  real pair measures above target, the honest number is recorded and the
  chunking parameters become the investigation — never a silent
  acceptance.
- gate: fallback proof — a release without the delta artifacts (or a
  crippled store) completes via the zst path unchanged.

### Implementation corrections (2026-09-28, builder emission)

Measured while wiring the builder side; each fact is a probe result, not
an assumption.

- **Default store location (probe, casync 2.r269 in-container):** casync
  writes the default store NEXT TO THE INDEX FILE, not in the process
  cwd. The first delta build died at `mv default.castr` because the store
  had landed beside the index in `build-a/contract/` while the mv looked
  in `/work`. Fix: assemble.sh passes `--store="$out/rootfs.castr"`
  explicitly (rm'd empty beforehand, so a reused store can never merge
  old chunks into a new index's store), the mv is gone, and build.sh's
  `/work/default.castr` hygiene line was removed — measured, there is
  nothing in the cwd to clean.
- **Chunk files are 0444:** casync marks store chunks read-only
  (immutable-by-design). Harmless in-container (root unlinks regardless),
  but delta-finalize.py runs HOST-side in the publish tail, and Windows
  Python refuses to unlink read-only files (WinError 5, measured). The
  script now removes via chmod-then-unlink fallback (no-op on Linux).
- **Publish-tail ordering:** delta finalization runs on
  `build-a/contract` BEFORE the payload copy. First delta-capable release
  deletes the entire ~6 GiB store; doing that pre-copy avoids dragging
  ~100k chunk files through the virtiofs mount only to delete them
  host-side after the copy. Nothing re-runs the finalizer on
  `out/contract` — in first-release mode its rc=3 fallback would strip
  the already-shipped caibx.
- **Finalizer validated against REAL casync bytes** (host-side Windows
  Python, the production environment): 5-scenario battery — first-release
  mode (store removed, bare caibx ships), 100% overlap (0 chunks kept,
  prev index copied), missing store (rc=3 fail-closed), parser-vs-store
  ID agreement (51/51), synthetic partial overlap (26 pruned / 25 kept,
  exactly as constructed). The battery caught two real bugs on its first
  run: a NameError on the prune path (copyfile after an import removal)
  and the read-only unlink above — both fixed same day.
- **Extra determinism point:** identical input indexed through two
  different `--store` paths produced byte-identical caibx digests —
  store location does not leak into the index.
- **Errexit probe (record so nobody "fixes" it):** the
  `[[ -f $f ]] && sha256sum "$f"` loop appending conditional SHA256SUMS
  entries is `set -e`-safe — a failing non-final command of an `&&` list
  is exempt from errexit (verified live). Converting it to if/fi blocks
  would be churn, not correctness.
- **Trap recurrence:** the single-quoted container script in build.sh
  claimed a third victim — the comment "rm's the store" inside it killed
  `bash -n` exactly like the documented 2026-09-28 case. Comments inside
  that string carry the same apostrophe ban as code.

### Builder emission verdict (2026-09-28, delta build 2)

The gate ran green end-to-end; every declared criterion has now been
exercised on real output:

- **Emission + determinism:** both assemblies emitted identical delta
  indexes — `delta index emitted (3313864 bytes; 76679 chunks)` twice, gate
  line `rootfs.ext4.caibx 1b97d068…` with zero NONDETERMINISM lines. Seven
  files gated, not six.
- **First delta-capable release shape (asserted against the published
  payload):** caibx present (3313864 bytes), no `rootfs.castr/`, no
  `rootfs.ext4.prev.caibx`, caibx entry present in SHA256SUMS (8 entries,
  all `sha256sum -c` verify), `release-base.json` sumsSha256 recomputed
  after the tail (`93add1f6…`).
- **Live reader probe (new, opt-in `TestLiveReconstructShippedPayload`):**
  the shipped reader parses the published index (82844 chunk references /
  76679 unique chunks — casync dedupes, so the reference count exceeds the
  file count) and reconstructs the 6 GiB image from a seed with an EMPTY
  store — every chunk resolved through the reader's ID matching — in 44 s;
  the result digest-matches the published rootfs (`ea574cb3…`, the same
  value the dual-build gate printed).
- **Publish tail (third occurrence of the handle failure):** the hardened
  tail fired as designed — 6×10 s retries, FATAL with `build-a/contract`
  intact and hand-publish instructions. The manual publish replicated the
  tail's order (delta-finalize first-release on build-a → store dropped
  pre-copy → copy → SHA256SUMS + runtime zip → release-base.json). Two
  hand-publish lessons recorded: re-verify copy targets after any
  busy-directory failure, and the delta-entries SHA256SUMS block is easy
  to forget outside the script — the first emitted sums lacked the caibx
  entry until the shape assertion caught it (the launcher's advertisement
  honesty depends on that block).
- **Not yet exercised:** release N+1 against seed N (partial store fetch),
  which needs a second payload — the E2E row stays open with its
  measurement obligation (target < 100 MB).

## Resolution

- **Closed Date:** —
- **Fix Description:** —
- **Tests Added:** —
- **Verification Evidence:** —
- **Archived:** —

## Lessons Learned

(written at closure)