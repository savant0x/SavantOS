# FID: Kate + Cursor IDE preinstalled in the desktop image

**Filename:** `FID-2026-0916-002-kate-cursor-preinstall.md`
**ID:** FID-2026-0916-002
**Severity:** medium (product content)
**Status:** converged (implemented; boot-verify lands with the next image build)
**Created:** 2026-09-16
**YAGNI-Compliance:** Verified (two apps, one new mechanism — a vendor lock —
reusing the existing digest-verification pattern; no config UI, no updater)
**Parent:** FID-2026-0915-006 (desktop experience), FID-2026-0915-001 (T5 track)

## Request

Operator: "i want both https://github.com/kde/kate and cursor ide to come
preinstalled."

## Grounding (evidence before design)

- **Kate already ships.** `guest-image/mkosi.conf` includes `kate` (Arch
  package, 26.04.3-1 confirmed installed in the running dev guest), and
  FID-2026-0915-006 D4 already pins it in favorites and taskbar. Work is
  evidence only — no code.
- **Cursor is not in the Arch snapshot pin.** The pin's ~30 "cursor" matches
  are all cursor *themes*. It is closed-source freeware distributed only as a
  self-updating AppImage; there is no repo package to pin.
- **AppImage runtime deps are in the pin:** `fuse2` (sandbox mount) and
  `libappindicator-gtk3` (tray). Added `fuse2` to the package list.
- **Distribution endpoint moved:** the historically documented
  `downloader.cursor.sh` is NXDOMAIN (DNS-over-HTTPS check, host and guest).
  Live endpoint (2026-09-16): `downloads.cursor.com` →
  `api2.cursor.sh/updates/download/golden/linux-x64/<build-id>` redirect.
- **Digest of record:** Cursor **3.20.21**, 305,666,552 bytes,
  sha256 `b9ec1e26…63bc9` (full digest in `guest-image/cursor.lock.json`),
  downloaded in-guest over the working NAT, ELF magic verified host-side.

## Design of record

**Vendor lock** (`guest-image/cursor.lock.json`): version, URL, sha256, size —
all pinned. `build.sh:fetch_cursor` downloads and digest-verifies at build
time (fail-closed, no lock file → build error). The blob never enters git;
determinism comes from the digest pinning the bytes, same trust shape as the
runtime payload lock.

`assemble.sh` gains probes: lock-file parse, AppImage at
`/opt/cursor/cursor.AppImage` with ELF magic, launcher script
`/usr/bin/cursor`, desktop file, and 512px PNG icon (extracted via the
AppImage's own `--appimage-extract`, no new container tools).

Desktop file + hicolor icon + favorites/taskbar pins in the savant layout.

## Perfection loop

1. **Challenge the framing.** "Preinstall a closed-source IDE" vs the trust
   posture: resolved via vendor lock — the image pins the exact vendor bytes
   and verifies them; we ship a digest, not a moving target. Alternative
   rejected: packaging an AUR-style repack (builds vendor trust we can't
   audit).
2. **Ordering / risk.** Endpoint rot is the top risk (already happened once —
   `downloader.cursor.sh` died). The lock file makes that a one-line,
   digest-verified rotation, caught by the build gate, not a silent drift.
   Auto-update inside the guest is left OFF: the image pins bytes; updates
   ship as lock rotations with the image.
3. **Convergence.** Kate = evidence-only. Cursor = vendor lock + probes +
   pins. Nothing else.

## Verification gates

- `guest-image/cursor.lock.json` parses and matches a live download (done:
  digest locked 2026-09-16).
- `--contract-only` gate green with the probe additions (done, rc=0).
- Full dual-build GATE GREEN with `fetch_cursor` in the chain, then boot
  proof: `cursor` launches in-guest, Kate present — filed back here.

## Resolution

Implemented 2026-09-16. Kate ships (evidence recorded); Cursor ships via
vendor lock. Boot verification follows the next image build.
