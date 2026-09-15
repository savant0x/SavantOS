# Developing SavantOS

How to iterate on SavantOS live, without ever rebuilding the factory image.
Three layers, fastest first: rebuild the **launcher** in seconds, mutate the
**guest** through SSH and the shared folder while it runs, and drive or
observe a running VM headlessly through the **QMP plane**.

The disposable dev environment these examples assume comes from
[`scripts/dev/dev-vm.sh`](../scripts/dev/README.md) — one command seeds a
dev data dir (12 GiB sparse copy in ~22 s from an existing install, or a
normal first-boot download), creates a shared folder, and boots a
console-build launcher with SSH wired up. Everything lives outside the repo
and outside any real install.

## Layer 1 — Launcher rebuild loop (seconds per iteration)

The launcher is a plain Go process; the guest runs independently of it, so
launcher changes never touch VM state:

```bash
cd app
go build -o SavantOS-dev.exe .      # console build — logs stream to stdout
cd ..
scripts/dev/dev-vm.sh boot          # boots with -share/-ssh/-instant/-no-update
# ... edit Go code, then: close the SavantOS window (or Ctrl+C), rebuild, boot
cd app && go test ./...             # unit layer (tests are colocated)
```

- `boot` rebuilds `SavantOS-dev.exe` automatically when missing; extra flags
  pass through (`boot -nogpu`, `boot -fullscreen`, `boot -forward tcp:8080:80`).
- The dev data dir persists between runs — settings, provisioned guest disk,
  receipts all stay. For a truly fresh state, point `SAVANTOS_DEV_DIR`
  somewhere new, or use the launcher's `-fresh` flag (starts over and keeps
  the previous writable disk for recovery).
- Gates before pushing launcher changes: `go build ./...`,
  `go vet -unsafeptr=false ./...` (plain `go vet` flags contractual
  win32 unsafe.Pointer interop — see `protocol.config.yaml`), `go test ./...`,
  `gofmt -l .` empty.

## Layer 2 — Live guest iteration (SSH + shared folder)

A factory-image rebuild costs 1–2 hours in the container pipeline. You almost
never need it: the running guest is fully mutable.

```bash
scripts/dev/dev-vm.sh shell                        # interactive shell as 'savant'
scripts/dev/dev-vm.sh shell uname -a               # one-shot commands
scripts/dev/dev-vm.sh shell bash /mnt/host/hello.sh   # share round-trip smoke
```

- **Shared folder:** `%USERPROFILE%\savantos-share` on Windows appears in the
  guest at `/mnt/host` (and as `~/savantos-share`). Edit on Windows, run in
  the guest, write results back — the classic edit/run loop with no image
  rebuild. `hello.sh` proves the round trip by writing `from-guest.txt` back.
- **State persists** in the dev disk across reboots: `yay -S <package>`
  (yay and the base-devel toolchain ship in the image), config edits, dotfiles.
- **Graduation:** a guest change that proves out becomes a skeleton/tree
  change in `guest-image/` (the first-party builder) — verified by the
  builder's contract gate (`scripts/release/build-guest.sh
  --contract-only`) and, for image content, the assemble.sh probes. Live
  mutation is the experiment; the builder tree is the durable form; the
  rebuilt factory image only ever ships through the release pipeline
  (`docs/RELEASE.md`). (The old `guest-build/` patch-train flow was
  retired 2026-09-15 — FID-2026-0914-002.)
- SSH authorizes your `~/.ssh/id_*.pub` automatically when `-ssh` is used;
  port 2222 is loopback-only (no firewall prompt).

## Layer 3 — QMP driving plane (observe and drive a running VM)

Every boot exposes QEMU Machine Protocol sockets for headless control. The
launcher ships drivers in [`scripts/vmtest/`](../scripts/vmtest/README.md)
(built for the nested-VM harness; the same ops work host-side):

```powershell
powershell -File scripts/vmtest/qmp.ps1 status      # {"return":{"status":"running",...}}
powershell -File scripts/vmtest/qmp.ps1 key meta_l,ret   # open a terminal in the guest
powershell -File scripts/vmtest/qmp.ps1 type 'echo dev'
powershell -File scripts/vmtest/qmp.ps1 key ret
```

(`status`, `key`, `type` verified live 2026-09-11; the key sequences are the
harness's own documented usage.)

**Port map — v0.0.1, observed on a live dev boot.** Ports can drift between
releases; never trust this table over discovery:

```bash
netstat -ano | findstr LISTENING | findstr 127.0.0.1   # then attribute PIDs:
tasklist /FI "PID eq <pid>"
```

| Port | Owner | Lifetime | Role |
| ---- | ----- | -------- | ---- |
| 2222 | qemu (`-ssh N` only) | guest up — survives launcher exit | guest sshd host-forward |
| 4445 | qemu | guest up — survives launcher exit | tools QMP (`qmp.ps1` target) |
| 4446 | qemu | guest up — survives launcher exit | win-key QMP (Win-key injection) |
| 4447 | qemu | guest up — survives launcher exit | auxiliary QMP |
| 4450 | launcher | launcher process only | boot/control plane |
| 4451 | launcher | launcher process only | guest agent plane |

**Known caveat (`shot`):** `qmp.ps1 shot NAME` issues QEMU's `screendump`,
but QEMU resolves the path against *its own* working directory — from a
host-side dev launch we could not locate the output at either absolute or
bare-relative paths. NEEDS-REVIEW; inside the vmtest harness (known CWD) it
works as documented. Use the guest's own screenshot tooling or the window
itself meanwhile.

## When things are half-alive (orphaned guest)

The launcher and QEMU die independently. If the launcher window/process is
gone but the guest still answers SSH, the QEMU process is orphaned: guest
ports (2222/4445/4446/4447) stay up, launcher planes (4450/4451) vanish.
Detection:

```bash
tasklist /FI "IMAGENAME eq qemu-system-x86_64w.exe"
scripts/dev/dev-vm.sh shell echo alive          # guest still reachable?
```

Recovery, gentlest first:

1. Shut the guest down from inside — still possible over SSH in the orphan
   state: `scripts/dev/dev-vm.sh shell sudo systemctl poweroff` (the trial
   account's sudo is passwordless — verified live 2026-09-11 via `sudo -n`).
2. `taskkill /IM qemu-system-x86_64w.exe` — last resort. Abrupt: the guest
   disk is not cleanly unmounted; the next boot may need an fsck (the guest
   handles this) or, worst case, the launcher's `-fresh` recovery path.
3. There is no `powerdown` op in `qmp.ps1` today — adding one
   (`{"execute":"system_powerdown"}`) is a known, small improvement.

## Relationship to scripts/vmtest

`scripts/vmtest/` automates a *nested* Windows VM (dockur/windows
container) for release-candidate testing — screenshots, keystrokes, shared
folders, sparse-disk tooling (`sparsetool`, also used by `dev-vm.sh init`
for seeding). `scripts/dev/` is the lighter host-side loop. The QMP ops and
driving patterns are shared between both.

## Before pushing

- Go changes: full gate from `protocol.config.yaml` (`build`, `vet
  -unsafeptr=false`, `test`, `gofmt`) — main takes direct pushes; CI runs the same
  gates on every PR.
- Docs: `bun run lint:md`.
- Guest changes intended to ship: `guest-image/` builder-tree change
  (gate: contract-only + assemble probes), then the release pipeline in
  `docs/RELEASE.md`.
