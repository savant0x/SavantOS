# ECHO PROTOCOL v0.2.0 — SavantOS Agent Bootstrap

> **This is the SINGLE bootstrap file for any agent session in this repository.**
> Language-agnostic core; project-specific details live in `protocol.config.yaml`.
> **Version:** 0.2.0 | **Status:** ACTIVE | **Non-Negotiable: YES**

---

## Project Identity

SavantOS is a sovereign agentic OS host for Windows: a signed, self-updating
launcher that runs a Linux desktop guest under QEMU/WHPX and hosts the Savant
agent platform inside it. It is a hard fork of Try Omarchy for Windows
(attribution in `NOTICE.md`; inherited history below the divider in
`CHANGELOG.md`).

**Repo:** `savant0x/SavantOS` · **License:** Apache-2.0 · **Language:** Go
(`app/`, go 1.27) + PowerShell scripts + Python release tooling.

---

## The 15 Laws

### Laws 1–4: Immutable Process Laws (ALWAYS enforced)

1. **Read 0-EOF Before Touch** — every file read completely before any edit.
2. **Present Before Act** — every change presented with impact analysis
   before implementation; operator approval before code is written.
3. **Verify Before Proceed** — every change verified with the commands from
   `protocol.config.yaml` before moving on. No broken builds.
4. **Verify Call-Graph Reachability** — after wiring a feature, grep
   production entry points to confirm it is actually called. Compilation is
   NOT verification.

### Laws 5–15: Extended Code Laws (strict_mode: true)

5. No pseudo-code, TODOs, or placeholders.
6. No type-safety shortcuts (Go: no ignored errors `_` on fallible calls; no
   `panic()` in non-test, non-main paths; see `coding-standards/go.md`).
7. Search for existing code BEFORE creating new.
8. Log intent before coding — document the intended change in the session
   summary before implementation.
9. Generate production-grade documentation.
10. Update tracking after every feature (`dev/fids/`, `CHANGELOG.md`).
11. Follow discovered patterns EXACTLY.
12. Never expose sensitive data in logs/errors (tokens, private keys,
    `.env.local` contents — including in agent context).
13. Utility-first, universal logic — one function, one truth.
14. All error paths handled (propagate or explicitly handle every error).
15. Build stays clean — zero errors, zero warnings on the gates.

---

## The Five Questions

When evaluating any approach, ask:

1. Will this work for **ALL** cases, not just the common case?
2. Will this scale to **1000 agents**, not just 10?
3. Will this survive a **hostile attacker**, not just an honest user?
4. Will this be **maintainable in 2 years**, not just today?
5. Does this **set the standard** for the industry, not just meet it?

If any answer is no — redesign until all answers are yes.

---

## Perfection Loop FSM

```text
idle → red → green → audit → adversarial → complete
                ↑          ↓
                └── self_correct ←┘
```

- **RED** (Detective): identify ALL failures and issues; catalog evidence
  (file paths, line numbers, grep output, call-graph reachability).
- **GREEN** (Thinker + Forge): fix issues with MINIMAL changes; most robust
  defaults chosen; all questions answered.
- **AUDIT** (Verifier): double-audit with two independent methods; evidence
  must come from tool output; self-reporting is prohibited.
- **ADVERSARIAL** (Adversary): meta-verification; verdicts override the
  Verifier's.
- **SELF-CORRECT**: address audit findings; verify inline; re-audit if the
  fix is non-obvious.
- **COMPLETE** (Recorder): close the FID, archive to `dev/fids/archive/`,
  update `CHANGELOG.md`.

**Hybrid Mode (default for most tasks):** the Orchestrator writes code
directly for tasks below the complexity threshold (< 100 lines changed, no
novel architecture, verification passes), then verifies immediately with
the gates and spawns the Verifier when trigger criteria apply (10+ lines,
2+ files, new function/API, security-sensitive). Full FID-Bound Execution
(Forge implements from a converged FID) is reserved for genuinely complex
work — > 100 lines AND new imports/APIs, novel architecture, verification
failing twice, or explicit operator request.

**Circuit breakers:** ~10% character-change cap per pass; 10 iterations max
per loop; escalate if the same issue reappears 3 times.

---

## FID Lifecycle

FIDs (Feature Implementation Documents) live in `dev/fids/` only. Closed
FIDs move to `dev/fids/archive/` and get a `CHANGELOG.md` entry.

- Filename: `FID-YYYY-MMDD-NNN-{kebab-case-title}.md` (template:
  `templates/FID-TEMPLATE.md`).
- Required metadata: **Filename**, **ID**, **Severity**, **Status**,
  **Created**, **Author**.
- Status values: `created | analyzed | fixed | verified | converged | closed`.
- FID metadata is a claim, not ground truth — verify against the codebase
  before reporting status. A `closed` FID with no code violates the
  Ground-Truth rule.

### Version-Control Laws (G1–G9, abridged)

- Atomic commits, one coherent change each; G8 message convention:
  `<type>(<scope>): <description> (<FID-ID>)` with types
  `feat|fix|refactor|test|docs|chore|perf`.
- Never commit secrets (`.env*` is gitignored; signing keys live outside the
  repo at `~/.savantos-keys/`).
- No force-push, no history rewrite on `main`, no tag mutations outside the
  release pipeline.

---

## Working Style

- One problem at a time. Verify every change. Document as you go.
- Flag ANY issue you encounter, even outside current scope.
- Honest assessment: verification claims need tool output; design decisions
  need documented reasoning; status claims need independent checks.

## Quick Reference

| What | Where |
| ---- | ----- |
| This protocol | `ECHO.md` |
| Architecture | `ARCHITECTURE.md` |
| Project config | `protocol.config.yaml` |
| Go standards | `coding-standards/go.md` |
| Contributor/agent guide | `AGENTS.md` |
| FID template | `templates/FID-TEMPLATE.md` |
| Session template | `templates/SESSION-SUMMARY.md` |
| FIDs | `dev/fids/` |
| Lessons learned | `dev/LEARNINGS.md` |
| Versioning scheme | `docs/SAVANT-VERSIONING.md` |

---

> Perfection is the standard. No exceptions.