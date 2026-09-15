# FID: Phase 3 Loop 2 — safety-law architecture (kill switch + confinement)

**Filename:** `FID-2026-0915-004-phase3-safety-law.md`
**ID:** FID-2026-0915-004
**Severity:** critical (operator ruling 2 implementation of record)
**Status:** converged (architecture of record; implementation in Phase 3 scope)
**Created:** 2026-09-15
**Parent:** FID-2026-0914-001 (Phase 3 — agent control plane), Loop 2
**Master plan:** FID-2026-0915-001 T4.1

---

## Summary

Implements operator ruling 2 as architecture: **the kill switch must
demonstrably sever agent input**. This FID defines what "the kill switch"
is, what it severs, what it provably does not touch, and how the exit
demo proves the guarantee. It is written so the guarantee is enforced by
process topology, not by daemon self-restraint.

## The law (from FID-2026-0914-001, unchanged)

> Agent input must be severable by the operator, demonstrably, in one
> action, without the agent's cooperation.

## Architecture of record

### Topology — three processes, two trust boundaries

```text
[ savant-ui (Kirigami, layer-shell) ]   ← operator's hand; NEVER holds input fds
   │  (private DBus, peer-to-peer, no system bus)
   ▼
[ savant-core (input+vision daemon) ]   ← the ONLY process with input capability
   │  (EIS context per FID-2026-0915-003; AT-SPI2 read-only)
   ▼
[ compositor consent (KWin) ]           ← structural revocation point
```

The operator control (savant-ui) and the capability holder (savant-core)
are **separate processes at separate privilege levels**. The UI cannot
inject input (it holds no fd and its DBus interface exposes only
kill/pause/resume/status verbs), and the daemon cannot show UI. Neither
can grant itself the other's role.

### Kill switch — three triggers, one mechanism

All three triggers converge on the same primitive: **revoke the input
bind** (close the EIS context / end the portal session per
FID-2026-0915-003) and enter a state where re-binding requires the same
operator action that granted it.

1. **UI button** (savant-ui, primary) — the one-action guarantee.
2. **Keyboard** — a compositor-level shortcut (KWin global shortcut)
   invoking the same DBus verb. Survives UI crash; lives in the
   compositor, which the agent never controls.
3. **Command line** — `savantctl kill` (root/unit-level), for headless
   and SSH administration; same DBus verb via the privileged path.

### What severance means (observable contract)

After the kill switch, **all** of these hold simultaneously and are
individually checkable:

- The EIS context fd no longer exists in savant-core's fd table
  (`/proc/$(pidof savant-core)/fd` shows no input capability).
- KWin's EIS receiver lists no bound client.
- Injected events stop at the compositor (a mechanical check: the demo
  client's injection calls fail with a disconnected context).
- savant-core stays **alive** — vision (AT-SPI2 read) keeps working; the
  operator retains inspection. Severing input is not killing the agent;
  observation continues, action ends. This asymmetry is the point.
- Re-arm requires operator action (UI re-enable), never daemon
  self-recovery.

### Confinement (what the daemon cannot do, structurally)

savant-core runs as a systemd **user** unit with:

- `RestrictAddressFamilies=AF_UNIX` (no network from the input plane).
- `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=read-only`
  with an explicit write allowlist (`SAVANT_LOG_DIR` only).
- **No root, no sudo, no device nodes** — uinput is excluded by
  construction, which is why FID-2026-0915-003's rejection is not just
  taste but a hard property here.
- The input capability arrives only through the compositor's grant; the
  unit file confers nothing.

### Failure posture

- **UI crash:** input keeps working (daemon holds its grant), keyboard +
  CLI triggers remain. Operator notice: compositor shortcut always works.
- **Core crash:** injection dies with the process — fail-closed by
  topology; EIS contexts die with their client. This is a feature: an
  agent that crashes cannot leave a live input path behind.
- **Compositor crash:** everything dies; session is gone anyway.
- **Compromised core (adversarial):** it can inject only while its
  context lives; revocation is one compositor-side action the agent
  cannot block (the compositor is not in the agent's trust domain). The
  system never depends on the agent's good behavior to enforce the law.

## Verification

- Exit demo (T4.4) proves the full contract: bind live → inject → kill
  switch (all three triggers, one per demo pass) → fd table shown empty
  → injection attempt fails → AT-SPI2 read still works → UI re-arm
  restores.
- A unit-test asserts the fd table has no input capability after the
  kill verb (CI-runnable, no display needed).

## Verification Gates

- gate: build/vet/test/fmt per protocol.config.yaml (T4.2)
- gate: T4.4 demo evidence referenced here when recorded

## Perfection Loop

### Loop 2 — Architecture (2026-09-15)

- **RED:** "One process with a kill flag is simpler" — rejected: a
  self-kill flag is the agent being trusted to restrain itself; the
  operator ruling requires severance independent of agent cooperation.
  Separation of processes is the minimal structure that satisfies it.
- **RED:** "Kill switch should also stop vision" — rejected (scope law):
  the ruling is about *input severance*; stopping observation removes
  the operator's ability to see what the agent was doing — strictly
  worse. Vision continues; action ends.
- **ADVERSARIAL:** "Agent could re-bind after revocation." — It cannot:
  re-bind needs a compositor grant, and the compositor's consent flow is
  operator-mediated (UI re-arm), which the agent cannot perform. Also
  `RestrictAddressFamilies` keeps the daemon off any bus it wasn't
  started with.
- **ADVERSARIAL:** "Keyboard shortcut can be swallowed by the agent."
  The shortcut is registered in KWin (compositor), not the agent's
  process; the agent has no path to intercept compositor-level input
  handling on a Wayland-only session.
- **CHANGE DELTA:** n/a (new architecture document; parent Loop 1
  comparison matrix remains as drafted, with this FID as its safety-law
  realization).
- **Convergence declared.**
