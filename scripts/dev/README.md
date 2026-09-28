# SavantOS dev live-loop VM

Iterate on SavantOS without ever rebuilding the factory image. One script
composes the launcher's built-in dev flags (`-ssh`, `-share`, `-instant`,
`-no-update`, `-dir`) into a disposable environment that lives entirely
outside the repo and outside any real install:

- data dir: `%USERPROFILE%\savantos-dev` (override: `SAVANTOS_DEV_DIR`)
- shared folder: `%USERPROFILE%\savantos-share` → guest `/mnt/host`
  (override: `SAVANTOS_DEV_SHARE`)
- SSH: Windows loopback port 2222 → guest sshd, user `savant`
  (override: `SAVANTOS_DEV_PORT`)

## Quick start (Git Bash)

```bash
scripts/dev/dev-vm.sh init        # seeds from Downloads/savantos-e2e/data
                                 # if present; else first boot downloads
scripts/dev/dev-vm.sh boot        # terminal 1: builds app/SavantOS-dev.exe,
                                 # boots with live console logs (foreground)
scripts/dev/dev-vm.sh shell       # terminal 2: ssh savant@127.0.0.1 -p 2222
```

`init --seed-from DIR` seeds from any existing install's `data/` folder using
the repo's sparse-preserving `sparsetool` — a faithful byte copy means the
launcher verifies the local payload against its copied receipts instead of
re-downloading the 1.7 GB factory image. No seed source and no `--seed-from`
means first boot downloads and digest-verifies the factory payload normally.

Seeding is a one-shot operation: `sparsetool` refuses an existing
destination by design, so a second `init` against the same `SAVANTOS_DEV_DIR`
stops rather than merging. Merge would be wrong anyway — it would carry the
previous run's receipts and update state into a target that is supposed to be
fresh. To rebuild a data dir from a seed source, pass `--reseed`:

```bash
scripts/dev/dev-vm.sh init --seed-from DIR --reseed   # replace in place
```

`--reseed` renames the existing dir to `<dir>.bak-<timestamp>` and seeds a
new one alongside it. Nothing is deleted, so a bad reseed is recovered by
renaming the backup back over `SAVANTOS_DEV_DIR`; delete the backups yourself
once the new dir has proven out. It also refuses to run while a guest is still
answering on the SSH port, since reseeding under a live VM corrupts the disk
it is using. This is also the cheapest way to get a known-clean target for
repeat runs, which is what the Stage 2 close/relaunch acceptance cycles need.

## Resetting a dev disk in place (no dialogs)

`--reseed` replaces the whole data dir from a seed. When you instead want to
keep the data dir (receipts, runtime, settings, share) and reset only the
guest disk, the launcher has a native path — T1.2 (FID-2026-0916-001), the
headless reset:

```bash
scripts/dev/dev-vm.sh boot -fresh -headless
```

`-fresh` rebuilds the writable disk from the factory payload; the old disk is
**retained** (renamed into `vm/before-reset-*/disk.raw`) for recovery, and
delete it yourself once the new guest has proven out. `-headless` is what
makes it automatable: the reset confirmation (`confirmResetBackup`) takes its
non-interactive default — proceed without the optional full backup, decision
logged to `vm/shell.log` — instead of opening the backup-dialog chain. A
pending setup cancel is still honored. The first boot after a reset
re-provisions the guest (first-run setup), so expect the usual boot time plus
provisioning.

Automation notes (the process rules below apply in full): run the launcher
with its stdio redirected, kill by Windows PID only, and remember the dev
`boot` foreground console disappears under `-headless` — tail
`$SAVANTOS_DEV_DIR/vm/shell.log` instead. This path is how vmtest/smoke
automation resets a real target between runs without any GUI present.

## The live loops

**Guest loop (no image rebuild, ever):** the shared folder is the bridge —
edit files on Windows, they appear in the guest at `/mnt/host` instantly.
Run `bash /mnt/host/hello.sh` inside the guest for the round-trip smoke
(writes `from-guest.txt` back to the share). The guest's writable disk
persists local changes across reboots: `yay -S <pkg>` and config edits stay
in the dev dir. When a guest change proves out, formalize it as a change in
the `guest-image/` builder tree (verified by
`scripts/release/build-guest.sh --contract-only` + the assemble.sh probes).
The old patch-authoring helper (`guest-patch.sh` → `guest-build/` mailbox
patches) was retired 2026-09-15 with the Omarchy kill list
(FID-2026-0914-002); see git history if you need the old flow.

- Mapping handled for you: a guest path `/p/f` becomes builder-tree path
  `guest/factory-overlay/p/f` (that is how guest content reaches the
  factory image).
- Modes and symlinks survive capture (tar over SSH); add mode refuses paths
  the builder already tracks (use `--modify`, which diffs against the
  pinned builder commit in `source.lock.json` — needs network for the
  fetch).
- Every patch carries a provenance header: builder commit, SavantOS source
  SHA, factory image provenance, captured paths. Author comes from your git
  config or `--author` / `SAVANTOS_PATCH_AUTHOR`.
- `commit` runs a `git am` round-trip proof before writing the patch — the
  builder's real consumer is the referee.
- Stage only intended content, never runtime-mutated state (`/etc` machine
  state, logs): that belongs to the writable disk, not the factory overlay.
- Before opening a PR with a real patch: `scripts/release/build-guest.sh
  --contract-only` (CI runs the same Guest contract job on every PR).

**Launcher loop:** `boot` uses `app/SavantOS-dev.exe`, a plain `go build`
(console, live logs). Kill it, edit Go code, rebuild, relaunch — the VM state
persists in the data dir between runs. `boot` passes extra flags through:
`scripts/dev/dev-vm.sh boot -nogpu`, `boot -fullscreen`, `boot -forward
tcp:8080:80`, and so on. It **refuses to start** (exit 2) when the QMP port
4450 is already taken, naming the process holding it: two VMs sharing one
control plane corrupt each other's state, and the old warn-and-proceed
behaviour turned a five-second fix into a confusing dead VM. Pass
`--force-qmp` to override when the holder is some unrelated process.

**Driving/observing:** the launcher exposes QMP on 4450 and the agent plane
on 4451 every boot; `scripts/vmtest/qmp.ps1`, `screenshot.ps1`, and
`clipimg.ps1` drive and capture the guest for headless checks.

## Process lifetime on this host

Four rules for anything that launches a long-running process. Each one
below cost a debugging session to learn; all four are measured, not
assumed.

- **Nothing reaps your background processes.** Four launch methods
  (plain `&`, `nohup`, PowerShell `Start-Process`, and a child of a
  command the tool *timed out*) each ran 20 minutes and exited
  **naturally** — no SIGTERM, no SIGINT. Assume orphans last until you
  kill them, and build teardown into any driver you write.
- **Redirect a long-running child's stdio or it will take your call down
  with it.** A child that inherits the calling terminal's stdout pipe
  keeps the *call* from completing; the call times out, and the timeout
  teardown then kills the tree. This is what a "harness sweep" looks
  like from the inside, and it is why an earlier note in this repo
  recorded a reaper that does not exist. Always:
  `nohup cmd >log 2>&1 </dev/null &`.
- **Kill by Windows PID, and never by image name.** `$!` in Git Bash is
  the **MSYS-side** pid; `taskkill /PID` will not match it. Read the real
  pid back (`netstat -ano`, `tasklist //NH`). Never
  `Stop-Process -Name <exe>` or `taskkill /IM`: the operator's own
  interactive VM is a real process, and killing by name destroys it. Use
  `taskkill /F /T /PID <windows-pid>` on the pid you started.
- **A probe that can return empty must fail closed.**
  `tasklist //FI "IMAGENAME eq qemu-system-x86_64w"` matches **nothing**
  without the `.exe` suffix — and an empty result looks exactly like "no
  QEMU is running". Parse `tasklist //NH` output yourself, and when a
  check depends on a probe, verify the probe is readable before trusting
  its answer.

## Close/relaunch acceptance

`accept-close-cycles.sh` drives the close contract for FID-2026-0915-002's
verification gates: ten close cycles with zero hangs, plus a forced-kill
predecessor so one relaunch runs against a hard-killed session. Per session it
waits for the guest ready signal, drives the real close path
(`accept-close-trigger.ps1` probes the caption close button's hit-test and
accepts the confirmation), waits for the launcher to exit, and records which
rung of the close ladder fired — graceful, escalated, or forced.

It needs a disposable data dir, so it refuses to start without
`--authorized-disposable-target` and refuses again if any QEMU is already
running (the trigger picks its window by process name). Check a target without
launching anything:

```bash
scripts/dev/accept-close-cycles.sh --authorized-disposable-target --preflight-only
```

`CLOSES=1` gives a single-cycle smoke run. A full run takes tens of minutes and
starts a VM, so launch it detached with its own output redirected — a
foreground call would hold the terminal's stdout pipe open the whole time.
Nothing reaps orphaned processes here, so the driver kills only by PID and
installs a teardown trap; an interrupted run still leaves the host clean.

## Notes and limits

- `boot` runs the launcher in the foreground; shut down by closing the
  SavantOS window or quitting from the tray icon (Ctrl+C is an abrupt kill —
  fine for the launcher, but skip it when a clean guest poweroff matters).
- `boot` fails closed on a busy QMP port 4450 and names the holder. If it
  refuses but you know the holder is unrelated, `--force-qmp` proceeds with a
  warning. Nothing here kills by process name: stop the other instance the way
  you would normally stop it.
- SSH works only after the guest is up; `shell` fails fast with a hint until
  then (first boot takes ~a minute after provisioning).
- Port 2222 is loopback-only — Windows Firewall does not prompt.
- GPU rendering follows the normal rules (`docs/RUNTIME-VALIDATION.md`); pass
  `-nogpu` to force the CPU path deliberately.
- Deleting the environment: `dev-vm.sh stop` prints the exact uninstall +
  folder-removal steps for the current paths.
