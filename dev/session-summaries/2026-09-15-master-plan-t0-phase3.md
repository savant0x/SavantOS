# Session Summary: 2026-09-15 (master plan, T0, Phase 3 m1+m2)

**Session ID:** 2026-09-15-master-plan-t0-phase3-m2
**Duration:** 2026-09-15 (master plan filing → T0 execution → Phase 3 design
set → savant-core m1+m2 landed + live-proven; dual-build running)
**Status:** in-progress (build in flight at summary time)

---

## Initial State

### Environment

- **OS:** Windows 11 host (Git Bash + PowerShell toolchain)
- **Language/Runtime:** Go launcher (`app/`), Go guest daemon (new:
  `guest-daemon/savant-core`), bash builder tooling
- **Branch:** main, in sync with origin at session end (through `11decb7`)
- **Last Commit at Start:** `37c3aab` (docs: FID statuses citing hashes)

### Repository

- Open FIDs: 0914-001 (Phase 3, analyzed), 0914-002 (kill list owed),
  0914-003 (close flow, proven-but-fragile), plus the fresh master plan.
- Working tree carried: glyph fix, mkosi indent fix, session summaries,
  the approved C1–C6 commit plan not yet executed.

## What Was Done (in order)

1. **C1–C6 commit plan executed** (34f6fa8 → 37c3aab): sandbox pin,
   Phase-2 desktop factory, keyring gates, release re-point (CI
   unbroken at HEAD), FIDs, summaries, hash-citing statuses.
   Disclosed evolutions: PowerDevil seed rode C2 (single-file
   finalize.sh), `.gitattributes` LF pin for guest-image/**.
2. **Master plan filed** (FID-2026-0915-001, `d7fa003`): five tracks
   (T0 unblock → T1 hardening → T2 deltas → T3 probes → T4 Phase 3),
   every open item claimed exactly once, four operator decisions
   surfaced.
3. **T0 executed:** push (CI green remotely), **Omarchy kill list**
   (`d0eff94`: 66 files, −13,276 lines, docs sweep, lock moved to
   scripts/release/), `nul` deleted, committed-tree boot proof.
4. **T0 boot proof surfaced two defects** (filed as FID-2026-0915-002):
   intermittent **PowerDevil close-drop** (ACPI event swallowed
   silently despite live seed — contradicts the 11:46 proof) and a
   **silent launcher exit during boot** (no WER, no log). Designed fix
   of record: launcher-authoritative close ladder (powerdown → verify →
   guest-side poweroff → waitExit kill), silent-exit impossible-by-
   construction logging.
5. **Phase 3 Loop 2 design set filed** (`3aeec5a`): 0915-003 input
   binding survey (EIS/libei primary, portal fallback, uinput rejected
   on safety-law grounds — all verified in-guest), 0915-004 safety-law
   architecture (three-process topology, kill switch = bind revocation,
   three triggers, confinement block), 0915-005 Savant Core design
   (six-milestone scaffolding sequence: see → act → sever-by-default).
6. **T4.2 milestones 1+2 landed** (`b4ded8e`, `b82d5b8`, `11decb7`):
   - `guest-daemon/savant-core`: dependency-free Go daemon; private
     0600-socket control plane with the exact law verbs (line protocol
     now — godbus is client-only, DBus surface deferred to m4,
     disclosed); sd_notify READY + WATCHDOG pings; Type=notify user
     unit with the full confinement block; preset-enabled; assemble
     probes include ELF-magic (Windows-embed unshippable); host-side
     cross-compile feeds both assemblies deterministically.
   - CI: guest-contract and release prepare gained setup-go; the
     contract gate now vet+tests the daemon on every push.
   - **CRLF gates rewritten byte-exact** (Python scan): grep proved
     irreproducible in this environment (0 vs 34 phantom hits between
     runs; Python byte arbiter: 0 both times). 3× green after rewrite.
7. **m2 live proof in the running dev guest** (no rebuild needed):
   full law-verb transcript green — fail-closed at boot, arm, kill,
   post-kill refusals, killAt journaled, QUIT exit, restart-disarmed.
8. **Dual-build with the daemon launched** (after unblocking: Docker
   Desktop zombie backends from Sep 11 killed+restarted, engine 28.4.0
   up; C: freed to 44 GB — a 76 GB pagefile had ballooned; the morning's
   contract HTTP server (PID 41092, port 8765) was killed holding the
   8.1 GB out/contract lock). First run caught my build.sh path bug
   (`guest-daemon/...` relative to the wrong cwd) — fixed script-
   relative (`11decb7`), relaunched: `savant-core built: c2bd36db…`,
   assembly A in flight.

## Findings & Decisions

- **9p host-share is a boot-time snapshot** — files written after guest
  boot are invisible in-guest; workaround: ssh/base64 piping. Launcher
  host-share service needs a refresh story.
- **grep CRLF detection irreproducible** — replaced with byte-exact
  scans in both gates (comment in-script carries the evidence trail).
- **QUIT reply races EOF** (cosmetic) — fix rides m3's savantctl.
- **PowerDevil close is intermittently unreliable** — close contract
  must not depend on it (0915-002's ladder, unimplemented yet).
- **Operator decisions taken this session:** kill-list sign-off
  (implicit in "t0"), dual-build proceed after Docker restart.
- **Still open from master plan:** T1 hardening (0777 /usr, headless
  -fresh), T2 delta pipeline, T3 launcher probes, 0915-002 fixes, m3–m6
  of the daemon, boot-verify of the in-flight build.

## Commit Lineage (this session)

```
34f6fa8 bd2e62f 40f36ff 9e48202 c2e839b 26d54a9 37c3aab   (C1–C6 + statuses)
d7fa003 docs(gov): master plan
d0eff94 chore(legacy): Omarchy kill list
3aeec5a docs(gov): T0 defects + Phase 3 design set
b4ded8e feat(phase3): savant-core m1+m2
b82d5b8 chore(phase3): drop stale go.sum
a4f63ed docs(gov): m1+m2 evidence + findings
11decb7 fix(build): build_savant_core pathing
```

## Handoff Notes

- Build log: `guest-image/out/build-2026-0915.log`; artifacts land in
  `/c/Users/spenc/dev/savantos-share/contract-0915` (build-guest.sh
  moves them out of out/contract). Verify dual-digest verdict, then
  serve + boot via the unmodified launcher and confirm the daemon
  ships: unit enabled, `savant-core` binary present, live STATUS over
  the socket. The OLD disk is retained at
  `vm/before-reset-manual-20260915` (recovery copy).
- If the build fails mid-flight, `guest-image/out/build-2026-0915.log`
  and `docker ps` are the first stops; the go step is host-side, before
  assembly A.
