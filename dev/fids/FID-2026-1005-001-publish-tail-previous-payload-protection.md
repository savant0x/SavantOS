# FID: Publish tail must not destroy the previous payload before its replacement exists

**Filename:** `FID-2026-1005-001-publish-tail-previous-payload-protection.md`
**ID:** FID-2026-1005-001
**Severity:** high
**Status:** fixed — implementation committed 2026-10-05 as `a5aa557`
(`feat(builder): publish by verified rename swap`, pushed to origin/main
with the governance/records slices); closure owes only the
operator-scheduled real-build swap proof
**Created:** 2026-10-05 17:52
**YAGNI-Compliance:** Verified

---

## Summary

The builder's publish tail destroys the currently published payload
(`guest-image/out/contract`) with `rm -rf` **before** the replacement payload
has finished being assembled, verified, or copied. The 2026-09-29 N+1 build
proved the gap live: `out/contract` was reduced to a husk by the busy-handle
rm, its replacement never published, and the previously published release was
lost (survivors were salvaged manually and re-hashed by the 2026-10-03
session). The 2026-09-28 hardening protects only the NEW payload
(`trap - EXIT` at `guest-image/build.sh:322`, 6x10 s retries, `build-a/contract`
kept intact) — the asymmetry named as a follow-up in FID-2026-0914-002:707-712
and recorded in SCOPE.md. This FID converges the design: complete the entire
payload assembly on `build-a/contract` first, then publish with an
atomic rename swap so the previous payload is never destructible mid-flight,
and extract the tail into a host-testable script with a scripted proof suite.

## Environment

- **OS:** Windows 11 host; build scripts run under Git Bash (MSYS)
- **Language/Runtime:** Bash (the tail is host-side shell; no Go involved)
- **Tool Versions:** bash + GNU coreutils via Git Bash — with a **broken
  coreutils install on this host: `head` and `find` are BOTH absent**
  (`command -v head` → exit 1; `/usr/bin/find` does not exist and `find`
  resolves to Windows `find.exe`, which rejects POSIX syntax with
  `FIND: Parameter format not correct`, exit 2 — both measured 2026-10-05).
  `mv`, `stat`, `sort`, `awk`, `tail`, `df`, `sha256sum` are present.
- **Commit/State:** `main` @ `9c640b5`, ahead 6 of `origin/main` unpushed;
  working tree carries the uncommitted G1-reconciliation and snapshot-lock
  changes of this session.

## Detailed Description

### Problem

Publish order in `guest-image/build.sh` (493 lines, read 0-EOF) is destroy
first, assemble later:

1. `build.sh:322` — `trap - EXIT` (gate green; `build-a` survives failures).
2. `build.sh:329-347` — retry loop runs `rm -rf "$out/contract"` (line 331)
   up to 6 x 10 s. This is the **published payload**, and `rm -rf` is
   destructive in flight: a handle held mid-deletion leaves a husk (the
   2026-09-29 shape).
3. Only THEN: delta-prev selection (`build.sh:358`), delta-finalize
   (`build.sh:367`), publish copy `cp -r build-a/contract "$out/contract"`
   (`build.sh:381`), first SHA256SUMS (`build.sh:386-390`), runtime archive
   staging (`build.sh:456`), SHA256SUMS re-emission (`build.sh:459-463`),
   delta entries + sums digest (`build.sh:470-480`), `release-base.json`
   (`build.sh:483-490`).

Every step between line 331 and line 490 can fail (delta-finalize rc!=3,
runtime digest mismatch, disk, interruption), and each such failure leaves
the published payload **destroyed** with only the unpublished replacement
in `build-a/contract`.

### Expected Behavior

- The previous payload stays intact and published until the replacement is
  fully assembled (runtime archive, SHA256SUMS incl. delta entries, digest)
  and self-verified.
- Publication is a rename, never a deletion: no primitive in the publish
  path can partially destroy the previous payload (no husk case).
- Every failure leaves a documented, recoverable state: previous payload
  still published (failure before the swap), or both generations present
  with a one-command recovery (failure inside the swap window).

### Root Cause

Hardening asymmetry: the 2026-09-28 fix (trap release + retry + FATAL with
`build-a` intact) was designed around protecting the NEW payload and working
around the busy handle, while treating destruction of the PREVIOUS payload as
the unguarded first step of publishing. `rm -rf` + `cp -r` was chosen over
assemble-then-rename; the destructive step therefore precedes every
verification step, and its failure mode (partial deletion) is the incident.

### Evidence

Incident record (FID-2026-0914-002:703-712):

```text
The 2026-09-29 N+1 build's publish tail hit the known busy-handle FATAL
(6x10 s). `out/contract` — the PUBLISHED N payload — was rm'd down to a
husk before the handle blocked: the previous release was destroyed while
its replacement never published. ... The hardened tail preserved the new
payload as designed — but nothing guards the PREVIOUS payload during the
publish rm. That asymmetry is a named follow-up for the publish tail.
```

Same event, 2026-09-29 session summary:

```text
The publish tail FATALed on the busy out/contract handle: the published N
payload was rm'd down to a husk before the handle blocked. Per the hardened
tail, the gate-passed payload survived intact in build-a/contract.
```

The current FATAL message itself documents the husk case as normal
(`guest-image/build.sh:341-345`):

```text
Publish by hand once the handle releases, either as
  rm -rf out/contract && cp -r build-a/contract out/contract
or, if only an empty husk remains, into it:
  cp -r build-a/contract/. out/contract/
```

Busy-handle occurrences of the rm: 2026-09-19, 2026-09-28, 2026-09-29
(`guest-image/RUNBOOK.md` failure-modes list) — this is a recurring trigger,
not a one-off.

Host constraint measured 2026-10-05 (shapes the design below): the tail's
test suite must run on THIS host, which lacks `head` and `find`:

```text
$ command -v head; echo $?
1
$ ls /usr/bin/find; find guest-image -maxdepth 1 -name out; echo $?
ls: cannot access '/usr/bin/find': No such file or directory
FIND: Parameter format not correct
2
$ stat -c '%d %n' guest-image/out guest-image/build-a
3495259774 guest-image/out
3495259774 guest-image/build-a        # same device — rename is available
```

## Impact Assessment

### Affected Components

- `guest-image/build.sh` — publish tail (lines 322-490) and its ordering
- `guest-image/out/` — the published release base served to launchers
- `guest-image/RUNBOOK.md` — publish-tail failure modes and manual-publish
  procedure (husk instructions become obsolete)
- New: `guest-image/publish-tail.sh`, `scripts/dev/test-publish-tail.sh`

### Risk Level

- [ ] Critical: System crash, data loss, or security vulnerability
- [x] High: Major feature broken, no workaround
- [ ] Medium: Feature degraded, workaround exists
- [ ] Low: Minor issue, cosmetic, or edge case

High (matches the records in SCOPE.md and the 2026-10-03 session): the
published release is destroyed with a 2-hour rebuild as the only recovery;
the incident already occurred once with survivors salvaged by hand. Not
Critical: no trust-boundary breach — the launcher fails closed on SHA256SUMS,
so a partial payload cannot be consumed silently; the loss is availability of
the published artifact, not integrity of what clients verify.

## Proposed Solution

### Approach

**Assemble fully, then rename-swap.** Complete 100% of payload assembly on
`build-a/contract` before touching `out/contract`, self-check the staged
payload, then publish via two renames with the previous payload parked as
`out/contract.prev` until the new one is verified in place. Extract the whole
tail into `guest-image/publish-tail.sh` so a scripted suite can prove every
failure point without a 2-hour build.

Design decisions and their reasoning:

1. **Reorder before rewriting.** Move runtime staging, both SHA256SUMS
   emissions, and the delta-entries block to run on `build-a/contract` ahead
   of any `out/contract` mutation. These steps never needed `out/contract`
   — they were sequenced after the copy only because the copy came first.
   After the reorder, the destructive window contains nothing but renames.
   *(Rejected: keeping the order and adding a backup copy — an ~8 GiB copy
   contradicts the operator's rotate-to-one disk mandate (2026-09-18) and
   still leaves `rm -rf` destructible mid-flight.)*
2. **Rename, never rm.** `mv out/contract out/contract.prev` is `rename(2)`:
   atomic, all-or-nothing — a busy handle makes it fail cleanly, never
   partially. The husk case becomes unrepresentable. *(Rejected: symlink
   indirection for atomic replace — NTFS symlinks need privilege/dev mode
   and add a new trust surface for the served path.)*
3. **Self-check BEFORE the old payload moves.** Required-files presence plus
   `sha256sum -c SHA256SUMS` inside the staged payload must pass first, so a
   broken replacement never costs the live one its slot.
4. **`out/contract.prev` as the park name — deliberately.** The rotation
   guard (`build.sh:254`) and delta-prev selection (`build.sh:358`) both glob
   `-name 'contract-*'`; `contract.prev` does not match that pattern
   (`contract.` vs `contract-`), so parked-state leftovers can never be
   pruned by rotation or mistaken for the delta chain link. Verified against
   both globs during audit.
5. **Same-device precondition.** GNU `mv` silently degrades to copy+rm
   across filesystems (which would reintroduce a destructive window). A
   `stat -c %d` equality check on `out` and `build-a` fails closed before
   the swap if they differ. Measured same device on this host (evidence
   above); both dirs live under `guest-image/` by construction.
6. **Stale `out/contract.prev` fails closed.** Its presence means a prior
   run died inside the swap window — unresolved evidence. The tail FATALs
   with explicit resolution options (restore it, or delete it to proceed)
   rather than silently discarding it on the next run.
7. **Extraction for testability.** The tail as inline code can only be
   verified by a full build. As `guest-image/publish-tail.sh` it is driven
   directly by `scripts/dev/test-publish-tail.sh` (the CI `windows-launcher`
   job already globs `scripts/dev/test-*.sh` — no workflow edit needed).
   Production caller: `build.sh` invokes it after the gate (Law 4: grep for
   the call site at implementation time; zero callers = reject the change).
8. **Bash globs + `sort` + `awk` only — no `find`, no `head`.** Required so
   the tail and its suite run on this host (both tools measured missing
   above) and so the delta-prev selection (today's `find | head` at
   `build.sh:358`, which also breaks under `set -o pipefail` on this host)
   becomes environment-proof as a designed property, not a patch.
9. **Failure hooks can only abort.** `PT_FAIL_AT` (used by the test suite)
   is honored only at stage boundaries and can only terminate the run —
   there is no hook position that skips a verification, so a test-only knob
   cannot weaken production behavior. Fail-closed by construction.
10. **`release-base.json` emitted last, after the swap and post-swap
    verification**, so it never points at a payload that is not published.

### Steps

1. **Reorder `build.sh`:** move runtime-archive staging, the SHA256SUMS
   emissions (with and without runtime), and the delta-entries block onto
   `build-a/contract` before line 322's `trap - EXIT`; compute the sums
   digest there.
2. **Extract `guest-image/publish-tail.sh`** (args: `out` dir, `build-a`
   dir, release name, version; `set -euo pipefail` inside), containing, in
   order: delta-prev selection (glob, newest `contract-*` sibling) — as a
   post-assembly informational step only, since delta-finalize now runs
   before it in build.sh — through swap and cleanup:
   a. preconditions: same device (`stat -c %d`), no stale
   `out/contract.prev`, `build-a/contract` present;
   b. staged-payload self-check: required files + `sha256sum -c SHA256SUMS`;
   c. `mv out/contract out/contract.prev` inside the existing 6 x 10 s retry
   cadence (skipped when `out/contract` does not yet exist — first publish);
   d. `mv build-a/contract out/contract`;
   e. post-swap verification: required files + `sha256sum -c` re-run in the
   published dir;
   f. `rm -rf out/contract.prev`, emit `release-base.json`, print the
   `GATE GREEN` line.
   Failure FATALs state exactly which generation exists where and the
   one-command recovery for that state (restore old: `mv out/contract.prev
   out/contract`; finish new: `mv` from the named staging dir).
3. **Wire `build.sh` to call `publish-tail.sh`** replacing inline lines
   322-490's tail; keep `trap - EXIT` semantics (gate spoken) and the
   build-a/build-b cleanup after a successful swap.
4. **Add `scripts/dev/test-publish-tail.sh`** (no VM, no Docker, no
   network; temp dirs with small fake payloads) covering: happy swap;
   staged self-check rejects a corrupt payload with previous untouched;
   pre-swap step failure leaves previous byte-identical; between-rename
   state recovers per the printed command; busy-`mv` retry succeeds within
   cadence and FATALs with previous still published beyond it; stale
   `contract.prev` refuses; first publish (no previous) works; parked name
   proven not to match `contract-*` globs used by rotation/delta; hook can
   abort but cannot skip post-swap verification; `release-base.json` exists
   only after a verified swap.
5. **Docs:** RUNBOOK publish-tail failure modes (husk bullet retired,
   rename semantics + new recovery), post-run checklist unchanged in
   substance; CHANGELOG entry at implementation closure; update the
   named-follow-up line in FID-2026-0914-002 and the SCOPE.md item when
   this FID closes.

### Verification

Declared gates (a gate not run is a gate failed):

```markdown
- gate: shell syntax — bash -n guest-image/build.sh guest-image/publish-tail.sh scripts/dev/test-publish-tail.sh
- gate: scripted proofs — bash scripts/dev/test-publish-tail.sh (all scenarios pass, exit 0)
- gate: contract — bash scripts/release/build-guest.sh --contract-only (exit 0)
- gate: docs (markdownlint on changed *.md) — bun run lint:md
- gate: call-graph — grep -n "publish-tail.sh" guest-image/build.sh shows the production call site (Law 4)
- gate: real-build proof (operator-scheduled, evidence at implementation): next real build logs the swap
  sequence, published SHA256SUMS re-verifies, no out/contract.prev residue, published rootfs digest == gate digest
```

The scripted suite is the primary proof: it exercises every failure point of
the swap in seconds, which the old inline tail could never do.

## Verification Gates

> Mandatory once status flips to `fixed`/`verified`. Declared above; at
> `converged` they are the contract implementation must satisfy.

```markdown
- gate: bash -n guest-image/build.sh guest-image/publish-tail.sh scripts/dev/test-publish-tail.sh
- gate: bash scripts/dev/test-publish-tail.sh — exit 0, all scenarios
- gate: bash scripts/release/build-guest.sh --contract-only — exit 0
- gate: bun run lint:md — exit 0
- gate: grep -n "publish-tail.sh" guest-image/build.sh — production call site present
```

> A gate that was not run is a gate that failed. Paste exact output under
> Resolution at closure.

## Perfection Loop

### Loop 1 — RED → GREEN → AUDIT → ADVERSARIAL (design, 2026-10-05)

- **RED:** Ordering flaw cataloged with line numbers (destroy at
  `build.sh:331` precedes assembly at 367-490); incident evidence from
  FID-2026-0914-002:703-712, the 2026-09-29 summary, and RUNBOOK failure
  modes (three busy-handle occurrences); host environment probe (head and
  find both missing; same-device stat probe).
- **GREEN:** Design v1: reorder assembly before mutation; rename-swap with
  `contract.prev` park; extract to `publish-tail.sh` + scripted suite;
  globs/sort/awk only; hooks abort-only.
- **AUDIT:** Re-read `build.sh` 0-EOF against every cited line (numbers
  re-grepped: 322, 329-347, 358, 367, 381, 456, 483); both `contract-*`
  glob sites checked against the park name (`contract.prev` does not match
  `contract-`); GNU `mv` cross-device fallback identified as a
  reintroduced destructive window → same-device precondition added;
  self-check ordered BEFORE the old payload moves; `release-base.json`
  moved post-swap.
- **ADVERSARIAL:** Challenges and answers: (a) "the swap window still has
  no payload at `out/contract`" — true for one rename, bounded by
  rename(2), with printed recovery for both states; strictly narrower than
  today's multi-minute destructive window ending in possible husk.
  (b) "a stale park blocks the next build" — intended: fail-closed forces
  the operator to resolve prior-failure evidence (decision 6). (c) "test
  hooks weaken production" — impossible by construction (decision 9).
  (d) "first publish has no previous payload" — conditional rename.
  (e) "delta chain link vs park confusion" — glob exclusion verified.
- **CHANGE DELTA:** ~35% of draft text rewritten in audit (heuristic,
  markdown; within the ~10%-per-pass intent across the passes below).

### Loop 2 — self-correction (same session)

- **RED:** (1) The extraction step's draft still placed delta-prev
  selection inside the new script while delta-finalize runs earlier in
  build.sh — order confusion; (2) host finding: `find` absence means
  `build.sh:358` dies under `pipefail` on this host and the rotation guard
  at `build.sh:254` silently no-ops (process substitution) — adjacent
  same-class damage that the design must not replicate; (3) no explicit
  first-publish (absent `out/contract`) behavior.
- **GREEN:** (1) delta-finalize stays in build.sh pre-swap; the extracted
  tail owns swap/verify/cleanup only (plus informational prev reporting);
  (2) mandate globs/sort/awk in the tail and suite, and record the
  `build.sh:254`/`358` host breakage in SCOPE.md as a separate
  `[OPEN-OUT-OF-SCOPE]` item (Law 2 — not absorbed here); (3) conditional
  rename documented and given a test scenario.
- **AUDIT:** Suite scenario list re-derived from the failure states in
  decisions 3-6; every state has exactly one scenario.
- **ADVERSARIAL:** "Is scenario coverage self-claimed?" — no: scenario
  names are mapped 1:1 to the FSM states in Step 2's a-f, and the suite
  exit code is the gate.
- **CHANGE DELTA:** ~8% (heuristic).

### Loop 3 — final convergence

- **RED:** Residual risks: real-build swap proof cannot run inside a
  design-only task (needs a 2-hour operator-scheduled build); RUNBOOK
  rewrite deferred to implementation; `build.sh:254`/`358` host breakage
  parked as an open item, not fixed here.
- **GREEN:** All three recorded as explicit implementation-time or
  out-of-scope items — no silent deferral (Step-Level Anti-Deferral: none
  of these is this FID's step; they are named elsewhere).
- **AUDIT:** Final pass re-checked every `file:line` citation against the
  tree (grep output pasted in Evidence); template fields complete; status
  semantics correct — `converged` means zero code written (Ground-Truth
  rule: verified, no `publish-tail.sh` exists yet).
- **ADVERSARIAL:** "Would closing on this state be honest?" — closure is
  correctly withheld: no implementation, no gate output. `converged` is
  the accurate status.
- **CHANGE DELTA:** <2% (heuristic) — converged.

### Loop 4 — implementation pass (2026-10-05, operator-approved)

Operator ruling: "run perfection loop and approve code" → the loop ran on
this document before any code, then the five steps were implemented.

- **RED:** Every citation re-verified against the tree before coding
  (`git diff` empty on `build.sh`; lines 322/329-347/358/367/381/456/483
  re-grepped). One design gap found during the pass: the delta-entries
  block's own `find rootfs.castr … | xargs` (old line ~474) would die
  under `pipefail` on this host exactly like old line 358 — decision 8
  had to cover it too, not just the two named sites.
- **GREEN:** The five steps implemented: reorder (assembly completes on
  `build-a/contract` before anything touches `out/contract`),
  `guest-image/publish-tail.sh` (163 lines: preconditions → self-check →
  park rename with 6×10 s retry → install rename → re-verify → cleanup →
  `release-base.json` → GATE GREEN), `build.sh` wiring at line 489,
  glob-only delta-prev selection (line 347) and glob-only chunk
  enumeration (line 472), `scripts/dev/test-publish-tail.sh` (180 lines,
  11 scenarios), RUNBOOK rewrite, contract gate now `bash -n`s the new
  script.
- **AUDIT (double, tool output):** `bash -n` on all four scripts exit 0;
  suite **42 passed, 0 failed, exit 0** — every FSM state: refusal before
  the swap with previous untouched, between-rename recovery via the
  printed command, busy retry and exhaustion with previous STILL
  PUBLISHED, stale park refused, first publish, park invisible to
  `contract-*` globs, unknown hook rejected, release-base only after a
  verified swap; `build-guest.sh --contract-only` exit 0;
  `bun run lint:md` exit 0; call-graph `grep -n "publish-tail.sh"
  guest-image/build.sh` → line 489; grep for `rm -rf "$out/contract"`,
  `cp -r build-a`, `cd "$out/contract"` in `build.sh` → **zero matches**
  (the destructive path is gone, not merely reordered).
- **ADVERSARIAL:** "Suite passed first run — is it testing the real
  script?" It drives `guest-image/publish-tail.sh` directly with real
  renames and real `sha256sum -c`; injections can only abort and unknown
  values fail closed (scenario 10). "Design promised recovery commands in
  FATALs" — asserted by scenario 4 (state) and scenario 6 (STILL
  PUBLISHED); the install-failure message carries both `mv` commands.
  "Cross-device precondition unproven" — genuinely out of reach on a
  single-filesystem host; NEEDS-REVIEW recorded below, static presence
  proven (scenario 11). "Rotation guard still uses find" — true, still
  open as its own SCOPE.md item; outside this FID's approved scope.
- **CHANGE DELTA:** ~40% of the loop/evidence sections rewritten
  (heuristic, markdown); the design sections are unchanged — the
  implementation followed the converged design with one decision-8
  extension (the delta-entries `find`).

### Missed Questions

1. *What serves `out/contract` during the rename window?* Loopback manual
   serving only (release base for `-release <url>`); a request during the
   sub-millisecond window errors — acceptable, and strictly better than
   today's minutes-long partial-deletion window.
2. *Does delta-finalize rc=3 (non-delta fallback) still work?* Yes — it
   mutates `build-a/contract` before the swap, exactly as today; the swap
   publishes whatever passed self-check.
3. *What if the build dies after `rm -rf out/contract.prev` but before
   `release-base.json`?* Published payload is complete and verified
   (sums re-checked); only the convenience pointer is stale — regenerate
   with the printed sums digest (documented in RUNBOOK).
4. *Does Docker's `/work` bind affect renames?* The tail runs host-side
   after containers exit; the historical busy handles came from the
   sharing layer lingering — rename fails the same way rm did, covered by
   the identical retry cadence, but without destructive partials.
5. *Rotation mandate (keep one)?* Swap adds zero copies (all renames);
   `contract.prev` is removed on success; disk profile unchanged.
6. *Who calls the new script?* `guest-image/build.sh` (production) and
   `scripts/dev/test-publish-tail.sh` (proof) — both greppable; Law 4 gate
   declared above.
7. *Does anything downstream parse `out/` names?* The launcher consumes
   served `SHA256SUMS`/manifest contents, not directory names; `contract.*`
   is excluded from the two globs that parse `out/` names (verified).
8. *Concurrency?* Single-operator sequential builds (pre-existing
   assumption, unchanged); stale-park FATAL guards the one cross-run state.
9. *What about `out/release-base.json` during failure states?* Left
   untouched on failure (still points at the still-published previous
   payload — correct); updated only post-swap.
10. *Can the suite run in CI?* Yes: the `windows-launcher` job globs
    `scripts/dev/test-*.sh`; suite must be head/find-free (it is, by
    decision 8) and launch no VM (it doesn't).
11. *Is `stat -c %d` portable to the Linux side?* GNU stat both sides; on
    a Linux release runner the same command works — fail-closed if not
    (errexit).
12. *Does reordering change any artifact bytes?* No — same operations,
    different order; the dual-build gate still gates the inputs, and
    self-check re-verifies the outputs before publish.

### Implementation Evidence (REQUIRED for `closed`)

- [ ] **Commit SHA:** not set — the staging plan is deliberately untouched
      (operator's instruction this pass); G2 makes closure impossible
      until the work is committed
- [x] **File:line ranges:** `guest-image/build.sh` (490 lines): reorder
      comment 323, glob delta-prev 340-351, assembly on `build-a/contract`
      380/452/469, glob chunk enumeration 472, production call
      `bash "$here/publish-tail.sh" …` 489; `guest-image/publish-tail.sh`
      (163 lines, new); `scripts/dev/test-publish-tail.sh` (180 lines,
      new); `scripts/release/build-guest.sh` `bash -n` list extended;
      `guest-image/RUNBOOK.md` failure modes + green-run log rewritten
- [x] **Gate output:** `bash -n` (4 scripts) exit 0; suite `RESULT: 42
      passed, 0 failed` exit 0; `build-guest.sh --contract-only` exit 0
      (snapshot-lock OK + savant-core vet/test ok); `bun run lint:md`
      exit 0
- [x] **Reproducibility:** grep `publish-tail.sh` → `build.sh:489`;
      grep `PT_FAIL_AT` → publish-tail.sh + suite; suite reruns green
- [x] **Step statuses:** all five Proposed Solution steps `implemented`
      (no deferrals, no skips; the real-build swap proof is this FID's
      declared *closure* gate, not a step)

### Code Verification Evidence

- [x] Files referenced in Affected Components exist — `build.sh` and
      `RUNBOOK.md` re-read 0-EOF before editing; both new files verified
      present with their declared line counts
- [x] Implementation matches the Proposed Solution (Loop 4 AUDIT: the
      destructive primitives are grep-absent, not just reordered)
- [x] Gates pasted: syntax exit 0 / suite 42-42 exit 0 / contract exit 0 /
      lint exit 0 (Loop 4)
- [x] Production call-graph: `build.sh:489` calls `publish-tail.sh`; CI
      wires the suite via `.github/workflows/ci.yml:79`
- [x] FID status reflects the actual implementation state (`fixed` —
      code exists, gates pass, committed as `a5aa557` and pushed;
      `closed` withheld per Ground-Truth: no real-build swap proof yet)
- [ ] Live cross-device precondition (NEEDS-REVIEW): a single-filesystem
      host cannot exercise the `stat -c %d` refusal; static presence
      proven by suite scenario 11

## Resolution

- **Closed Date:** not set — status `fixed`; the commit landed (G2:
  `a5aa557`, pushed alongside the governance, records and scratchpad
  slices), so closure requires only (b) the operator-scheduled
  real-build swap proof (next real build:
  swap lines in the log, published SHA256SUMS re-verifies, no
  `out/contract.prev` residue, published rootfs digest == gate digest)
- **Fix Description:** assembly completes on `build-a/contract` before
  the publish path touches `out/contract`; `publish-tail.sh` publishes by
  verified rename swap (park → install → re-verify → cleanup →
  release-base); no `rm -rf` touches any payload in the publish path;
  glob/awk-only tail (host-coreutils-proof); scripted suite proves all
  eleven scenarios
- **Tests Added:** yes — `scripts/dev/test-publish-tail.sh` (42
  assertions), auto-wired into CI by the `scripts/dev/test-*.sh` glob
- **Verification Evidence:** Loop 4 (syntax exit 0 / suite 42-42 exit 0 /
  contract gate exit 0 / lint exit 0 / call-graph `build.sh:489` /
  destructive-path grep zero matches)
- **Archived:** not set — see Closed Date

## Lessons Learned

- Hardening that protects one side of a destructive sequence while leaving
  the other side unguarded converts a crash into data loss: the 2026-09-28
  fix saved the new payload and, by ordering, guaranteed the old one's
  destruction on failure.
- `rm -rf` is a destructive primitive with a partial-failure mode (husk);
  rename has none. Anything that looks like "replace X" should be designed
  as rename, with rm reserved for post-verification cleanup.
- Verification and mutation must be ordered: every check that can fail
  should run before the first step that cannot be undone.
- Shell code that only a full 2-hour build can exercise has no regression
  net — extraction into a drivable script is what makes failure states
  provable.
- Environment assumptions belong in the design: this host is missing
  `head` AND `find`, which silently breaks the rotation guard and fatally
  breaks delta-prev selection — the new code is glob/awk-only so its
  correctness does not depend on a healthy coreutils install.
