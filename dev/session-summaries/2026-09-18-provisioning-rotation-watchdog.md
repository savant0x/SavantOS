# Session Summary: 2026-09-18 — provisioning live-proof, disk rotation, build watchdog

**Session ID:** 2026-09-18-provisioning-rotation-watchdog

**Duration:** 2026-09-18 → 2026-09-19 (multiple sub-sessions)

**Status:** in progress (dual-build running under the respawn watchdog)

---

## Initial State

### Environment

- **Branch:** main @ `6c6d57f` (provisioning chain) → `adcba2f` (rotation guard)
- **Dev VM:** SavantOS-dev3 live with the provisioning chain installed
- **Build infra:** dual-build in Docker (mkosi), payload served over loopback

---

## What Happened

### 1. First-boot API-key provisioning (FID-2026-0917-002) — implemented + live-proven

Grounding corrections that shaped the design:

- The CLI's real config store is `~/.savant-code/credentials.json` — 0600, schema
    `{providerApiKeys:{OPENROUTER_API_KEY:…}}` — extracted from the v0.0.31 binary (`chmodSync(_, 384)`). The
    FID's guessed `~/.config/savant/` path was wrong and corrected.
- The "existing host→guest clipboard bridge" was half real: launcher listeners on 4448/4449 existed, but **no
    guest-side daemon shipped**.

Chain as built (all in the factory skeleton):

1. `savantos-clipboard.service` user unit + `clipboard-bridge.sh` at `/usr/local/bin/`, enabled via the user preset;
    `socat` + `wl-clipboard` added to the package list (runtime-installed in the live guest via the factory pacman
    criterion).
2. `provision-key` watcher (XDG autostart): watches the Wayland clipboard for `SAVANTOS-KEY:PROVIDER:<key>`, writes
    the CLI's own credentials.json mode 600, scrubs the guest clipboard, acks.
3. Launcher `-provision-key PROVIDER:KEY` (lifecycle port) sets the sentinel on the Windows clipboard and waits for
    the ack.

**Live proof:** host clipboard → bridge pull → provisioner → credentials.json 0600 → ack → host clipboard
    read `savantos: key provisioned` → key scrubbed both sides. First ack push silently failed (raw text vs the
    bridge's base64 frame) — caught against the launcher decoder and re-proven.

**Honest limit (filed):** the full headless agent session (`--print`) didn't complete on the 1 GB dev VM — the 172
    MB Bun standalone page-thrashes (~10 MB available, IO pressure 65%, `filemap_fault` loop). Environment constraint,
    not a provisioning failure; needs a default-sized VM.

### 2. Disk near-fill incident + rotation (operator escalation)

The build pipeline kept **full copies** of every artifact (build-a + build-b workspaces + contract copies, ~50 GB at
    peak) and only cleaned on success — two publish-tail failures left everything behind and nearly filled the 931
    GB drive.

Fixes (commit `adcba2f`):

- `build.sh` **rotation guard**: at startup, all stale build workspaces and old contract directories are removed;
    exactly one payload survives the run.
- **Fail-path self-clean trap**: gate failures clean up instead of leaving 26 GB behind.
- One-time sweep: duplicates (`contract-0917`, `guest.previous`, stale `out/contract`, scratch clones) removed;
    `winq-emu` runtime zip archived to `out/runtime-archive/`.

### 3. Build resilience: respawn watchdog

Two dual-build runs died to the Docker/WSL engine vanishing mid-run (01:20 overnight signature — sleep/hibernate
    kills vmmemWSL; AC/DC standby are already "never", so it's lid/hibernate behavior).
    `dev/scratchpad/build-watchdog.sh` runs detached: relaunches the build if the engine dies pre-verdict (safe:
    rotation guard makes every attempt a clean start), max 3 attempts, verdict detection per attempt.

### 4. 0918 dual-build status

- Run 1 (assembly A green, including the four provisioning-chain probes + savant-code/Cursor/Kate/chromium) died in
    assembly B's package phase (engine EOF).
- Run 2 (watchdog attempt 1): caches hot, staging gates green, long legs grinding. Publish tail (`out/contract`) still
    owed after GATE GREEN.

---

## Key Discoveries

- The 0918 run's assertion line confirms the whole provisioning chain is in the factory content gate (`savant scheme`
    covers provision-key + clipboard-bridge + unit + autostart).
- Disk-pressure incidents traced to *cleanup-on-success-only* design; the rotation guard removes the whole class.
- Engine death ≠ build bug: check `vmmemWSL` and the log's last timestamp before blaming gates.

## Commits

- `6c6d57f` provisioning chain (launcher + skeleton + probes)
- `adcba2f` rotation guard + fail-path self-clean
- `71bba05` boot-proof FID filing (0917 series)

## Artifacts

- `guest-image/skeletons/usr/local/lib/savantos/provision-key`
- `guest-image/skeletons/usr/local/bin/clipboard-bridge.sh`
- `guest-image/skeletons/etc/xdg/autostart/savantos-provision-key.desktop`
- `guest-image/skeletons/usr/lib/systemd/user/savantos-clipboard.service`
- `app/provision_key.go` + tests; `dev/scratchpad/build-watchdog.sh`

## Open

- Dual-build verdict + publish (watchdog running); fresh-boot factory proof of the provisioning chain after GATE
    GREEN.
- Launcher render guard (FID-2026-0917-001) still queued.
