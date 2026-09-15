# FID: Phase 3 Loop 2 — Savant Core daemon design + T4 scaffolding plan

**Filename:** `FID-2026-0915-005-phase3-savant-core-design.md`
**ID:** FID-2026-0915-005
**Severity:** high (Phase 3 implementation of record)
**Status:** converged (design of record; implementation queued)
**Created:** 2026-09-15
**Parent:** FID-2026-0914-001 (Phase 3 — agent control plane), Loop 2
**Master plan:** FID-2026-0915-001 T4.2 (with T4.3/T4.4 sequencing)

---

## Summary

Concrete design for **Savant Core** — the crash-resilient user daemon
that owns agent input (per FID-2026-0915-003), observation, and the
safety law (per FID-2026-0915-004) — plus the exact scaffolding sequence
for T4.2. This FID is the last design blocker before code.

## Process model

**One daemon, three planes, strict fd hygiene:**

- **Input plane** — the EIS context (or portal session fallback). The
  only fds in the daemon that can move a pointer or type.
- **Vision plane** — AT-SPI2 bus connection (read-only access pattern;
  the daemon never emits AT-SPI events) + ScreenShot2 fd-based captures
  (never pixel copies through the portal).
- **Control plane** — the private DBus (UI: kill/pause/resume/status;
  savantctl: same verbs) and journald structured logging.

All three planes are separated at the fd level from process start, so
the kill switch (input-plane revocation) cannot possibly disturb vision
or control (separate fds, separate code paths).

## Crash resilience (the reason this is a daemon, not a library)

- **Restart trust:** the unit is `Restart=on-failure` with
  `RestartSec=1`; a crashed core cannot leave a live input path (the
  context dies with the process — FID-2026-0915-004's fail-closed
  property), so crash-recovery needs no capability scrubbing.
- **State:** the daemon is stateless between sessions except one small
  file (`/run/user/1000/savant/core-state.json`: last kill timestamp,
  re-arm counter, current bind mechanism) for the operator journal.
  No secrets, no cache, nothing to corrupt.
- **Watchdog:** `WatchdogSec=10` — a hung core is killed by systemd and
  comes back with no input capability (re-arm required). A hung agent
  can never keep acting.

## Interaction pipeline (how an agent action flows)

```text
agent client → DBus Action request (action + args)
  → policy gate (see below)
  → AT-SPI2 target resolution (node path, never coordinates blindly)
  → input synthesis (EIS: pointer move/click, key events; xkbcommon for keysyms)
  → completion event + journal line (action, target, latency, outcome)
```

- **AT-SPI2-first interaction** (per parent Loop 1): the daemon resolves
  targets through the accessibility tree — stable names, roles, and
  coordinates in compositor space — instead of raw pixel guessing.
  Vision (ScreenShot2) exists for cases AT-SPI2 can't see (custom GL
  surfaces), explicitly as fallback.
- **Policy gate** (minimal v1, extends in T4.3): kill-switch state
  (injection refused when severed), per-action confirmation policy
  (UI-configurable allowlist for no-confirm actions; everything else
  requires the operator's UI ack). Refusals are journaled with reason.

## Language/dependencies of record

- **Go**, reusing the repo's existing toolchain, DBus, and logging
  idioms (`app/` is Go; no new runtime enters the image).
- libei bindings: **cgo against the guest's libei** (the image already
  ships the library — FID-2026-0915-003) with a pure-Go DBus path for
  the portal fallback. AT-SPI2 over dbus (pure Go, no cgo).
- ScreenShot2 via the portal's fd passing (no PNG intermediates in the
  pipeline; frames live in shared memory fds).

## Image integration (skeletons, factory pattern)

- `usr/lib/systemd/user/savant-core.service` — user unit per the
  confinement block of FID-2026-0915-004.
- Factory preset: **enabled** (the daemon runs for the desktop session;
  it holds no capability until the operator's UI arms it).
- Contract gates: assemble.sh content assertions (unit exists, preset
  line present, binary path correct) per the established pattern.

## T4.2 scaffolding sequence (what lands, in order)

1. **Skeleton + unit file** (no binary yet — image carries the shape)
   with contract gates green.
2. **Core skeleton binary**: DBus server + journald logging + status
   verb only (no input, no vision). Boots in the dev guest; `savantctl
   status` works. *Milestone: the daemon exists, touches nothing.*
3. **Vision plane**: AT-SPI2 read (tree dump verb). *Milestone: the
   daemon can see, still cannot act.*
4. **Input plane**: EIS bind + one injection behind the policy gate
   (armed by UI ack). *Milestone: the daemon can act.*
5. **Kill switch wiring** (all three triggers) + fd-table CI test.
6. **T4.3 UI** (Kirigami layer-shell) consumes the same DBus verbs; T4.4
   exit demo runs the full contract from FID-2026-0915-004.

Each milestone is individually demonstrable in the dev guest; no
milestone silently widens capability (the gate progression is see →
act → sever-by-default).

## Verification

- Milestone 2–5 each carry their own dev-guest demo line (journaled) —
  filed into this FID as they land.
- T4.4 demo (parent's exit criterion) is the final verification.

## Verification Gates

- gate: build/vet/test/fmt per protocol.config.yaml
- gate: contract gate on any image-bearing milestone

## Perfection Loop

### Loop 2 — Design (2026-09-15)

- **RED:** "Merge UI into core to skip the DBus hop" — rejected: that
  re-couples the capability holder with the operator's hand, exactly
  what FID-2026-0915-004's topology law forbids.
- **RED:** "Python/prototype faster for v1" — rejected: adds a runtime
  to the image and a second toolchain to the repo for no capability
  gain; Go already speaks DBus and journald here.
- **ADVERSARIAL:** "AT-SPI2 is a fingerprinting risk (apps behave
  differently under screen readers)." — True for some apps; mitigations
  of record: (a) AT-SPI2 read-only access is a normal assistive
  pattern, (b) coordinates are always compositor-space so injection
  doesn't depend on app-side cooperation, (c) vision fallback covers
  apps that refuse AT-SPI2. Named, not ignored.
- **ADVERSARIAL:** "Daemon crash mid-injection leaves a stuck button."
  — Covered by topology: the EIS context dies with the fd's owner; the
  compositor releases the pointer. No stuck state survives the process.
- **CHANGE DELTA:** n/a (new design document; supersedes the parent
  Loop 1 "daemon + adapters" placeholder with this concrete form).
- **Convergence declared.**
