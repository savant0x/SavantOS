# Session Summary: 2026-09-17 — KWin wedge investigation, launcher hardening, Cursor/Kate ship

**Session ID:** 2026-09-17-wedge-hardening-cursor-kate

**Duration:** 2026-09-17 (multiple sub-sessions)

**Status:** completed

---

## Initial State

### Environment

- **Branch:** main; launcher `app/` (Go), guest image Plasma 6/Wayland
- **Live dev VM:** SavantOS-dev3 (Plasma 6, Wayland, CPU/GPU render mix)

### Trigger

Opening Kate (or any decorated window) hid the taskbar and pointer; later, **any click on the desktop** killed input.
    Operator asked for a full investigation + FID + perfection loop ("get serious").

---

## What Happened

### 1. KWin/input wedge investigation (kwin-wedge-probe.sh series)

Discriminated through the candidate causes on the live VM:

- **CSD vs server decorations:** CSD Kate wedged too → decoration path exonerated.
- **App class:** kcalc also wedged → not Kate-specific; any Qt widget app.
- **Root cause family:** the host GPU/fence path (Venus contexts created by the newer Mesa in the new image) —
    host-side, not guest config. Mitigated by CPU rendering in the affected flows.

### 2. Launcher hardening (FID-2026-0916-001)

- **D1/D1b/D1c:** foreign-dir override refusal, payload provenance fields, `dev-vm.sh` anchor; G1 unit tests + G2
    incident-shape regression green (the 11:36 flag-shape incident replayed as a test).
- **D2–D4 stall-visibility pass:** pre-boot phase logging (`app/phase_core.go`, platform-neutral), 90 s silence
    watchdog, `-headless` mode with modal-dialog suppression, splash-mirrored phase text. Live-proven headless (full
    phase chain to qemu in ~1 s).

### 3. Cursor + Kate ship (FID-2026-0916-002)

- `fetch_cursor` chain verified in a full dual-build; **boot proof on the fresh payload**: Cursor launches, Kate
    present, evidence filed.
- Wayland capture path fixed (screenshot tooling in the payload) and the theme gallery evaluation rerun.

### 4. Savant Code ships (FID-2026-0917-002)

`savant-code` CLI (v0.0.31) shipped in the factory image: full app dir at `/usr/lib/savant-code/`, on PATH, desktop
    entry + traffic-lights icon, pinned in the live Plasma config. Boot proof: `savant --version` → 0.0.31 on a
    fresh `-fresh`-provisioned payload.

---

## Key Discoveries

- The dual-build gate caught two of its own bugs live: the exec-bit probe (MSYS can't represent the bit; moved
    in-container + debugfs owner-exec assertion) and a mkosi 0777 normalization (probe validated against the real
    image: 777/755 pass, 644 rejected).
- The launcher's close-flow safety (FID-2026-0915-002) correctly refused a `-fresh` reset while a pending-update
    marker existed — safety behaving as designed after a hard-kill; the marker is cleared exactly as the confirm
    step would.
- Port 2222 answered from the *old* morning VM while the new boot was pending — old-session collisions masquerade as
    "wrong payload".

## Commits

Launcher hardening + phase visibility + FID updates (0916/0917 series), savant-code chain: `fd5a888` → `71bba05`.

## Artifacts

- `dev/fids/FID-2026-0916-001-launcher-hardening.md`
- `dev/fids/FID-2026-0916-002-cursor-kate.md`
- `dev/fids/FID-2026-0917-002-embedded-agent-savant-code.md`
- `app/phase_core.go`, `app/provision_key.go` (bridging into 0918 work)
