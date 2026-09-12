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
re-downloading the 1.7 GB factory image. No seed source and no `-seed-from`
means first boot downloads and digest-verifies the factory payload normally.

## The live loops

**Guest loop (no image rebuild, ever):** the shared folder is the bridge —
edit files on Windows, they appear in the guest at `/mnt/host` instantly.
Run `bash /mnt/host/hello.sh` inside the guest for the round-trip smoke
(writes `from-guest.txt` back to the share). The guest's writable disk
persists local changes across reboots: `yay -S <pkg>` and config edits stay
in the dev dir. When a guest change proves out, formalize it as the next
numbered patch in `guest-build/` — that is how the existing patches were
authored.

**Launcher loop:** `boot` uses `app/SavantOS-dev.exe`, a plain `go build`
(console, live logs). Kill it, edit Go code, rebuild, relaunch — the VM state
persists in the data dir between runs. `boot` passes extra flags through:
`scripts/dev/dev-vm.sh boot -nogpu`, `boot -fullscreen`, `boot -forward
tcp:8080:80`, and so on.

**Driving/observing:** the launcher exposes QMP on 4450 and the agent plane
on 4451 every boot; `scripts/vmtest/qmp.ps1`, `screenshot.ps1`, and
`clipimg.ps1` drive and capture the guest for headless checks.

## Notes and limits

- `boot` runs the launcher in the foreground; shut down by closing the
  SavantOS window or quitting from the tray icon (Ctrl+C is an abrupt kill —
  fine for the launcher, but skip it when a clean guest poweroff matters).
- SSH works only after the guest is up; `shell` fails fast with a hint until
  then (first boot takes ~a minute after provisioning).
- Port 2222 is loopback-only — Windows Firewall does not prompt.
- GPU rendering follows the normal rules (`docs/RUNTIME-VALIDATION.md`); pass
  `-nogpu` to force the CPU path deliberately.
- Deleting the environment: `dev-vm.sh stop` prints the exact uninstall +
  folder-removal steps for the current paths.
