# Project knowledge

SavantOS — a sovereign agentic OS host for Windows: one signed, self-updating
Go launcher (`SavantOS.exe`, ~8 MB) that boots a Linux desktop guest under
QEMU/WHPX with GPU rendering (WINQ-EMU Venus/virgl, llvmpipe fallback).
Hard fork of Try Omarchy for Windows; Apache-2.0. All engineering work is
governed by the ECHO Protocol (`ECHO.md`) — read it 0-EOF before touching
anything; gates and policy live in `protocol.config.yaml`.

## Quickstart

- Setup: Go 1.27 for the launcher; bun + markdownlint-cli for the docs gate;
  Docker for the guest image build. Nothing else is required locally.
- Dev (launcher loop, seconds per iteration — see `docs/DEVELOPING.md`):

  ```bash
  cd app && go build -o SavantOS-dev.exe .   # console build, logs to stdout
  scripts/dev/dev-vm.sh boot                 # live guest; `shell` for SSH in
  ```

- Test / full gate (Go from `app/`, docs from repo root):

  ```bash
  cd app && go build ./... && go vet -unsafeptr=false ./... && go test ./... && gofmt -l .
  bun run lint:md                            # repo root; any *.md change
  ```

## Architecture

- Key directories:
  - `app/` — the Go launcher (module `github.com/savant0x/SavantOS/app`):
    supervisor state machine, first-run download/verify, update state machine,
    QEMU/QMP control, tray + settings, backup/restore/reset, clipboard bridge,
    uninstall. Tests colocated as `*_test.go`; `app/cmd/sign-update/` signs
    update manifests; `app/testdata/` pins SHA256SUMS fixtures.
  - `guest-image/` — first-party factory-image builder (mkosi directory build,
    Arch snapshot-pinned, dual-build determinism digest gate, `boot-proof.sh`).
    Phase 2 (Plasma desktop + Savant identity) in active development —
    `finalize.sh` writes factory skel/Plasma config; `skeletons/` rides
    `SkeletonTrees`; wallpapers are generated host-side into the tree.
  - `guest-image/` — first-party deterministic builder (mkosi + Plasma 6
    skeletons); the legacy `guest-build/` patch train was retired 2026-09-15
    (FID-2026-0914-002); the runtime lock lives at
    `scripts/release/runtime.lock.json`.
  - `runtime-build/` — source-locked Windows QEMU runtime build (WINQ-EMU).
  - `scripts/` — PowerShell host tooling: bootstrap, launch, QMP plane,
    win-key forwarder, release pipeline; `scripts/dev/dev-vm.sh` is the dev loop.
  - `docs/` — operator docs; `FINDINGS.md` is the technical history (read
    before touching QEMU/WHPX code); `dev/fids/` holds ECHO FIDs, `dev/fids/archive/` closed ones.
- Data flow: the launcher supervises QEMU via QMP (launcher planes on
  4450/4451, qemu tool planes 4445–4447). The host↔guest contract rides kernel
  cmdline words (`savantos.*`: provisioning, tz/keyboard/locale, share name,
  SSH/port forwards) — host `app/` and guest side must change together.
  Clipboard bridges host PowerShell ↔ guest socat agent (text + PNG). Updates
  are Ed25519-signed manifests; the public key is pinned in `app/update.go`,
  key material lives outside the repo (`~/.savantos-keys/`).

## Conventions

- Formatting/linting: gofmt owns Go formatting; `go vet -unsafeptr=false` is
  the vet gate (plain `go vet` flags contractual win32 `unsafe.Pointer`
  interop); markdownlint (`bun run lint:md`) covers every `*.md` change —
  root `.markdownlint.json` is canonical, 120-col. On Windows the shell is
  Git Bash (POSIX syntax, forward slashes). Anything consumed by Linux
  tooling must pin LF explicitly — CRLF corrupted release digests three
  times on 2026-09-11, and executables imported from Windows lose the exec
  bit (fix with `git update-index --chmod=+x`).
- Patterns to follow: wrap errors with `%w`; never discard errors with `_`;
  no `panic()` outside tests/main; constants over magic strings; exported
  identifiers need doc comments; win32 interop stays inside `*_windows.go`
  behind `//go:build windows`; atomic commits as `type(scope): description`
  with the FID reference in the body; new code ≤350 lines/file, ≤50
  lines/function (inherited upstream files are grandfathered, protected by a
  behavioral freeze).
- Things to avoid: never connect to QMP during the guest's first seconds
  (launch wedge); always `-vga none` with `virtio-gpu-pci`; WHPX needs
  `-no-reboot` with guest reset treated as "QEMU exits → relaunch";
  `virtio-sound-pci` needs an explicit `-audiodev`; a wedged-then-killed
  guest poweroff is NOT clean — recent writes can be lost. Inside the mkosi
  build, don't chown uid 1000 (id-mapped sandbox, EINVAL) — `assemble.sh`
  reasserts ownership outside it. KConfig/unit/theme files must not carry
  CRLF (build gate fails). Never commit secrets or print key material into
  logs. FIDs live only in `dev/fids/`; changes >100 lines route through the
  Recorder agent. Bumping `currentVersion` requires regenerating
  `rsrc_windows_amd64.syso` (`versioninfo_test.go` enforces the sync).