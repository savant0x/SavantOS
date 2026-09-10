# NOTICE

This file accompanies the Apache License, Version 2.0 under which SavantOS is
distributed (see `LICENSE`). It records attribution for the works this
project derives from, as required by Section 4(d) of that License.

## SavantOS

Copyright 2026 Spencer Howell (Savant AI)

SavantOS is a hard fork of Try Omarchy for Windows. The Windows launcher
(`app/`), guest-image patches (`guest-build/`), runtime build
(`runtime-build/`), scripts, CI workflows, and documentation in this
repository derive from the works listed below, imported as a pristine
baseline commit and then rebranded and extended.

## Try Omarchy for Windows

- Source: <https://github.com/omacom/try-omarchy-windows> (v0.0.14-preview)
- Earlier home: <https://github.com/tsouth89/try-omarchy-windows>
- License: MIT — Copyright (c) 2026 Brandon South
- What was used: the entire launcher codebase, guest patch series, runtime
  packaging, release pipeline, scripts, and docs. This is the direct parent
  codebase of SavantOS.

## try-omarchy (macOS)

- Source: <https://github.com/themartiano/try-omarchy>
- License: MIT — Copyright (c) 2026 Try Omarchy contributors
- What was used: the original try-omarchy concept and architecture that the
  Windows port (and therefore SavantOS) descends from.

## Omarchy

- Source: <https://github.com/basecamp/omarchy> — <https://omarchy.org>
- Maintainer: 37signals / Basecamp
- What is used: the Omarchy Arch Linux desktop distribution that ships inside
  the SavantOS guest image. The Omarchy mark belongs to its owner; it is NOT
  ours, and in-guest Omarchy branding remains the property of its owner. The
  distribution's packages are governed by their own upstream licenses.

## WINQ-EMU

- Source: <https://github.com/cmspam> (`winq-emu-qemu`, `winq-emu-virglrenderer`)
- Licenses: QEMU is GPL-2.0; virglrenderer is MIT (as pinned with per-commit
  hashes in `runtime-build/sources.lock.json`)
- What is used: the Windows QEMU runtime with WHPX fixes and Venus/virgl
  graphics forwarding, built from source by `runtime-build/`.

## try-omarchy-win guest image builder

- Source: <https://github.com/jorge-huxley/try-omarchy-win> (pinned in
  `guest-build/source.lock.json`)
- What is used: the containerized x86_64 guest-image builder and the
  direct-kernel-boot WHPX recipe that produces the factory disk.

## Chainfire

- Prior art and public guidance on WHPX interrupt-handling behavior in
  QEMU 11, which informed `runtime-build/patches/qemu/`.

## Trademarks

"Omarchy" is the mark of its respective owner and appears here only to
describe the guest operating system and to credit its authors. SavantOS is
not affiliated with, endorsed by, or sponsored by 37signals, Basecamp,
omacom, tsouth89, themartiano, or the Try Omarchy authors.