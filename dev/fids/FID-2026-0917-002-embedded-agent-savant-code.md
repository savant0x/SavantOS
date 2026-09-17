# FID: Embedded agent — Savant Code as native OS software

**Filename:** `FID-2026-0917-002-embedded-agent-savant-code.md`
**ID:** FID-2026-0917-002
**Severity:** high (Phase 3 direction setter)
**Status:** in progress — steps 1–2 landed (lock + fetch chain verified);
step 3 partial (entry + pins done, key-provisioning hook open); step 4
awaits the next image build
**Created:** 2026-09-17
**Parent:** FID-2026-0912-001 (pivot), FID-2026-0915-005 (savant-core — now
a downstream consumer of this design, not a prerequisite)

## Request

Add direct support for an embedded agent in SavantOS, and install the
Savant Code CLI as native software. Operator clarification (2026-09-17):
savant-core is being rebuilt and is not a foundation right now — **the
only thing ready is Savant Code**. The design therefore inverts: the
embedded agent is Savant Code itself, shipped in the OS.

## Grounding (evidence before design)

- **Savant Code is the harness product**: coding-agent CLI with typed
  agent definitions (`.agents/types/agent-definition.ts` — model via
  OpenRouter, per-agent tool subsets, `spawn` for sub-agents from the
  agent store `publisher/name@version`), ECHO protocol governance
  (`dev/echo-v0.1.2-single-agent.md`), and its own palette/theme system
  that already anchors the OS identity (traffic lights, Kvantum,
  color-schemes, wallpaper generators all derive from `palette.ts`).
- **savant-core state**: m1+m2 landed (`b4ded8e`, `b82d5b8`) but under an
  operator-declared rebuild; this FID takes NO dependency on it and does
  not touch `guest-daemon/`.
- **Distribution fact NOT yet grounded**: the exact artifact source for
  the Savant Code CLI (npm registry package, release tarball, or compiled
  binary) — this is implementation step 1 and must be verified before any
  lock file is written. Nothing in this repo records it.

## Design of record

### 1. Native install (vendor-lock pattern, proven by Cursor)

- `guest-image/savant-code.lock.json`: `{version, url, sha256, size}` —
  digest-pinned CLI artifact, fetched at build time by a `fetch_savant_code`
  step in `guest-image/build.sh` (same fail-closed, no-network-at-runtime
  discipline as `fetch_cursor`; the digest pins the bytes so builds stay
  deterministic).
- Installed to `/usr/lib/savant-code/` with a `/usr/bin/savant` wrapper in
  the guest PATH; probes in `assemble.sh`: lock parses, digest matches, ELF
  or entry-script magic present, `savant --version` executes headless.
- If distribution is npm-only: the lock pins a **packed tarball digest**
  (`npm pack` of a pinned version, cached at build) — never a live
  registry dependency inside the build.

### 2. Embedded agent = Savant Code sessions in the OS

- The agent runtime IS the CLI: first-party agents preinstalled with the
  image (ECHO-governed, `.agents` definitions shipped in the payload),
  launched from the terminal, the launcher pin (replacing the placeholder
  "Savant Code" taskbar entry from D4), or a desktop entry.
- OS integration surface v1 (this FID's scope):
  - `savant` on PATH + pinned in favorites/taskbar.
  - Working directory conventions: sessions open in `~/dev` (the folder
    the operator already created for this).
  - Model key provisioning at first boot: operator key delivered via the
    existing host→guest clipboard bridge into a 0600 `~/.config/savant/`
    config at first agent run — keys never baked into the image.
- **Safety-law honesty note**: until savant-core's action plane lands, the
  embedded agent's capability boundary is the shell (equivalent to any
  user session — it has no compositor/input powers beyond terminal
  access). The law's injection-severing story attaches when savant-core
  re-lands and becomes a Savant Code **tool backend**: desktop-control
  tools routed through the daemon's policy gate, so the kill switch severs
  the agent's hands by construction. That integration is FID-tracked
  separately when the rebuild lands; it must NOT be designed here.

### 3. Explicitly out of scope (YAGNI)

- No new agent runtime, no Python framework, no bundled local LLM, no
  model proxy in this pass — the harness already solved these decisions.
- No savant-core coupling, no Windows-host CLI (natural follow-up once
  the guest side proves; the Go launcher already speaks the port plane).

## Perfection loop

1. **Explanatory power**: covers both asks with one mechanism (the CLI is
   the native software AND the embedded agent). The daemon dependency
   inversion is recorded so nobody re-couples them by accident.
2. **Probe discipline (today's lesson applied)**: verification gates are
   headless-executable facts (digest, PATH, `--version` exit code) — no
   GUI-dependent proofs. `--version` runs in a bare env; the image now
   ships `xcb-util-cursor`, but the gate must not depend on it.
3. **Determinism**: vendor-lock digest + no registry-at-build = the
   byte-exact discipline the factory already enforces (Cursor precedent).
4. **Reversibility**: everything is one payload dir + PATH wrapper +
   pins; removal is `rm` of one directory and two config lines.
5. **Falsifiability**: if the CLI's real distribution turns out to be
   platform-specific binaries with a different update channel, the lock
   pattern still holds — only `fetch_savant_code` changes shape.

## Verification gates

- Lock file parses; artifact fetched and digest-verified at build.
- `assemble.sh` probes green: wrapper, PATH, `savant --version` (exit 0,
  expected version string), first-party agents present in the payload.
- Guest boot proof on CPU mode: `savant --version` over SSH; one real
  agent session run recorded in the journal/transcript.
- No `guest-daemon/` changes in the implementation commit.

## Open items (in order)

1. ~~Ground the distribution fact~~ **DONE 2026-09-17:** upstream is
   `github.com/savant0x/savant-code`, release pipeline ships
   `savant-code-linux-x64.tar.gz`; v0.0.31 pinned in
   `guest-image/savant-code.lock.json` (tarball sha256 `61b3ce77…18ad3`
   from the GitHub API, re-verified against the local download;
   binary sha256 `187873c8…` recorded for the image-content probe).
   Tarball layout confirmed FLAT (binary + sibling assets) → untars
   directly into `/usr/lib/savant-code/`.
2. ~~`fetch_savant_code` + install/layout + assemble probes~~ **DONE
   2026-09-17:** `build.sh` fetches digest-verified with cache; stages the
   untarred app into the skeleton tree and generates the
   `/usr/bin/savant` wrapper; `assemble.sh` probes ELF magic + lock-digest
   match on the image content; flat-tarball layout asserted live in the
   grounding extraction. Syntax + lock-parse verified; `python3` in the
   build container proven by the identical Cursor lock probe.
3. Desktop integration **partial:** `savant-code.desktop` entry (TUI
   launched inside Konsole, `Icon=savant-code`) + kickoff/tasks pins are
   in; a square traffic-lights app icon was derived from
   `savant-start.svg`. **Still open:** first-boot API-key provisioning
   (host→guest clipboard bridge into a 0600 config — no keys in the
   image) and the first-party agent definitions in the payload.
4. Boot proof on the next image build (CPU mode per FID-2026-0917-001):
   `savant --version` over SSH + one real agent session recorded.
