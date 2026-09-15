# SavantOS Architecture

## What SavantOS Is

SavantOS is a sovereign agentic OS host for Windows. One signed, self-updating
launcher that:

1. Boots a Linux desktop guest under QEMU/WHPX (GPU via WINQ-EMU Venus/virgl,
   CPU fallback via llvmpipe),
2. Bridges the host and guest (clipboard both ways incl. images, shared
   folders, time/locale/keyboard sync, port forwards, optional SSH),
3. Self-updates with Ed25519-signed, SHA256-authenticated manifests
   (launcher, runtime, factory guest image), with staged installs and
   rollback,
4. Will host the Savant agent platform inside the guest (M2+ roadmap).

## Components

| Path | What it is |
| ---- | ---------- |
| `app/` | Go launcher (exe `SavantOS.exe`). Supervisor state machine: setup → boot → run → shutdown; setup download/verify/recovery; update state machine; QEMU/QMP control; tray + settings UI; uninstall; backup/restore/reset; portable mode. |
| `app/cmd/sign-update/` | Release tool that signs `update-v2.json` manifests with the Ed25519 update key. |
| `guest-image/` | First-party deterministic builder: mkosi config, Plasma 6 skeletons, wallpapers, assemble + content gates; `scripts/release/build-guest.sh` runs the dual-build digest gate. |
| `runtime-build/` | Source-locked CI build of the Windows QEMU runtime (WINQ-EMU QEMU + virglrenderer forks, per-commit pins in `sources.lock.json`). |
| `scripts/` | Host-side PowerShell tooling: launcher bootstrap, VM test harness (`vmtest/`), release pipeline (`release/`), guest overlay files (`guest/`). |
| `.github/workflows/` | CI (build/vet/test + release-pin validation + guest contract), release (two-phase: guest build+smoke, then sign+publish), runtime build, guest lock refresh. |
| `assets/favicon/` | SavantOS brand assets (icon source of truth for `app/icon.ico`). |
| `docs/` | Operator/user documentation and technical history (`FINDINGS.md` carries the provenance banner). |

## Host ↔ Guest Contract

- **Kernel cmdline words** (`savantos.*`): provision mode, trial credentials,
  timezone, keyboard, locale, share name, SSH port, forwarded ports, host
  time. The guest's initramfs/systemd overlay reads these; both sides must
  change together (host `app/` + guest patches).
- **QMP**: lifecycle control, keystrokes, screenshots, reboot-intent
  notification on port 4450. Never touch the QMP socket during the guest's
  first seconds (launch-wedge trap, see `docs/FINDINGS.md`).
- **Clipboard bridge**: host PowerShell helper ↔ guest socat agent, text and
  PNG, serialized delivery state.
- **Trial account** (instant mode): `savant`/`savant`, created by guest
  patch; the host hint string and the guest account must stay in sync.

## Update Trust Chain

- `app/update.go` pins `updatePublicKeyHex` (Ed25519). Manifests are signed
  by `app/cmd/sign-update` with the private half (GitHub secret
  `SAVANTOS_UPDATE_SIGNING_KEY`; key material lives outside the repo at
  `~/.savantos-keys/`, never committed).
- Release base: `https://github.com/savant0x/SavantOS/releases/download/`.
- `app/manifest.go` pins the default release URL + SHA256SUMS digest for the
  factory guest image; downloads are verified against the authenticated
  manifest before use, with install receipts enabling fast re-verify.
- Version scheme: Savant Versioning (`docs/SAVANT-VERSIONING.md`); the
  lineage restarted at v0.0.1.

## Agent Governance (ECHO)

Engineering work in this repo is governed by the ECHO Protocol (`ECHO.md`):
FIDs in `dev/fids/`, Perfection Loop (RED → GREEN → AUDIT → ADVERSARIAL →
COMPLETE), Hybrid Mode for routine changes, and the quality gates in
`protocol.config.yaml`. See `AGENTS.md` for the contributor/agent guide.

## Key Traps (from docs/FINDINGS.md — read before touching QEMU/WHPX code)

1. Always `-vga none` with `virtio-gpu-pci` (two-display trap).
2. Never connect to QMP during early boot (launch wedge).
3. WHPX: no XSAVE-state CPU features above SSE4.2 on stock QEMU (XSAVE
   cliff); `-no-reboot` + treat guest reset as "QEMU exits → relaunch".
4. `virtio-sound-pci` needs an explicit `-audiodev`, else the guest hangs.
5. Guest poweroff/reboot can wedge stock WHPX QEMU and lose recent writes —
   never treat a wedged-then-killed poweroff as clean.