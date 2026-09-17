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

## Boot proof (2026-09-17, image build-2026-0916)

- Dual-build (run `build-2026-0916`) reached the six-file digest list only
  after the A==B determinism comparison passed; the final packaging leg was
  reconstructed honestly after the run died at the missing runtime zip
  (builder hardened: missing-zip is now a fatal, not a warn). GATE GREEN,
  sums digest `a6ccbc5c…d439`.
- Fresh provision of that payload at `C:\savantos` (old writable disk
  retained): receipt verified, disk reseeded, GPU boot, userspace ready.
- Guest ground truth: `/usr/bin/cursor` present at the exact vendor-lock
  size (305,666,552 B), `cursor.desktop` present, `fuse2 2.9.9-5` installed,
  Kate `26.04.3` present.
- Cursor launch proof: launches over SSH with the session env sourced —
  full Electron tree up (15 procs); screenshot captured
  (`dev/scratchpad/theme-shots/cursor-running.png`, 2.4 MB).

## Incident found during the boot proof: Qt xcb fatal (fixed)

- `kate --version` over a bare SSH session SIGABRTs: Qt falls back to the
  xcb platform plugin and the image ships **without `xcb-util-cursor`**
  (`Could not load the Qt platform plugin "xcb" ... libxcb-cursor0 is
  needed`). Any Qt GUI app launched without a Wayland env (SSH, kdialog
  from scripts, xdg-open edge paths) dies the same way.
- Fixed live in the guest (`pacman -S xcb-util-cursor`): `kate --version`
  now passes under both `xcb` and `offscreen` platforms. Payload fix:
  `xcb-util-cursor` added to `guest-image/mkosi.conf`, ships with the next
  image.
- Note on the earlier "Kate takes down the taskbar" report: the disk where
  that reproduced (dev3) carried my theme-eval leftovers (Tela cursor/icon
  themes) and was superseded by this fresh provision; the fresh guest is
  factory-clean (empty theme overrides) and kwin/plasmashell stayed up
  through every Kate/Cursor launch in this proof. If it reproduces here,
  it gets its own FID with a coredump trail.

## Resolution

Implemented 2026-09-16. Kate ships (evidence recorded); Cursor ships via
vendor lock. Boot verification completed 2026-09-17 (fresh provision of
build-2026-0916): Cursor launches, Kate present, xcb-cursor incident found
and fixed in-guest + in the payload pin.
