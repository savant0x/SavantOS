# FID: Embedded agent — Savant Code as native OS software

**Filename:** `FID-2026-0917-002-embedded-agent-savant-code.md`
**ID:** FID-2026-0917-002
**Severity:** high (Phase 3 direction setter)
**Status:** provisioning implemented + live-proven (bridge → sentinel →
0600 credentials.json → ack); agent definitions payload item open; full
headless session blocked on dev-VM memory (documented in open item 3);
next image build carries the whole chain
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
   **Live-found during the first real runs (both fixed, both caught by
   gates, not by shipping):** (a) MSYS cannot represent the exec bit —
   host chmod no-ops and `[ -x ]` lies, while the container bind presents
   777, so executability is asserted in-container and in the image
   content only; (b) mkosi normalizes bind-mounted trees to mode 0777
   (proved: the shipped cursor binary is 0777 and runs), so the image
   probe asserts the owner-exec bit via debugfs, not octal 0755 —
   validated against the real image (777/755 pass, 644 rejected).
3. Desktop integration **partial:** `savant-code.desktop` entry (TUI
   launched inside Konsole, `Icon=savant-code`) + kickoff/tasks pins are
   in; a square traffic-lights app icon was derived from
   `savant-start.svg`.
   **Key provisioning IMPLEMENTED + live-proven 2026-09-17/18:**
   grounding corrected the design — the CLI's own store is
   `~/.savant-code/credentials.json` (0600, schema
   `{providerApiKeys:{OPENROUTER_API_KEY:…}}`, verified in the v0.0.31
   binary: chmodSync(384), gHH=".savant-code"), NOT the FID's guessed
   `~/.config/savant/`. Chain shipped: (1) guest half of the clipboard
   bridge (scripts/guest/clipboard-bridge.sh →
   /usr/local/bin + savantos-clipboard.user unit + preset enable) — the
   host listeners 4448/4449 existed but the image never shipped the
   guest daemon; (2) `socat`+`wl-clipboard` added to mkosi Packages
   (verified on the 2026-08-11 pin); (3) `provision-key` watcher (XDG
   autostart): watches the Wayland clipboard for
   `SAVANTOS-KEY:PROVIDER:<key>`, writes the CLI's own credentials.json
   0600, overwrites the guest clipboard with the ack, pushes the
   base64-frame ack to the host, exits; (4) launcher `-provision-key
   PROVIDER:KEY` sets the Windows clipboard via the lifecycle port
   (`provision` verb) and polls for the ack.
   **Live proof in the running guest:** deps installed via the factory
   runtime-pacman criterion; bridge connected ("clipboard: guest
   connected" in the launcher log); sentinel placed on the host
   clipboard → provisioner wrote credentials.json **mode 600** with the
   exact CLI schema → guest clipboard = ack text → **host clipboard read
   back `savantos: key provisioned`** → key scrubbed from both sides.
   First push attempt failed (raw text vs base64 frame) — caught and
   fixed against the launcher's decodeClipFrame, re-proven.
   **Honest limit:** the full headless agent session
   (`--print`) did NOT complete on the current dev VM — the Bun
   standalone (172 MB binary) page-thrashes against the 1 GB guest's
   ~10 MB MemAvailable (PSI IO ~65%, stuck in filemap_fault); TUI
   commands (`--version`, `--help` over pty) succeed when memory frees.
   `--print` on a default-sized VM (or the TUI interactively) remains
   the operator proof; the test key was invalid by construction so an
   OpenRouter auth error was the expected best case. Also surfaced:
   `SAVANT_CODE_RG_PATH` needed for ripgrep in headless runs (no rg in
   the payload) — queued with the D-series work.
   **Still open:** first-party agent definitions in the payload.
4. Boot proof on the next image build (CPU mode per FID-2026-0917-001):
   **DONE 2026-09-17.** Dual-build (assemblies A+B) GREEN — all six
   contract files byte-identical (rootfs.ext4 `6e63b67a…`, zst
   `c63c9d67…`); savant-code probes passed on BOTH assemblies (ELF magic,
   lock binary digest `187873c8…`, owner-exec bit). Fresh payload served
   over loopback HTTP, provisioned by the unmodified launcher through
   `-release`/`-sums-sha256` (install-state.json digests match the new
   contract), booted `-nogpu` headless: "guest userspace announced ready"
   60 s after QEMU start. Guest evidence over SSH: `savant --version` →
   **0.0.31** (rc 0); `/usr/lib/savant-code/` carries the full app dir
   (env.json, tree-sitter.wasm, …); `/usr/bin/savant` present; modes 777
   (= shipped cursor precedent, owner-exec asserted by the assemble
   probe); `savant-code.desktop` + `savant-code.svg` in the payload and
   the entry already pinned in the live Plasma config; KWin active on
   CPU rendering (wedge-free config).
   **Incident recorded during proof:** the first `-fresh` attempt FATALed
   with "finish the pending update before resetting" — the 2026-09-15
   hard-kill had left `payload-update-state.json` guestPending=true and
   reset correctly refused (FID-2026-0915-002 close-flow behaving as
   designed). Recovery: cleared the pending marker (the step
   `commitGuestPayloadUpdate` would have done; `guest.previous` retained),
   then boot succeeded. Open work item remains the D2–D4 stall-visibility
   + close-flow pass in FID-2026-0916-001.
   **Still open (unchanged):** first-boot API-key provisioning (host→guest
   clipboard bridge into a 0600 config) — a real agent session needs it;
   until then the launch proof is `--version`/`--help` (rc 0) rather than
   a full session.

## Build & disk status (2026-09-18/19)

### Disk near-fill incident (operator escalation) — fixed

The pipeline kept full copies of every artifact (build-a + build-b
workspaces + contract copies, ~50 GB at peak) and only cleaned on
success; two publish-tail failures left everything behind and nearly
filled the drive. Fixes (commit `adcba2f`): the `build.sh` rotation
guard removes stale workspaces/old contract dirs at startup (exactly
one payload survives each run) and a fail-path self-clean trap runs on
gate failure. One-time sweep removed the duplicates
(`contract-0917`, `guest.previous`, stale `out/contract`); the runtime
zip moved to `guest-image/out/runtime-archive/` as its durable home.

### Engine deaths + watchdog

Three runs died to the Docker/WSL engine vanishing mid-build (01:20
overnight, ~14:50, ~17:00 — roughly a 2 h cadence; AC/DC standby are
already "never", machine appears to be a desktop on the High
performance scheme, so the trigger is still unidentified).
`dev/scratchpad/build-watchdog.sh` runs the build detached and
respawns it on pre-verdict engine death (safe: the rotation guard
makes every attempt a clean start). Watchdog attempt 1 died to the
engine; attempt 2's assembly A passed; attempt 3 ran the full ~2 h
7 m without an engine death.

### Attempt 3 verdict: dual gate GREEN, publish tail FATAL — fixed

Both assemblies green (content assertions incl. the full provisioning
chain; savant-code vendor digest `187873c8…` and Cursor `b9ec1e26…`
verified in-image). Dual-digest comparison: all six contract files
matched (rootfs.ext4 `28bcc259…`, zst `682a8433…`). The publish tail
then FATALed: the runtime zip was expected at `Downloads/` (the
pre-rotation default) and my sweep had moved it — a build-input
reference that survives nowhere in the repo. Fixed (`1f6c0d7`):
`RUNTIME_ZIP` resolution falls back to
`out/runtime-archive/winq-emu-alpha10-portable.zip`. Lesson recorded:
a fail-closed publish tail must be able to find its inputs from the
repo itself, or "fully green build, zero payload" can happen again.
Final run in flight under the watchdog; verdict + publish on arrival.