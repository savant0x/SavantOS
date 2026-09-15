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
| 1.1 | `/usr` + `/usr/share` mode-0777 normalization in the builder + assemble.sh mode assertion | 0914-003 Loop 3 finding | one-line root cause class: tar/mke2fs inherited permissive modes; assert 0755 in the same gate that guards content |
| 1.2 | Launcher headless `-fresh` path (`-yes` flag or probe bypass) so automation can reset disks | 0914-003 Loop 3 finding | GUI dialog `confirmResetBackup` unreachable in headless runs; consumer = vmtest/smoke automation |
| 1.3 | Dual-build re-run on the committed tree (validates 1.1 + proves determinism survives the commit boundary) | 0914-002 gates | produces the T2 delta-baseline image |

**Exit:** shipped images cannot be world-writable; automation can reset a
disk; fresh baseline image for delta work.

### T2 — Deltas & release cycle (0914-002 steps 5 + exit criterion)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 2.1 | casync-only delta design build-out over the F1–F7 contract: chunk store + seed (current rootfs on the data disk) + streamed index; host still authenticates full-image SHA256SUMS as the ONLY trust root (delta = optimization, never a second trust anchor) | 0914-002 Loop 2/3 (D2 ruling: design of record) | zstd-split documented fallback |
| 2.2 | Large-asset range re-verification on `rootfs.ext4.zst` before any consumer ships | 0914-002 Loop 3 ADVERSARIAL | extends the confirmed small-asset result |
| 2.3 | Release cycle dry run: prepare → pin → publish → smoke on a fresh data dir (first Plasma-based signed release) | 0914-002 exit criterion | needs T1.3 baseline |
| 2.4 | **Operator decision (named, not silent):** sysupdate guest-pull vs host-contract | 0914-002 Loop 2 RED (d) | F1–F7 collision documented; no code until ruled |

**Exit:** update downloads shrink from ~2 GB to <100 MB; the exit criterion
of 0914-002 is discharged.

### T3 — Launcher probes (0914-002 step 3; rulings D1: all three now)

| # | Item | Source | Notes |
|---|------|--------|-------|
| 3.1 | Metered-pause: `GetNetworkConnectivityHint` + pause semantics in `downloadVerifiedWithOptions`/`ensureRuntime`/`ensureGuest` + settings escape hatch | 0914-002 Loop 2 GREEN (3a) | needs its own micro-contract (pause what, show what, override how) before code — named in the FID |
| 3.2 | Vulkan 1.3 detection: adapter enumeration + version assertion + probe-record shape, no graphics deps (DXGI/D3DKMT-style native work) | 0914-002 Loop 2 GREEN (3b) | feeds render-probe reasons + guest compositing flag |
| 3.3 | AVX2 probe via `GetLogicalProcessorInformationEx` CPID bits; lands feeding the probe record/diagnostics; VLM-flag consumer arrives with T4 (named, not silent, wiring gap) | 0914-002 Loop 2 GREEN (3c) | order 3a → 3b → 3c is the D1 ruling |

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
4. **Mode policy** (T1.1): flat 0755 on /usr tree vs per-path table.

## Verification Gates

- gate: docs (markdownlint) — run on this file at commit
- gate: each child FID's own declared gates (already declared there)
- gate: plan re-run through its loop at every track closure

## Resolution

- **Closed Date:** — (governing plan; closes when T4's demo lands)
- **Archived:** —

## Lessons Learned

(written at closure)
