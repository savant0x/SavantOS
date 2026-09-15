# FID: Phase 3 — Savant agent control plane (EIS + AT-SPI2)

**Filename:** `FID-2026-0914-001-agent-control-plane.md`
**ID:** FID-2026-0914-001
**Severity:** high
**Status:** analyzed
**Created:** 2026-09-14 00:56
**YAGNI-Compliance:** Pending
**Parent:** FID-2026-0912-001 (first-party OS pivot — Phase 1 converged; Phase 2 landed under FID-2026-0912-002/FID-2026-0913-001)

---

## Summary

Phase 3 of the approved pivot (FID-2026-0912-001, workstream 3): embed the
Savant agent as a first-class peer inside the Plasma guest — Savant Core as a
crash-resilient systemd user daemon, the input adapter (EIS primary with a
portal fallback), AT-SPI2-first interaction with a ScreenShot2 vision
fallback, the operator's safety law implemented as designed in ruling 2, a
Kirigami layer-shell UI, and cursor yielding. This FID materializes the
approved workstream into a tracking record (it was defined in the pivot FID
but never given its own FID — a tracking gap found in the 2026-09-14 folder
audit); the perfection loop below runs when implementation begins.

## Environment

- **OS:** Windows 11 host; Arch Linux guest (Plasma 6.7, Wayland)
- **Language/Runtime:** Go 1.27 (launcher); the agent layer's runtime is a
  Phase 3 design decision (EIS/AT-SPI2 client bindings chosen by evidence)
- **Commit/State:** working tree 2026-09-14 — Phase 2/identity bake present
  (uncommitted); the dev guest carries the deployed identity files +
  kvantum/papirus installs

## Detailed Description

### Scope (from FID-2026-0912-001, workstream 3 — recorded verbatim)

- Savant Core as a systemd user daemon; crash-resilient.
- Input adapter: EIS primary → portal fallback.
- AT-SPI2-first interaction with a ScreenShot2 vision fallback.
- Safety law implemented as designed in operator ruling 2 (recorded
  verbatim in FID-2026-0912-001): tiered approvals (read = silent, project
  writes = logged, destructive/network/shell = out-of-band human approval);
  un-hideable audit overlay; kill switch severing the agent's input channel;
  agent confined to an unprivileged identity that cannot modify its own
  permissions.
- Kirigami layer-shell UI.
- Cursor yielding.

### Verified premises (from FID-2026-0912-001's lessons)

- The KWin EIS interface is REAL (verified in-guest); the Deep Research
  brief's state-destruction premise was not. Rule: verify an external
  report's load-bearing claims against the live system before adopting its
  red-team.

### Exit criteria (from FID-2026-0912-001's verification section)

Live demo in the dev guest: the agent injects input via EIS, reads the
AT-SPI2 tree, and the kill switch severs it.

## Impact Assessment

### Affected Components

- New: the agent layer (daemon + input adapter + AT-SPI2 client + Kirigami
  UI) — a new in-tree component; location decided in Phase 3 design
- Guest: systemd user units for the daemon

### Risk Level

- [x] High: the Savant agent platform is the product's core roadmap item
      (M2+); nothing ships without the safety law implemented as designed

## Proposed Solution

### Approach

Design phase first: runtime/toolchain selection by evidence (EIS client
bindings, AT-SPI2 bindings), safety-law architecture, daemon lifecycle —
each decision documented in this FID's loops before code. Then
implementation as a contract-gated workstream, direct-pushed per the 3c flow.

### Steps

1. This FID's perfection loop converges (design decisions documented).
2. Daemon + input adapter + AT-SPI2 client land contract-gated.
3. Safety law (ruling 2) implemented and demonstrated.
4. Exit demo: EIS input injection + AT-SPI2 tree read + kill-switch sever,
   observed in the dev guest.

### Verification

- Repo gates (build/vet/test/fmt) + the live demo in the dev guest.
- The safety law's kill switch demonstrated severing the agent's input
  channel mid-operation.

## Verification Gates

> Declared now; run when implementation begins (a gate that was not run is a
> gate that failed).

- gate: build (cd app && go build ./...) — plus the agent layer's own build
- gate: vet / test / fmt per protocol.config.yaml
- gate: docs (markdownlint on changed *.md)
- gate: live demo (EIS injection + AT-SPI2 read + kill-switch sever) in the
  dev guest — pasted into this FID as evidence

## Perfection Loop

### Loop 1 — Design convergence (2026-09-14, folder-audit pass)

- **RED:** Open design questions cataloged: (a) agent runtime/toolchain
  (EIS client bindings — the libei ecosystem; chosen by a
  binding-availability survey); (b) the agent layer's in-tree location;
  (c) the safety law's kill-switch wiring (how the input channel severs);
  (d) AT-SPI2 client bindings; (e) daemon delivery through the payload
  contract.
- **GREEN:** Each converted into a named exit criterion or answered by
  precedent: (b) in-tree, per FID-2026-0912-001 missed-question-4; (e) the
  payload contract F1–F7 already covers file delivery — the agent rides it;
  (a)/(c)/(d) named Phase-3 design deliverables (the binding survey is the
  first implementation step).
- **AUDIT:** Premises cited from FID-2026-0912-001's verified lessons (EIS
  real in-guest) and the F1–F7 contract (verified against app/fetch.go
  there).
- **ADVERSARIAL:** "The design loop cannot converge without the binding
  survey" — answered by the FID-2026-0912-001 Loop-3 precedent: unknowns
  become named exit criteria, not open questions.
- **CHANGE DELTA:** ~20%.
- **Convergence declared:** status → analyzed; implementation begins after
  Phase 2's closure evidence lands.

## Resolution

- **Closed Date:** —
- **Fix Description:** —
- **Tests Added:** —
- **Verification Evidence:** —
- **Archived:** —

## Lessons Learned

(written at closure)