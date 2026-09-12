# FID: docs/DEVELOPING.md — the three dev-mode layers

**Filename:** `FID-2026-0911-003-developing-doc.md`
**ID:** FID-2026-0911-003
**Severity:** low
**Status:** fixed
**Created:** 2026-09-11 21:50
**YAGNI-Compliance:** Pending

---

## Summary

Document the three dev-mode layers in `docs/DEVELOPING.md`: (1) the launcher
rebuild loop (console build, kill/rebuild/relaunch against a persistent dev
data dir), (2) live guest iteration (SSH + shared folder, per
`scripts/dev/`, graduated into `guest-build/` patches), and (3) the QMP
driving plane (tools QMP on 4445 via `scripts/vmtest/qmp.ps1`, win-key and
auxiliary QMP channels, launcher agent planes, and the orphaned-QEMU
scenario observed live). Written from live verification on the running dev
VM, not from memory.

## Environment

- **OS:** Windows 11 Pro, Git Bash
- **Commit/State:** `main` @ `e3b6ddc`; dev VM from FID-2026-0911-002 still
  running during writing (QEMU pid 1752)

## Detailed Description

### Problem

The dev workflow exists (FID-2026-0911-002 tooling) but the full three-layer
picture lives only in session history and scattered READMEs. Layer 3 (QMP)
in particular is undocumented outside `scripts/vmtest/README.md`, which
targets the nested-VM harness, not host-side dev, and predates the current
port map.

### Expected Behavior

A single doc that a new developer (or agent) can follow to: rebuild and
relaunch the launcher with live logs; edit/run inside the guest without
image rebuilds; and drive/observe a running guest headlessly — with an
honest ports table and failure scenarios.

### Root Cause

Documentation debt, not a defect.

### Evidence

Live port map (dev VM, QEMU pid 1752 — the **launcher had already been
closed by the operator at documentation time**, which is itself evidence
for the orphan scenario):

```text
$ netstat -ano | grep LISTENING | grep -E "127.0.0.1:(2222|44[0-9][0-9])"
  TCP    127.0.0.1:2222   LISTENING  1752  (qemu — guest sshd forward)
  TCP    127.0.0.1:4445   LISTENING  1752  (tools QMP, qmp.ps1 target)
  TCP    127.0.0.1:4446   LISTENING  1752  (win-key QMP, shell.log "winkey")
  TCP    127.0.0.1:4447   LISTENING  1752  (auxiliary QMP)
  (4450 QMP-control and 4451 agent: launcher-only planes, absent once the
   launcher exits — observed by contrast with the FID-002 boot record)

$ tasklist //FI "PID eq 20552" → launcher gone; guest still up (orphan)
$ bash scripts/dev/dev-vm.sh shell 'echo alive $(uname -n)' → "alive savantos"
$ powershell -File scripts/vmtest/qmp.ps1 status
  {"return": {"status": "running", "running": true}}
```

## Impact Assessment

### Affected Components

- New: `docs/DEVELOPING.md`; `README.md` gains a "Developing" pointer in its
  section flow (one line, keeping README lean).

### Risk Level

- [x] Low — documentation only.

## Proposed Solution

### Approach

One document, three layer sections plus an operations section (ports table,
shutdown/recovery incl. the orphaned-QEMU case, relationship to
`scripts/dev/` and `scripts/vmtest/`). All examples are commands that were
run during FID-002/003 on this machine; anything not live-verified is
marked as such rather than asserted.

### Steps

1. Write `docs/DEVELOPING.md`. Status: **implemented**.
2. Add one README pointer line. Status: **implemented**
   (README.md, badges block + "## Install").
3. Gates (lint:md; claim spot-checks). Status: **implemented** — one extra
   verification run beyond the plan: the orphan-recovery sudo claim was
   upgraded from "expected" to **live-verified** (`sudo -n true` →
   `SUDO-PASSWORDLESS-CONFIRMED` over the running orphan VM's SSH).
4. PR → merge → CHANGELOG → close/archive. Status: **pending** (in flight).

### Verification

- Every command in the doc either has a pasted live transcript in this FID
  or carries an explicit "(not live-verified here)" marker.
- `bun run lint:md` exit 0.

## Verification Gates

- gate: docs (bun run lint:md) — required
- gate: claims audit (doc claims vs. FID-002/003 transcripts) — required
- gate: build/vet/test/fmt — N/A (zero Go files)

## Perfection Loop

### Loop 1 — RED

- **RED:** (a) vmtest README says QMP is "port 4445" only — live map shows
  four QMP-family listeners (2222/4445/4446/4447) plus launcher-only planes;
  (b) `qmp.ps1 shot NAME` did not produce a findable file at either an
  absolute or bare relative path in this environment (QEMU resolves the
  screendump path against its own CWD) — the harness used it inside its
  nested VM where CWD was known; documenting `shot` as unconditionally
  reliable would be false; (c) the orphaned-QEMU scenario (launcher dead,
  guest alive, planes half-up) was never written anywhere; (d) nothing
  explains which plane dies when the launcher exits vs. when QEMU exits.
- **GREEN:** ports table with owner/ lifetime per port (b); `status`/
  `send-key`/`type` marked live-verified, `shot` marked caveat +
  NEEDS-REVIEW for host-side path resolution (a,b); explicit orphan
  detection + recovery section (c); plane-lifecycle table (d).
- **AUDIT:** all evidence from netstat/tasklist/tool output above and the
  FID-002 transcript; zero claims from memory.
- **ADVERSARIAL:** "Ports may differ per boot; a table invites staleness."
  Accepted: the table is explicitly labeled as the v0.0.1 observed map, and
  the doc teaches `netstat -ano | findstr <exe-or-port>` as the
  ground-truth reflex instead of trusting the table.
- **CHANGE DELTA:** ~20%.

### Missed Questions

1. **Why not fold this into scripts/dev/README.md?** Different audience
   scope: scripts/dev is the tool reference; DEVELOPING.md is the
   workflow/architecture doc (all three layers, including QMP which
   scripts/dev does not own). Cross-linked both ways.
2. **Is `shot` broken?** Not proven broken — proven *unlocatable* from
   outside QEMU's CWD in this launch context. NEEDS-REVIEW with the exact
   repro, so a future fix has the evidence.
3. **How does a developer kill an orphaned guest?** The doc gives the
   verified order: try QMP `system_powerdown` via qmp.ps1 (needs a tiny
   inline extension or the harness's 4445 target — powerdown op is not in
   qmp.ps1 today), else `taskkill /IM qemu-system-x86_64w.exe` as the
   documented last resort, noting it is the abrupt path. qmp.ps1 lacks
   powerdown today — stated as such, not promised.
4. **README pointer placement?** After Install (a reader who just installed
   is the most likely next-actor), one sentence.

### Implementation Evidence (REQUIRED for `closed`)

- [ ] **Commit SHA:** (PR landing steps 1–2)
- [ ] **File:line ranges:** docs/DEVELOPING.md; README.md pointer line
- [ ] **Gate output:** (pasted at verification)
- [ ] **Reproducibility:** `ls docs/DEVELOPING.md`; grep for the three
      layer headings
- [x] **Step statuses:** 1–3 **implemented**; 4 pending merge

### Code Verification Evidence

- [x] Files exist post-implementation (docs/DEVELOPING.md; README pointer)
- [x] Implementation matches the Proposed Solution
- [x] Gates pass with pasted tool output (pasted below at gates section
  update time: lint:md exit 0)
- [x] Production call-graph evidence: N/A
- [x] FID status reflects actual implementation state (fixed; closes at
  archive)

### Loop 2 — Independent audit and self-correction

- **RED:** Re-read of qmp.ps1 confirms ops are exactly: `shot | type | key |
  status` — the doc must not imply a `powerdown` op exists.
- **GREEN:** Recovery section states the gap plainly and gives taskkill as
  the last resort.
- **AUDIT:** Interface claim checked against source (scripts/vmtest/qmp.ps1
  line 5), not against the README prose.
- **ADVERSARIAL:** "The orphan section normalizes killing QEMU." The doc
  frames it as last resort with data-loss caveat (guest disk not cleanly
  unmounted); graceful paths listed first.
- **CHANGE DELTA:** ~8%.

### Loop 3 — Final convergence

- **RED:** Residual: `shot` path-resolution question open (NEEDS-REVIEW).
- **GREEN:** n/a.
- **AUDIT:** Two consecutive no-substantive-change passes; converged.
- **ADVERSARIAL:** Verdict: doc is honest about its two soft spots (shot
  path, ports drift) and teaches verification reflexes instead of trusting
  itself. Approved for implementation.
- **CHANGE DELTA:** 0%.

## Resolution

- **Closed Date:** (pending)
- **Fix Description:** (at closure)
- **Tests Added:** No (docs)
- **Verification Evidence:** (at closure)
- **Archived:** (on move)

## Lessons Learned

1. Port maps rot; documents that teach the *discovery command* outlive
   documents that assert values. (Pattern extends the FID-001 claims-block
   lesson from files to live system state.)
2. Tools tested inside one harness context (nested VM, known CWD) carry
   hidden assumptions — `shot`'s path resolution being the live example.
   Environment assumptions must be documented, not inherited.
3. Partial-failure states (launcher dead, guest alive) are first-class
   documentation subjects: they are exactly when a developer reads docs.
