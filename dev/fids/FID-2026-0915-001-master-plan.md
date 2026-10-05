# FID: Master plan — all remaining work, organized (M-plan v1)

**Filename:** `FID-2026-0915-001-master-plan.md`
**ID:** FID-2026-0915-001
**Severity:** high (governing)
**Status:** converged (plan of record; children carry their own loops)
**Created:** 2026-09-15
**YAGNI-Compliance:** Verified (this FID only ORGANIZES approved work; it
adds no feature, orders existing approved items, and names every decision
that is still the operator's)
**Parent:** FID-2026-0912-001 (first-party OS pivot)
**Children:** T0 → T4 (below); every existing open FID is claimed by exactly
one track

---

## Summary

Governing plan for ALL remaining work after the 2026-09-15 commit landing
(`717bb15..37c3aab`). Five tracks (T0–T4), each with a named child FID (new
additive track T5, 2026-09-15: the desktop experience pass, FID-2026-0915-006 —
closed 2026-09-16).
files where none exists), a single source FID for every item (no orphan, no
double-claiming), explicit dependency edges, a recommended sequence, and the
decision points that belong to the operator. Ordered to protect the two
load-bearing truths of this project: the pivot FID's de-risking order
(builder → desktop → agent → factory), and Law 4 (nothing lands without its
consumer).

## The plan (five tracks)

### T0 — Unblock & hygiene (hours; no design risk)

| # | Item | Source | Evidence base |
|---|------|--------|---------------|
| 0.1 | Push `main` (7 commits) so CI runs green remotely | 0914-002 step 2 | `9e48202` fixed release.yml + `--contract-only` wiring |
| 0.2 | Omarchy kill list (operator sign-off now unlockable): `git rm` `guest-build/` 51 files; `runtime.lock.json` → `scripts/release/` + `prepare-assets.sh:14` repoint in the SAME change; docs sweep per D3 dispositions; CHANGELOG; vmtest retarget sequenced AFTER 0.3 | 0914-002 step 6; parent 0912-001 | Full inventory + coupling findings in Loop 2, rulings D3 received |
| 0.3 | Dev-VM boot proof on the committed tree (vmtest retarget precondition) | parent verification section | Sep-15 fresh-boot proof exists for the pre-commit tree; repeat on `37c3aab` to make the retarget honest |
| 0.4 | Tree hygiene: delete stray `nul`; disposition `knowledge.md` (commit / ignore / delete); scratchpad scripts | operator call; not in any FID | `git status` untracked inventory |
| 0.5 | SCOPE.md missing-summaries line: `[OPEN-OUT-OF-SCOPE] → RESOLVED` | session-summaries backfill | file reads `[BLOCKED]` to agent tools; 30-second operator or later-session edit |

**Exit:** CI green on the remote; legacy builder gone; every future boot
proof runs on the committed tree.

### T1 — Factory hardening (small, gate-friendly; new child FID)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 1.1 | `/usr` + `/usr/share` mode-0777 normalization in the builder + assemble.sh mode assertion | 0914-003 Loop 3 finding | one-line root cause class: tar/mke2fs inherited permissive modes; assert 0755 in the same gate that guards content. **IMPLEMENTED 2026-09-27** (per-path policy, ruled): normalization before the tar stream + debugfs mode assertion on the shipped image content |
| 1.2 | Launcher headless `-fresh` path (`-yes` flag or probe bypass) so automation can reset disks | 0914-003 Loop 3 finding | GUI dialog `confirmResetBackup` unreachable in headless runs; consumer = vmtest/smoke automation. **IMPLEMENTED 2026-09-28**: no `-yes` flag added — `-headless` is the explicit confirmation; `confirmResetBackup` proceeds without the full-backup dialog, logs the decision, honors a pending cancel (unit-locked in `recovery_windows_test.go`); consumer documented as `dev-vm.sh boot -fresh -headless`; live proof on the real target is operator-gated |
| 1.3 | Dual-build re-run on the committed tree (validates 1.1 + proves determinism survives the commit boundary) | 0914-002 gates | produces the T2 delta-baseline image. **RAN 2026-09-28: GATE GREEN, twice.** Both runs pass all six digest comparisons; run 2 reproduced run 1's digests byte-identically (`rootfs.ext4 a2dbea53…895d5`), i.e. determinism holds across independent full pipelines, not just within one. Baseline published to `guest-image/out/contract` + `release-base.json` (sums `5525ba54…755e`), carrying the polkit rule from commit `0131c9d`. The run also exposed the recurring publish-tail trap (transient handle on `out/contract` killed the green build and the EXIT trap destroyed the proven copies — second occurrence after 2026-09-19); fixed in `build.sh`: trap released once the gate has spoken, removal retries with backoff, and residual failure preserves `build-a/contract` with hand-publish instructions (exercised live by run 2) |

**Exit:** shipped images cannot be world-writable; automation can reset a
disk; fresh baseline image for delta work.

### T2 — Deltas & release cycle (0914-002 steps 5 + exit criterion)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 2.1 | casync-only delta design build-out over the F1–F7 contract: chunk store + seed (current rootfs on the data disk) + streamed index; host still authenticates full-image SHA256SUMS as the ONLY trust root (delta = optimization, never a second trust anchor) | 0914-002 Loop 2/3 (D2 ruling: design of record) | zstd-split documented fallback. **DESIGNED 2026-09-28** (FID-2026-0914-002, T2.1 section): builder emits `rootfs.ext4.caibx` + packed `.castr` (format facts probe-verified on the pinned snapshot); launcher gains a Go read-only caibx/castr extractor integrated at the `ensureGuest` rootfs branch with the existing full-image digest as the unchanged acceptance gate; additive both directions with zst fallback; sysupdate stays the named open decision. **IMPLEMENTED + PROVEN 2026-09-28** (commits 4fdec4d/25710ec): builder emits the caibx + sharded store (explicit `--store`; the default store lands next to the index, not the cwd — measured), the caibx joined the dual-build digest gate (seven files identical; `rootfs.ext4.caibx 1b97d068…`), the first delta-capable release published as the bare caibx (no store/prev index; sums `93add1f6…`), and the shipped reader reconstructed the published image from a seed with an empty store digest-exact (`ea574cb3…`) — the N→N live proof. Open: the E2E N+1 measured transfer (target < 100 MB). **MEASURED 2026-10-03: 3 chunks / 87,522 bytes (0.1 MiB) against the published N index — met; the drift is the embedded savant-core VCS stamp. The 09-29 publish-tail FATAL destroyed the published N payload (chain incident + survivor inventory in 0914-002); a restore rebuild is in flight** |
| 2.2 | Large-asset range re-verification on `rootfs.ext4.zst` before any consumer ships | 0914-002 Loop 3 ADVERSARIAL | **RE-VERIFIED 2026-09-28**: the resume suite (27 tests, real httptest servers) covers 200-cut → 206 append with Range-offset assertions, cross-call `.part` retention, and a new double-interruption lifecycle test (offset advances cut1→cut2, append-only, never truncated). Operational caveat for local proof servers: `python -m http.server` ignores Range (the launcher's 200-restart fallback engages by design); `docker run -p -v …/www` serves Range — use it for the delta E2E |
| 2.3 | Release cycle dry run: prepare → pin → publish → smoke on a fresh data dir (first Plasma-based signed release) | 0914-002 exit criterion | needs T1.3 baseline |
| 2.4 | **Operator decision (named, not silent):** sysupdate guest-pull vs host-contract | 0914-002 Loop 2 RED (d) | F1–F7 collision documented; no code until ruled |

**Exit:** update downloads shrink from ~2 GB to <100 MB; the exit criterion
of 0914-002 is discharged.

### T3 — Launcher probes (0914-002 step 3; rulings D1: all three now)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 3.1 | Metered-pause: `GetNetworkConnectivityHint` + pause semantics in `downloadVerifiedWithOptions`/`ensureRuntime`/`ensureGuest` + settings escape hatch | 0914-002 Loop 2 GREEN (3a) | needs its own micro-contract (pause what, show what, override how) before code — named in the FID. **IMPLEMENTED 2026-09-16** (evidence: 0914-002 step 3a section) |
| 3.2 | Vulkan 1.3 detection: adapter enumeration + version assertion + probe-record shape, no graphics deps (DXGI/D3DKMT-style native work) | 0914-002 Loop 2 GREEN (3b) | feeds render-probe reasons + guest compositing flag. **IMPLEMENTED 2026-10-03** (capability probe: Khronos ICD-manifest walk + version assertion; D3DKMT corrected away — `displayDriverIdentity` is the one adapter truth; no new guest flag — `savantos.render` is the consumer; evidence: 0914-002 3b/3c section) |
| 3.3 | AVX2 probe via `GetLogicalProcessorInformationEx` CPID bits; lands feeding the probe record/diagnostics; VLM-flag consumer arrives with T4 (named, not silent, wiring gap) | 0914-002 Loop 2 GREEN (3c) | order 3a → 3b → 3c is the D1 ruling. **IMPLEMENTED 2026-10-03** (`IsProcessorFeaturePresent(PF_AVX2)` — GLPIE corrected, it carries no CPUID bits; VLM-flag consumer still T4.6, named) |

**Exit:** all three probes in the render-probe record; 3c's gap named for T4.

### T4 — Phase 3 agent control plane (0914-001; the product core, longest pole)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 4.1 | Binding survey (EIS/libei, AT-SPI2) + runtime/toolchain selection by evidence; in-tree location for the agent layer | 0914-001 Loop 1 GREEN (a),(b),(d) | first implementation step; unknowns become named exit criteria |
| 4.2 | Safety-law architecture: tiered approvals, audit overlay, kill-switch wiring (how the input channel severs), unprivileged confined identity | 0914-001 scope; parent ruling 2 | nothing ships without this designed; gates all of T4 |
| 4.3 | Savant Core daemon + input adapter + AT-SPI2 client, contract-gated | 0914-001 steps 2 | rides the F1–F7 payload contract |
| 4.4 | Kirigami layer-shell UI + cursor yielding | 0914-001 scope | after the daemon core |
| 4.5 | Exit demo: EIS injection + AT-SPI2 tree read + kill-switch sever, live in the dev guest | 0914-001 verification | pasted into the FID as evidence |
| 4.6 | AVX2→VLM flag wiring (consumes 3.3) | D1 ruling note | the named wiring gap closes here |

**Exit:** 0914-001's verification section, demonstrated live.

### T5 — Desktop experience pass (additive, 2026-09-15; child FID 0915-006 — CLOSED)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 5.1 | Clock/date redesign (compact `ddd d MMM`) | 0915-006 D1 | landed, boot-verified |
| 5.2 | Wallpaper v3 (deterministic generator, 4K) | 0915-006 D2 | byte-identical on screen |
| 5.3 | Icon decision (Papirus-Dark retained; colloid absent from pin) | 0915-006 D3 | fallback rule of record |
| 5.4 | Chromium preload + favorites/taskbar pins | 0915-006 D4 | in-image verified |
| 5.5 | Featherpad notepad | 0915-006 D5 | in-image verified |

**Exit:** met 2026-09-16 (dual-build GATE GREEN + fresh-image boot proof +
rendered-desktop screenshot). Ideas ledger (theming, extensions) remains
open in 0915-006 for future passes.

## Dependency edges (the plan's spine)

- T0.2 (kill list) → T0.3 (boot proof on committed tree) → vmtest retarget.
- T1.1/T1.2 → T1.3 (one rebuild validates both).
- T1.3 → T2.3 (baseline image); T2.1 → T2.2 → any delta consumer.
- T3.1 → 3.2 → 3.3 (D1 order); T3.3 → T4.6.
- T4.2 gates T4.3; T4.1 gates 4.3's bindings; T4.3 gates 4.4/4.5.
- Parallel-friendly: T1 ∥ T3 (different components: builder vs launcher);
  T2 design ∥ T3 implementation.

## Recommended sequence (critical path)

**T0 (today: push + kill list + boot proof) → T1 (hardening + rebuild) →
T3 (probes, while T2 design matures) → T2 (deltas + release dry run) → T4
(agent: survey → safety law → daemon → demo).**

Rationale: T0 removes the governance debt that taxes everything else; T1
cheaply hardens the artifact every later track consumes; T3 is approved and
unblocked now while the T2 delta design is operator-gated at 2.4; T4 is the
longest pole with the highest value and starts design as soon as T0 frees
the tree.

## Perfection Loop (on the plan itself)

### Loop 1 — Reconciliation (2026-09-15, folder-audit + 0-EOF FID reads)

- **RED:** Is any remaining item unowned, double-owned, or invented?
- **GREEN:** Coverage check against sources: every item above cites its
  FID:section (0914-001 steps/Loop-1 exits; 0914-002 steps 3/5/6 + exit
  criterion + Loop-2/3 rulings; 0914-003 Loop-3 findings; parent
  verification + sign-off gates). No item exists in the plan that is not
  already approved somewhere; no open FID item is unclaimed. Double-claim
  check: the AVX2 probe appears in BOTH 0914-002 step 3 and as 0914-001's
  VLM consumer — resolved by D1's own ruling (probe now in T3, consumer in
  T4.6). The kill list appears in parent + 0914-002 — resolved by the
  parent's own framing (execution step lives in 0914-002; sign-off in the
  parent).
- **AUDIT:** FID statuses read fresh this session (0914-001 `analyzed`,
  0914-002 `converged`, 0914-003 `proven`, 0913-001 `fixed`, 0912-002
  `converged`); commit list `34f6fa8..37c3aab` verified.
- **ADVERSARIAL:** "The plan invents work." — T0.4/T0.5 are hygiene the
  folder audit left visible; they are labeled operator-call, not scope
  growth. "Tracks duplicate FIDs." — tracks are sequencing views over FID
  items; every item's canonical home stays its FID.
- **CHANGE DELTA:** n/a (first pass, new document).

### Loop 2 — Ordering / risk / YAGNI (2026-09-15)

- **RED:** What ordering hides risk or violates Law 4?
- **GREEN:** (i) T2.4 blocks delta code — so T2 implementation waits on an
  operator ruling while T2 design proceeds; the plan reflects that instead
  of silently choosing. (ii) Law 4 on T3.3: consumer lands in T4.6, which
  is why the probe lands as probe-record/diagnostics content now, exactly
  per the D1 ruling's wording. (iii) T1.3 before T2.3 avoids designing
  deltas against a pre-commit-tree baseline. (iv) vmtest retarget stays
  sequenced after a committed-tree boot proof, per D3.
- **AUDIT:** Risk levels cited from source FIDs; kill-list blast radius
  (51 tracked files + 2 coupling points) from Loop-2 inventory.
- **ADVERSARIAL:** "Do T4 first — it's the product." — Rebutted by the
  pivot FID's own de-risking order and by blast radius: T4 on an
  un-hardened, un-released artifact multiplies rework; T4 design (4.1/4.2)
  CAN start early and is sequenced to.
- **CHANGE DELTA:** ~15%.

### Loop 3 — Convergence (2026-09-15)

- **RED:** Are all operator decision points surfaced, and is every exit
  measurable?
- **GREEN:** Decision points enumerated: (1) T0.2 kill-list sign-off
  (design approved; waiting), (2) T0.4 hygiene dispositions, (3) T2.4
  sysupdate architecture ruling, (4) T1.1 mode policy detail (0755 vs
  per-path). Every track ends in a verifiable exit (CI green; kill list
  committed + boot proof; mode assertion green in the gate; dry-run
  release; probes in the record; live agent demo).
- **ADVERSARIAL:** "Plans like this rot." — Mitigated by structure: this
  FID orders and sequences ONLY; each item's canonical record stays in its
  child FID, so plan drift cannot orphan evidence; the plan is re-run
  through its loop whenever a track closes.
- **CHANGE DELTA:** ~10%.
- **Convergence declared:** plan of record. Execution of T0 items may
  begin immediately on operator go.

## Operator decision points (all four)

1. **Kill-list sign-off** (T0.2) — design approved 2026-09-14; execution
   now unblocked by the boot-proof condition.
2. **Hygiene dispositions** (T0.4): `nul` delete; `knowledge.md`
   commit/ignore/delete; scratchpad scripts keep-or-delete.
3. **sysupdate architecture** (T2.4): guest-pull (contract bend) vs
   host-pull (sysupdate as named open decision) vs defer.
4. **Mode policy** (T1.1): flat 0755 on /usr tree vs per-path table —
   ruled 2026-09-27 (implement T1.1 now): the implementation ships under
   the per-path policy the register recommends (a flat 0755 would strip
   setuid bits and legitimate 0600 modes); the full-tree question stays
   at the factory design checkpoint.

## Verification Gates

- gate: docs (markdownlint) — run on this file at commit
- gate: each child FID's own declared gates (already declared there)
- gate: plan re-run through its loop at every track closure

## Approved completion addendum — 2026-09-16

The operator approved the completion outline and L3 execution boundaries in
`SCOPE.md`. This addendum supersedes stale ordering and status assertions
above, without discarding the historical rulings. Child FIDs retain their
requirements and acceptance evidence. No missing work is silently deferred.

### Execution sequence and acceptance

| Stage | Scope and canonical owners | Exit evidence |
|---|---|---|
| 1 | Scope/baseline: this master and SCOPE; reconcile all 14 active FIDs, preserve existing work, record source/artifact identity | Baseline gate results; each requirement assigned to implementation, missing proof, or explicit decision |
| 2 | Launcher: 0916-001 override refusal, anchors in all provisioning callers, receipt provenance, complete modal audit, early durable logs, watchdog lifecycle; 0915-002 bounded close sequence; 0914-003 reset follow-up | Refusal before network I/O; damaged/partial-install and runtime-only cases; genuine headless branch tests; 10 close and 10 relaunch cycles on an approved disposable target |
| 3 | Factory/release integration: 0914-002 and T1 follow-ups | Pre-image permission normalization and finished-image assertions; reliable content-negative tests; builder argument/prerequisite validation; one owner for runtime acquisition and manifest assembly; isolated harness ownership |
| 4 | Desktop/current-image proof: 0912-002, 0913-001, 0915-006, 0916-002 | Factory generation freshness; Cursor installation/update/sandbox contract reconciled; current-image fresh-disk boot, Kate/Cursor launch, desktop screenshot, service health, restart and clean shutdown |
| 5 | Probes: 0914-002, metered then Vulkan then AVX2 | Correct policy diagnostics and agreed pause semantics; validated capability APIs; positive/negative/error tests; reachable diagnostics/render consumers |
| 6 | Deltas: 0914-002 | casync index/chunks/reconstruction; authenticated full-image acceptance; interruption/corruption/fallback tests; large-asset range proof; representative measured transfer target |
| 7 | Agent: 0914-001 and 0915-003/004/005 | Binding/toolchain contract, observation, independent revocation/privilege topology, policy-gated input, operator controls/UI, cursor yielding, VLM budget/AVX2 consumer, live integrated demo |
| 8 | Integrated release and closure: 0914-002, parent 0912-001, all children | Complete gate suite and fresh-install/update recovery proof; separately authorized signing/publication; release smoke; evidence-backed archival of every eligible child |

Stage 2 protection precedes developer payload experiments. Stage 3 precedes
new factory proof and delta-baseline generation. Stage 5 preserves the
approved probe order; its AVX2 consumer completes in stage 7. Agent binding
and safety design can start earlier, but input capability must not precede
independently enforced safety. VM operations require the target checkpoint.

### Per-FID reconciliation and remaining obligations

| FID suffix | Completion disposition |
|---|---|
| 0912-001 | Preserve historical Phase-1 proof; reconcile inherited host/guest integration requirements, assign any gaps to successors, and close the umbrella only after its approved agent/factory/release obligations pass |
| 0912-002 | Do not reimplement superseded desktop details; reconcile successors and capture any missing current-image restart/clean-exit proof |
| 0913-001 | Preserve recorded identity/hover proof; tie final rendered state and service/plugin evidence to the actual factory artifact |
| 0914-001 | Control-state daemon is only a foundation; complete observation, interaction, independent safety, UI, resource policy, and parent live demo |
| 0914-002 | Preserve implemented keyring/metered/legacy-retirement work; finish policy/probes, factory/release integration, harness retarget, deltas, and signed-release acceptance |
| 0914-003 | Preserve successful PowerDevil shutdown evidence; reconcile inhibitor acceptance wording; finish permissions and explicit automated-reset follow-ups without equating headless with consent |
| 0915-001 | Maintain one current dependency map and an owner/gate for every obligation; reconcile status after each child closes |
| 0915-002 | Implement concrete bounded shutdown/fallback transport; persist early failures; prove 10 close and 10 relaunch cycles, including a forced-kill predecessor in an approved disposable environment |
| 0915-003 | Validate actual KWin/portal interfaces, coordinates, failure behavior and toolchain; interface presence alone does not prove injection or revocation |
| 0915-004 | Converge independently enforceable revocation, operator-only re-arm, identity separation, approvals, audit visibility and confinement before interaction ships |
| 0915-005 | Preserve control milestones; complete observation/input/UI milestones, meaningful health/lifecycle tests, image-service assertions, CGO delivery, and required state recovery |
| 0915-006 | Reconcile historical D1-D5 closure and archival; fix generation freshness/builder-validation follow-ups; keep D6 as proposals, with hardening/Cursor owned by their successors |
| 0916-001 | Complete D1/D1b/D1c and all-modal D3 scope; correct Linux platform boundary; strengthen phase/watchdog/logging tests; prove actual G4 branches and retain G6 as a conditional reproduction obligation |
| 0916-002 | Preserve saved six-artifact comparison, distinguish subsequent publication failure/recovery, reconcile vendor/update/sandbox contract, and prove Kate/Cursor on the new factory disk |

### Newly discovered defects and evidence cautions

These findings belong to the approved stage-1 investigation; static findings
are not runtime verification or permission to skip child-FID design.

- `app/phase.go` lacks the Windows build boundary described by its comment.
  Linux-target vet reproduced `phase.go:35:3: undefined: fatal`.
- All-modal headless acceptance is not established by the three UI wrappers;
  fatal/reset/repair paths need their own production-path tests.
- Factory daemon mode normalization follows image creation in `assemble.sh`;
  source-tree chmod after assembly cannot prove finished-image permissions.
  (Fixed 2026-09-27: the normalization now precedes the tar stream and is
  gated by a debugfs mode assertion on the image content — T1.1.)
- Builder runtime publication and release preparation disagree about who
  supplies the runtime archive and SHA256SUMS entry. Linux runner environment
  assumptions also require correction.
- Metered policy descriptions require argument-order correction and an
  explicit admission-versus-mid-transfer semantics check.
- Existing control-daemon KILL tests do not revoke input capabilities. Audit
  shutdown-reply ordering, health reporting, and final-image service gates.
- Cursor's saved dual-assembly comparison passed before publication failed.
  Current artifact presence does not prove publication recovery or GUI launch.
- Historical desktop/PowerDevil proof is not evidence that the missing host
  fallback ladder works. An updated factory payload is not a fresh guest disk.

### Decision register and approval boundaries

- casync-only work may proceed under the source ruling; the earlier statement
  that sysupdate blocks all delta code is superseded. Sysupdate adoption is
  still an explicit operator architecture decision.
- Recommend a per-path permissions policy, not recursive executable mode for
  all files. Confirm the policy at the factory design checkpoint.
- Define explicit disposable-target/reset authorization and backup behavior
  before destructive tests. Never modify a production directory by pointer.
- Confirm independent agent privilege/revocation topology before enabling
  input. AF_UNIX/socket permissions alone do not establish role separation.
- Signing-provider availability and release/version/pins require a release
  checkpoint; no secret inspection, signing action or publication is implied.
- Commits/pushes, existing-work disposition, scope changes and revised
  acceptance criteria require separate approval. D6 ideas are not added scope.
- Repository documentation claims about external SignPath/CI state require
  current read-only evidence before being reported as current facts.

### Stage-1 baseline evidence

Starting source: HEAD `fd5a888`, Windows Go `go1.27.0 windows/amd64`.
Existing `guest-image/build.sh` changes and untracked artifacts preserved.

Commands in `app/`:

```text
go build ./...                         PASS (exit 0)
go vet -unsafeptr=false ./...          PASS (exit 0)
go test ./...                         PASS
ok github.com/savant0x/SavantOS/app 9.698s
?  github.com/savant0x/SavantOS/app/cmd/sign-update [no test files]
gofmt -l .                            PASS (empty output)
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go vet ./...
vet.exe: .\phase.go:35:3: undefined: fatal
```

The environment-prefix form above denotes process-scoped target settings;
commands were executed through PowerShell environment variables.

The daemon passed Linux-target vet/build and test compilation using the
Windows Go toolchain. The resulting Linux test executable ran under WSL
Ubuntu with `-test.v=true -test.timeout=90s`; all eight tests passed. These
are existing control-state/socket tests, not product-agent input safety proof.
Native Linux Go/race CI parity is not established: WSL reported
`go: command not found` on its current PATH. No toolchain was installed.
An initial unquoted `-test.v` invocation was split by PowerShell and rejected;
the quoted-argument rerun supplied the successful test evidence.

Repository `bun run lint:md` and `git diff --check` passed before planning
edits; documentation gates must be rerun after each planning update.
No application/VM launch, image build, remote CI query, commit or push occurred.

Subsequent stage-1 correction and verification:

- Added the missing Windows build constraint in `app/phase.go` and supplied
  the tracker dependency in the existing non-Windows test harness. Evidence
  and the intermediate dependency failure are recorded in 0916-001.
- Windows build/vet/test/format passed after the correction. Linux-target
  vet/test compilation passed; the compiled launcher suite ran under WSL
  and returned `PASS`. Focused watchdog/modal/phase tests also returned
  `PASS` over ten repetitions. This does not establish race freedom.
- Release-helper Python compilation passed; unittest discovery ran 10 tests
  and returned `OK`. Runtime lock validation returned
  `ok - locked QEMU 2ce303cfbbc8 and virglrenderer e80354b8f5a0 with 2 recipe patch(es)`;
  runtime shell syntax checks passed.
- The exact guest-contract command returned snapshot-lock OK and passed its
  preceding shell/content checks, then failed at line 104:
  `go: command not found`, `savant-core gate FAILED`. Do not mark that gate
  green based on the separately passing cross-compiled daemon tests.
- `SCOPE.md` is intentionally ignored by `.gitignore:51`; its local update
  is present, while this tracked addendum carries the durable authorization.
- Markdown lint and whitespace checks passed after the planning/FID edits.
  Git emitted LF-to-CRLF normalization notices for edited tracked files;
  no line-ending policy was changed.

Race-gate status (2026-09-16): the local host cannot run `go test -race`
(Windows Go without gcc; `cgo: C compiler "gcc" not found` with
`CGO_ENABLED=1`). This is an environment limitation, not a gate failure:
race testing is CI's defined job (`ci.yml` runs `go test -race ./...` on
ubuntu-latest, which has gcc). The suspected watchdog goroutine race remains
a static finding until CI or an approved Linux toolchain executes the race
suite. The daemon gate was additionally verified natively on Windows
(`go vet ./...`, `go test -count=1 ./...`, `gofmt -l .` all clean in
`guest-daemon/savant-core`); the WSL contract-gate failure is an environment
PATH limitation, recorded above, not a code failure.

Final stage-1 gate evidence (fresh, uncached, 2026-09-16):

```text
app/:    go build ./... && go vet -unsafeptr=false ./... &&
         go test -count=1 ./... && gofmt -l .
         ok github.com/savant0x/SavantOS/app 9.320s   (all four gates clean)
guest-daemon/savant-core/: go vet ./... && go test -count=1 ./... &&
         gofmt -l .   ok 0.057s (all three gates clean)
repo:    bun run lint:md && git diff --check   clean
```

Stage-1 exit: the configured baseline gates pass on the corrected tree. The
remaining stage-1 items are recorded as owned follow-ups, not silent
deferrals: native Linux/race parity (CI or approved toolchain), the exact
WSL contract-gate run, remote CI evidence, and untracked-work dispositions
(operator call). Stage 2 (launcher protection) is next per the approved
sequence.

### Stage-1 re-baseline — 2026-09-27 (current tree)

The tree moved 24 commits past the 2026-09-16 baseline (`fd5a888` →
`9b4789d`; FID-2026-0916-002 / 0917-001 / 0917-002 / 0922-001 work
landed). Source identity: HEAD `9b4789d`; `main` is **ahead of
`origin/main` by 2** (`1e79220`, `9b4789d`, unpushed). The working tree
carries preserved uncommitted work (50 paths: pre-existing `app/`
render-probe/settings edits, FID record updates, untracked scratchpad
tooling) — disposition is an operator call per the decision register.
Factory artifact identity of record: 2026-09-22 published contract,
SHA256SUMS digest `3ef63506…`; Arch snapshot 20260811; runtime locks
QEMU `2ce303cfbbc8`, virglrenderer `e80354b8f5a0`.

Fresh gate results (2026-09-27, this host, Go 1.27.0 windows/amd64):

```text
app/:      go build / go vet -unsafeptr=false / go test -count=1 (ok 9.7s)
           / gofmt -l — all clean
app/ linux-target: GOOS=linux go vet + go test -c — clean (see fix 1)
guest-daemon/savant-core/: go vet / go test -count=1 (ok 13.9s) / gofmt
guest-contract: scripts/release/build-guest.sh --contract-only PASS
release tooling: py_compile PASS; unittest discover 10 tests OK;
           runtime-build/validate-lock.py ok; bash -n runtime-build PASS
repo:      bun run lint:md PASS; git diff --check PASS
```

Stage-1 corrections this pass (same class as the phase.go boundary fix):

1. `provision_key_test.go` referenced `provisionSentinel` from the
   windows-only `provision_key.go`, breaking Linux-target vet/test
   compilation (`undefined: provisionSentinel`) — a regression from the
   FID-2026-0917-002 provisioning landings. Fixed by extracting the const
   into platform-neutral `app/provision_contract.go`; both targets green.
2. `scripts/release/build-guest.sh` and `guest-image/build.sh` executed
   `check-snapshot-lock.sh` (and `build.sh`) directly while those scripts
   are tracked 100644; Windows checkouts cannot carry exec bits, so
   remote CI run #91's Guest-contract job died instantly with **exit 126**
   on the direct exec — invisible in Git Bash, which does not enforce the
   bit (the recorded MSYS lesson, inverted). Fixed by explicit `bash`
   invocation at the three call sites; `--contract-only` re-verified green.

Remote CI evidence (read-only API, 2026-09-27): run #91 (`ddb1097`,
2026-09-20) concluded failure — the "Windows launcher" job is green; the
ubuntu "Launcher" job failed at "Test launcher" (`go test -race ./...`,
instant compile failure = defect 1) and "Guest contract" failed at exit
126 (defect 2). Both fixes are in the working tree; pushing the 2 unpushed
commits plus these fixes is the operator's (G1/G3), and the CI rerun is
the proof. If the rerun surfaces the suspected watchdog goroutine race
(the suite has never run under `-race` locally — no gcc), that becomes
FID-2026-0916-001 work, not a surprise.

Requirement reconciliation: the per-FID table's 14 assignments hold.
Three table FIDs were closed and archived on 2026-09-27 (0912-002,
0914-003, 0915-006 — the FID record reconciliation session); their
remaining obligations map to owners already named in this plan:
0914-003's permissions + automated-reset follow-ups = T1.1/T1.2;
0915-006's generation freshness = stage-4 acceptance and builder
validation = stage-3 (which also owns the recorded `build.sh`
unknown-flag defect); 0912-002's missing current-image
restart/clean-exit proof = stage-4 acceptance. D6 remains a proposal
ledger.

Remaining stage-1 items (owned, visible, not deferred): native Linux/race
parity (CI after the push), remote CI green confirmation, and the
untracked-work + unpushed-commit dispositions (operator call). Open
decisions unchanged (four above). Stage 2 (launcher protection) remains
next per the approved sequence.

Status update (later 2026-09-27, same day): the operator ratified
incorporation of the preserved work and directed "all work should be
pushed in full" — everything landed and pushed through `8f8874b`; CI
runs 36351604844 (`82e1ded`) and 36352329369 (`8f8874b`) are green on
all three jobs including the race suite (the suspected watchdog race was
confirmed there and fixed — FID-2026-0916-001). A rulings pass settled
all four open decisions the same day: 0915-002 mislabel corrections,
the `build.sh` fail-closed CLI, T1.1 implemented under the per-path
policy, and the historical hygiene trio closed as resolved (SCOPE.md).

### Verification policy

Use the configured launcher build/vet/test/format gates and repository Markdown
gate. Run Linux CI/race parity in a suitable toolchain environment before
claiming CI equivalence. Daemon checks need the Linux build/vet/test/format
suite; existing tests are not substitutes for the stage-7 capability proofs.
Run the release-helper and `scripts/release/build-guest.sh --contract-only`
gates before factory/release changes proceed, then perform each child FID's
image and runtime gates against recorded source/binary/image identities.

A blocked gate stays visible with an owner and next action. Only the operator
may change acceptance or defer approved work. Historical proof is reusable
only with explicit relevance to the artifact being accepted.

## Resolution

- **Closed Date:** — (closes only after every approved track passes its gates)
- **Archived:** —

## Lessons Learned

(written at closure)
