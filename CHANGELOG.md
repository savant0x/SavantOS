# Changelog

## Unreleased

### Added
- **T1.3 dual-build determinism re-run green, baseline published (FID-2026-0915-001):**
  two independent assemblies on the current tree hash identically across all
  six contract files, and run 2 reproduced run 1's digests byte-for-byte
  (`rootfs.ext4 a2dbea53…`) — determinism survives the commit boundary and
  carries the polkit rule. The stage-3 delta baseline is published in
  `guest-image/out/contract` with `release-base.json` (sums `5525ba54…`).
  The run exposed the recurring publish-tail trap (a transient handle on
  `out/contract` fails `rm -rf` and previously the EXIT trap destroyed the
  proven copies — second occurrence after 2026-09-19): `build.sh` now
  releases the trap once the gate has spoken, retries the removal with
  backoff, and on residual failure preserves `build-a/contract` with
  hand-publish instructions — exercised live by run 2.
- **Headless disk-reset for automation (T1.2, FID-2026-0916-001):**
  `dev-vm.sh boot -fresh -headless` resets a real target's writable disk with
  no dialogs — the `-fresh` confirmation takes its non-interactive default
  headless (proceed without the optional full backup, decision logged, cancel
  honored) and the old disk is retained in `vm/before-reset-*/` for recovery.
  The headless branch is unit-locked (a regression back to the dialog fails
  fast in `go test` instead of hanging), and the consumer is documented in
  `scripts/dev/README.md`. Live proof on a real target is operator-gated.
- **Dev tooling test suites in CI:** `scripts/dev/test-dev-vm-init.sh`,
  `test-accept-preflight.sh`, and `test-boot-qmp-refusal.sh` (92
  assertions, Windows-only by construction and none of which launch a VM)
  run in the existing `windows-launcher` job, so the re-seed path, the
  acceptance driver's refusal paths, and the QMP boot refusal cannot rot
  silently. The suites live beside the scripts they cover.
- **Close/relaunch acceptance driver (`scripts/dev/accept-close-cycles.sh`,
  FID-2026-0915-002):** drives ten close cycles plus a forced-kill
  predecessor and records which rung of the close ladder fired each time.
  Refuses to start without an explicit disposable-target authorization, or
  if any QEMU is already running (the close trigger selects its window by
  process name, so a stray second VM would mean closing the wrong one).
  Kills only by PID — never by image name, which would destroy an
  operator's own interactive dev VM — and installs a teardown trap, because
  nothing reaps orphaned processes: a terminal-launched child survives
  indefinitely (measured: 20 minutes across four launch methods, every
  probe exiting naturally with no SIGTERM). `--preflight-only` validates a
  target without launching a VM. **Acceptance run 2026-09-28: GATE GREEN** —
  10/10 close cycles, 11 sessions, 0 failures, `graceful=10`, against the
  operator-authorized disposable target `C:\Users\spenc\savantos-accept`.
  (The driver's own first run reported a false hang: `tasklist`'s
  `IMAGENAME` filter matches nothing without the `.exe` suffix, which made
  the stray-VM preflight vacuous and the forced-kill a no-op — fixed, and
  the process probe now fails closed on an unreadable list.)
- **Guest→host image clipboard (FID-2026-0922-001):** images copied in
  the guest now cross to the Windows clipboard — a `wl-paste --watch`
  push watcher beside the text watcher (PNG-only, 16 MiB cap, image
  flavor wins over text when both are offered), completing symmetric
  image support on the shared loop-prevention state.
- **Savant Code ships as native guest software (FID-2026-0917-002):**
  the Savant Code CLI is vendor-locked at v0.0.31
  (`guest-image/savant-code.lock.json`, digest-verified at build) with a
  `/usr/bin/savant` wrapper, desktop entry, and factory pins. API keys
  provision over the clipboard bridge into a 0600
  `~/.savant-code/credentials.json` (`-provision-key PROVIDER:KEY`),
  proven end to end on a fresh factory boot (~3 s sentinel→ack). Build
  pipeline hardening landed with it: disk-artifact rotation (exactly one
  retained payload, fail-closed on low space), an engine-death watchdog,
  and a runtime-archive fallback so a green verdict can never end in a
  missing payload.
- **Kate + Cursor preinstall verified on-image (FID-2026-0916-002):**
  fresh provision of the build-2026-0916 payload boots with Cursor at the
  vendor-locked digest (launch proof: full Electron tree + screenshot) and
  Kate 26.04.3 present. Incident found during the proof and fixed: the
  image lacked `xcb-util-cursor`, so any Qt app launched without a Wayland
  env (bare SSH, script tooling) aborted with the Qt xcb fatal;
  `xcb-util-cursor` now ships in the payload pin.
- **Headless fatal discipline (FID-2026-0916-001 D3):** `fatal()` no longer
  calls the blocking topmost MessageBoxW under `-headless` — a fatal now
  logs and exits so automation cannot dangle on an invisible dialog
  (found via a 15-minute silent stall at the runtime-verify step).
- **Pre-boot stall visibility (FID-2026-0916-001 D2–D4):** every pre-boot
  phase transition is logged and mirrored on the splash; a watchdog names
  the held phase after 90 s of silence (hidden-dialog hint at 5 min,
  never auto-kills); `-headless` runs dialogs as logged non-interactive
  defaults so automation can no longer dangle invisibly.
- **Desktop experience pass (FID-2026-0915-006):** wallpaper v3 from
  the deterministic generator, a compact clock date (`ddd d MMM`), and
  Chromium + FeatherPad preinstalled from the pinned snapshot with
  favorites/taskbar pins. The icon upgrade was gated off honestly —
  Colloid is absent from the pin — and Papirus-Dark stays by recorded
  fallback.
- **Savant Core daemon, milestones 1+2 (FID-2026-0915-005):**
  `guest-daemon/savant-core` lands as a confined, watchdogged systemd
  user daemon (fail-closed by construction) serving the
  KILL/PAUSE/RESUME/STATUS/QUIT law verbs over a 0600 control socket,
  with factory wiring asserting unit, binary, and preset in the image.
  Under operator-declared rebuild; FID-2026-0917-002 takes no
  dependency on it.
- **Metered-link download pause (FID-2026-0914-002 step 3a):** full
  payload downloads pause while Windows reports a metered connection,
  resume when it clears; allow via the settings checkbox or
  `-allow-metered`. Metadata and cached files are never paused.
- **Desktop identity — QML traffic-lights decoration
  (FID-2026-0913-001):** the Savant identity ships as a custom QML
  KDecoration (`savant-traffic-lights`, dots top-right) with the Savant
  color scheme and a single Windows-class panel; hover marks are
  centered QML primitives (measured within 0.5 px of dot center).
- **Plasma 6 desktop factory (FID-2026-0912-002):** KDE Plasma 6
  (Wayland) ships as the factory desktop — SDDM autologin to the Wayland
  session, factory presets and display-manager alias, themed Konsole
  profile, and assemble-time content assertions so a silently-empty
  desktop cannot pass the gate.
- **First-party guest builder (FID-2026-0912-001):** the guest image is
  built in-tree by `guest-image/` — mkosi rootless directory build on
  the pinned Arch snapshot, deterministic `mke2fs` assembly (sorted tar
  stream, fixed epoch/UUID), and a dual-build digest gate that makes a
  nondeterministic image unshippable. The six-file payload contract,
  grow-at-boot, and the `savantos-ready` lifecycle unit are emitted for
  the unmodified launcher.
- Savant desktop identity: the Savant and Savant Light themes (traffic-lights
  palette, glowing-dots wallpapers) as factory default, plus a Windows-style
  bottom taskbar (waybar: launcher mark, window list, clock, tray) launched
  with the session, with existing-user migration via the compat-revision
  catch-up flow (FID-2026-0911-005, patches 0046–0048).
- Developer live-loop environment (`scripts/dev/dev-vm.sh`): sparse-seeded
  disposable data dir, shared folder, and SSH wiring for iterating on the
  guest and launcher without rebuilding the factory image
  (FID-2026-0911-002).
- Guest patch-authoring helper (`scripts/dev/guest-patch.sh`): captures
  live guest files into the next numbered `guest-build/` mailbox patch
  (factory-overlay mapping, provenance header, exec-bit/CRLF hardening,
  `git am` round-trip proof) (FID-2026-0911-004).

### Changed
- **CPU rendering is now the guarded default (FID-2026-0917-001):** the
  GPU path can wedge the compositor when a window with a titlebar opens
  (Kate or any Qt app), freezing the desktop until a session restart.
  "Automatic" rendering boots CPU unconditionally — the render probe's
  day-long GPU memory is removed because it only recorded boot success,
  while the wedge strikes later. Choosing GPU in Settings or passing
  `-render gpu` still boots GPU but warns on every launch (log plus
  modal). The probe record remains for the forced-GPU runtime-rollback
  path.

### Removed
- **Omarchy kill list executed (FID-2026-0914-002, operator sign-off
  2026-09-15):** the legacy `guest-build/` patch train is deleted (51
  tracked files: 48 patches + README + source/runtime locks). Coupled
  changes in the same commit: `runtime.lock.json` moved to
  `scripts/release/runtime.lock.json` beside its only consumer and
  `prepare-assets.sh` re-pointed; the Omarchy-lock refresher
  (`scripts/release/refresh-guest-lock.sh`, `scripts/dev/guest-patch.sh`,
  `.github/workflows/refresh-guest-lock.yml`) removed with it. Docs sweep:
  COMPATIBILITY.md and MIGRATION.md retired as stubs, FINDINGS.md carries a
  read-first provenance banner (WHPX/QEMU findings stay load-bearing),
  README/AGENTS/ARCHITECTURE/knowledge/NOTICE/DEVELOPING forward-looking
  references updated to the first-party `guest-image/` builder. The vmtest
  retarget sequences after the next committed-tree boot proof, not with
  the deletions.

### Fixed
- **The close ladder's escalation rung now actually works (FID-2026-0928-001):**
  rung 2 (`ssh systemctl poweroff -i`) was polkit-denied — the factory image
  shipped no polkit rules, logind's default demands interactive auth, and
  the wheel NOPASSWD sudoers grant does not apply to a polkit-mediated
  action — so a dropped power event always ended in the forced QEMU stop.
  The factory image now ships `50-savantos-power.rules`, granting the
  `savant` user the power-off action family (bare, `-multiple-sessions`,
  `-ignore-inhibit`) with `yes`, per the operator ruling; reboot stays
  factory-default. Live escalation proof and the acceptance re-run are
  pending an image rebuild.
- **Dev `boot` fails closed on a busy QMP port (`scripts/dev/dev-vm.sh`):**
  a taken port 4450 only produced a warning, then launched anyway — so a
  second dev VM would fight the first over the control plane and leave a
  confusing dead guest. `boot` now refuses with exit 2 before it builds or
  launches anything, naming the holder's process and PID, and distinguishes
  "another SavantOS instance is still running" from "an unrelated process
  holds the port". `--force-qmp` overrides with a warning.
- **The close ladder now records which rung closed the guest
  (FID-2026-0915-002):** `runCloseGuard` started the ladder as a bare
  goroutine, so when the guest powered off, `supervise` returned, `main`
  logged `---- exiting ----` and returned — killing the ladder mid-poll
  before it could log its verdict. Across 11 real close sessions the rung
  line appeared **zero** times while "power button sent" appeared 11 times:
  exactly the ambiguity the ladder exists to remove, since a dropped power
  event would still have looked like a clean close. `startCloseLadder` now
  registers the ladder in flight and signals a verdict; `main` awaits it
  before the exit line, bounded by the ladder's own two verify windows plus
  a margin, and logs rather than hangs if a ladder cannot finish.
- **Dev data dir can be re-seeded (`scripts/dev/dev-vm.sh`):** a second
  `init --seed-from` against an existing data dir died on `sparsetool`'s
  "destination exists" preflight, leaving a half-initialized dir that no
  later run could recover. `init` now refuses with an actionable message
  (exit 2) and `--reseed` replaces the dir by renaming the old one to
  `<dir>.bak-<timestamp>` — never deleting it, so a bad reseed is
  recoverable. `--reseed` also refuses while a guest is still answering on
  the SSH port, and an existing-but-empty dir is cleared with `rmdir`
  (fail-closed: it cannot remove content). Repeat clean targets are what the
  Stage 2 close/relaunch acceptance cycles need.
- **Clipboard image frames and bridge observability
  (FID-2026-0922-001):** host→guest PNG frames were silently dropped by
  the guest pull loop (`base64 -d` over the `png:`-prefixed line);
  `--receive-image` now decodes them (signature check, 16 MiB cap) and
  the launcher logs every item that crosses, so a "copy doesn't work"
  report has a trace to read. Proven on a fresh factory boot of the
  2026-09-22 payload.
- **Guest pointer stays visible (FID-2026-0917-001,
  FID-2026-0916-001):** the guest cursor plane never reaches the SDL-GL
  window on click, so the pointer vanished over a live desktop;
  `KWIN_FORCE_SW_CURSOR=1` ships as a kwin drop-in (software cursor
  drawn in-frame, host input intact), and `-host-cursor` now warns that
  it kills host→guest pointer input.
- **savant-core startup crash-loop (FID-2026-0915-006):** the unit's
  `ReadWritePaths=%t/savant-core` required a pre-existing directory —
  `RuntimeDirectory=savant-core` fixes the 226/NAMESPACE crash-loop,
  with an assemble-time regression probe.
- **Window close powers the guest off (FID-2026-0914-003):** PowerDevil's
  `handle-power-key` inhibitor swallowed the ACPI power key behind the
  host close gesture; the factory seeds `powerButtonAction=8` (Shutdown),
  re-asserts it on login, and an assemble value probe makes a wrong seed
  unshippable. Proven on the first built image: one QMP `system_powerdown`
  exits QEMU in seconds.

### Governance
- ECHO Protocol 0.2.1: new Working Style clause — **no silent deferrals**;
  any element of an approved plan that will not be implemented requires
  operator approval before merge (arising from FID-2026-0911-005's post-
  closure record correction).
- Main branch flow: the PR-required ruleset was removed by operator
  directive; direct pushes to `main` are the normal flow, CI runs the full
  check suite on every push, and the force-push/deletion ban remains.
  Release playbook, SignPath submission, and policy stub updated to match.

### Documentation
- **Dual-build runbook added (`guest-image/RUNBOOK.md`, FID-2026-0914-002):**
  the T1.3 contract gate's full procedure distilled from the two 2026-09-28
  runs — prerequisites and the cheap `--contract-only` pre-flight, the
  detached-launch pattern, green-run log shape, every observed failure mode
  (Docker engine down, the publish-tail busy handle and its manual-publish
  fallback, vendor-digest mismatch, CRLF gate, NONDETERMINISM stop-rule,
  disk-space FATAL), the post-run checklist with cross-run digest
  verification, and the scope boundary against the remaining stage-3 rows.
  Linked from the FID's contract-gate declaration.
- **Stage-2 exit evidence complete (FID-2026-0916-001):** the override
  guard's live acceptance passes on the real launcher — damaged/partial
  installs refuse with exit 1 before any network I/O, runtime-only and
  anchored directories proceed past the guard, and the pointer-shaped
  incident form re-refuses. The G6 stall-reproduction campaign was aborted
  by the operator after its windowed arms put VM windows on the desktop
  without approval: sample-staging campaigns are ruled out — VM work uses
  the real installs/targets only, with explicit approval. G6 remains a
  conditional obligation awaiting a live reproduction during real work or
  an explicit ruling; the partial run's warm-up anomaly (alive ~5 minutes,
  no log produced) is recorded in the FID for that evidence.
- G4 headless smoke satisfied (FID-2026-0916-001): a `-headless` boot of
  the provisioned dev target reached QEMU and userspace-ready 15 s after
  launch with every pre-boot phase logged, the share-skip decision logged,
  and no dialog block. The gate wording is corrected: on a provisioned
  directory the provision decision comes from the persisted
  `provision-mode` file and is never re-asked, so the fresh-install
  variant remains unexercised.
- New FID-2026-0928-001: the close ladder's privileged escalation rung
  cannot succeed. `systemctl poweroff -i` runs unprivileged over a
  `BatchMode=yes` ssh session against a guest with no polkit rules, so
  polkit demands interactive auth; NOPASSWD wheel does not apply because
  the action is polkit-mediated. A dropped power event therefore escalates
  straight to the forced stop. Ruled 2026-09-28 (F1 polkit rule, `yes`,
  power-off only) and fixed in the builder — see Fixed above.
- Harness process-lifetime rules documented (`scripts/dev/README.md`):
  no reaper exists, redirect long-running children, kill by Windows PID
  rather than `$!` or image name, and make empty-returning probes fail
  closed.
- Falsified tooling claim retracted (FID-2026-0922-001): the note recording
  that this harness sweeps terminal-spawned processes within ~2 minutes does
  not hold. Measured on 2026-09-28 across four launch methods — plain
  background, `nohup`, a PowerShell `Start-Process` detached tree, and a
  child of a command killed by the tool timeout — every probe ran 20
  minutes and exited naturally with no SIGTERM; `ping -t` survived 6+
  minutes. The real mechanism behind the symptom is a long-lived child
  holding the calling terminal's stdout pipe, which makes the *call* time
  out and take the tree with it. A desktop-app restart is not excluded and
  remains the likeliest explanation for the one run in question.
- First-party OS pivot filed (FID-2026-0912-001): the guest is rebuilt as a
  first-party mkosi + systemd-repart builder (Arch base, snapshot-pinned) with
  a KDE Plasma 6 Wayland desktop, native traffic-lights theming, and the
  Savant agent embedded via the live-verified KWin EIS + AT-SPI2 control
  plane. Operator rulings recorded: research reconciliation adopted, agent
  safety law confirmed, and a NO-WIPE ruling — the launcher, release
  pipeline, dev loop, and SignPath work are untouched; the Omarchy patch
  train (`guest-build/`) retires surgically after sign-off. Deep Research
  brief and reconciliation recorded under `dev/`.
- Developer guide (`docs/DEVELOPING.md`): the three live-iteration layers
  (launcher rebuild loop, guest iteration via SSH/share, QMP driving plane),
  observed port map with plane lifetimes, and orphaned-guest recovery
  (FID-2026-0911-003).
- Release playbook (`docs/RELEASE.md`) replaces the inherited upstream
  release doc (now removed): three-phase workflow, manifest pin recipe,
  PR-only main mechanics, and the `signing` input choices.
- README badges (release, downloads, CI, license); repo topics and homepage
  configured.
- SignPath submission: MFA recorded as verified via the GitHub API
  (FID-2026-0911-001).
- FID-2026-0911-001 closed and archived.
- FID record reconciliation (2026-09-27): FID-2026-0912-002 (high),
  FID-2026-0914-003 (high), and FID-2026-0915-006 (medium) closed and
  archived with completed resolution records; active FID status
  metadata normalized to the allowed value set.

## v0.0.1 - 2026-09-11

The SavantOS lineage restarts at v0.0.1 (Savant Versioning,
`docs/SAVANT-VERSIONING.md`). All entries below the divider are inherited
upstream history, kept verbatim for provenance.

### Features
- Rebrand to SavantOS: launcher identity (module path, app title, exe,
  data dirs, window classes, registry, uninstall), guest kernel-cmdline
  words (`savantos.*`), the `TRY_SAVANTOS_*` host/guest env seam, trial
  credentials (`savant`/`savant`), and the renamed launcher scripts.
  Guest patches are proven by applying all 44 with `git am` against the
  pinned upstream builder commit.
- Update trust chain rotates to the SavantOS Ed25519 keypair; the release
  base repoints to `github.com/savant0x/SavantOS` at v0.0.1 with an
  all-zero placeholder manifest so first-run verification stays
  fail-closed until the first factory image is published.
- Governance scaffold: ECHO protocol, FID lifecycle, coding standards,
  markdownlint docs gate, and aligned quality limits.

### Fixes
- Release tooling is CRLF-safe on Windows (prepare-assets digest field,
  test fixture line endings).

---
## v0.0.14-preview - 2026-09-05

### Features
- The guest follows the Windows display language: the launcher passes it along with the time zone and keyboard layout, and the guest generates that locale and makes it the default for the next login. `-locale` overrides it. Existing guests gain this with the next guest-image update.
- A runtime archive that is unchanged between releases is kept instead of being downloaded and unpacked again.
- Existing guests catch up with the image defaults on the first boot after an image update, without touching anything the person changed: an untouched `monitors.lua` gets the current QEMU profile (so CPU rendering starts with animations off there too), the "no gaps" and "single-window aspect ratio" toggles an older image switched on are removed when they are still the seeded copies, and Suspend leaves the system menu.

### Fixes
- Choosing Suspend inside Omarchy no longer freezes the VM window. The guest can no longer enter the S3 or S4 sleep states; a suspend request falls through to suspend-to-idle and the lock screen, and new guests have Omarchy's suspend-off toggle on so the system menu does not offer it.
- New guest images include the Noto CJK fonts, so Chinese, Japanese, and Korean text renders instead of boxes.

## v0.0.13-preview - 2026-09-05

### Features
- Automatic rendering now remembers when this PC cannot run the GPU path and goes straight to CPU rendering on later launches, retrying after a runtime or display-driver change, once a day, or when GPU is chosen in the new Rendering setting. A pending runtime update on a PC that already runs on CPU rendering is kept instead of being rolled back and downloaded again on every launch.
- Guest CPUs and RAM are sized to the machine: all logical processors but two (between two and eight) and a third of the RAM (4 to 8 GiB on CPU rendering; GPU rendering keeps its 6 GiB), with a Guest CPUs setting and `-cpus` to override.
- The guest image now includes fcitx5, so Omarchy's input method service no longer fails and restarts every two seconds for the whole session, and the CapsLock compose sequences work. Existing guests keep their packages, so on them the service now waits quietly until fcitx5 is installed (`sudo pacman -S fcitx5 fcitx5-gtk fcitx5-qt`).
- Print Screen inside the Omarchy window now goes only to Omarchy; Windows' own screen capture stays out of the way until you switch back.
- New guests on CPU rendering start with Hyprland animations off, since every animation frame is CPU time on llvmpipe; a choice in `looknfeel.lua` still wins. Existing guests keep their current setting.
- `TryOmarchy.exe -reclaim` while Omarchy runs gives the space of deleted Omarchy files back to Windows: the guest writes zeros over its free space within a budget the Windows drive can spare, and after the next shutdown the launcher turns those zero blocks back into holes in the disk file. Needs the current guest image.
- A small guest agent keeps the Omarchy clock in step with Windows: the launcher sends the host time when the guest connects, every five minutes, and right after Windows resumes from sleep, and the guest corrects itself when it has drifted by more than two seconds. Existing guests gain this with the next guest-image update.
- Images now cross the clipboard in both directions: a screenshot or picture copied in Windows pastes into Omarchy as PNG, and an image copied in Omarchy pastes into Windows apps. Text keeps working as before. Existing guests gain this with the next guest-image update.
- The guest follows the Windows time zone and default keyboard layout. Each is applied when it changes on the Windows side, so a layout or zone chosen inside Omarchy stays until Windows changes; `-timezone` and `-keyboard` override this for a launch. Existing guests gain this with the next guest-image update.
- The VM window remembers its size and position: a windowed launch reopens where the window was last left when that spot is still on a connected display, with the guest console sized to match.
- Try Omarchy registers under Windows Apps & features and can be removed from there, from **Remove Try Omarchy** in Settings, or with `-uninstall`. Removal offers a full backup first and deletes only this installation's shortcuts, registry entry, saved location, and data folder.

### Fixes
- Restore now budgets free space from the backup's compressed size instead of the sparse files' nominal size, so a 10 GB backup no longer demands 33 GB free. Restored files keep the modification times their receipts recorded, so a restored copy does not re-download its image and runtime on first launch, and a restore from Settings no longer asks about shortcuts again.
- New guest users no longer start with the "no gaps" and "single-window aspect ratio" Hyprland toggles switched on, which silently overrode gaps, border size, and rounding set in `~/.config/hypr/looknfeel.lua` (#32). Existing guests keep their current toggles; run `omarchy-hyprland-window-gaps-toggle` once to turn gaps back on.
- The Settings text under the SSH key row is no longer painted over by the label above it, and messages logged before the session log opens, such as the restored-payload decision after an interrupted update, now appear at the top of the log.

Thanks to [solkkku](https://github.com/solkkku) for reporting the Hyprland config override (#32).

## v0.0.12-preview - 2026-09-05

### Features
- Added backup, restore, and reset controls to Settings for stopped standard installs, plus `-backup` and `-restore` command-line options. Backups include the guest disk, boot files, bundled runtime, and settings, and every file is checksum-verified during restore. Restore creates a separate installation with its own launch and Settings shortcuts, so existing installations and backups are never replaced.
- Reset now offers a full backup first, prepares the new disk before moving the old one, and keeps the previous disk in a recovery folder. A failed or cancelled backup stops the reset.
- Added disk-capacity controls for standard installs, with in-place growth, current capacity and Windows free-space information. Lowering the setting never shrinks an existing disk.
- New standard installs now ask whether to use the default Local AppData folder or a different local drive or folder before downloading the runtime and guest image. Alternate locations are checked for write access and free space, remembered across launches, and carried into Start-menu and Desktop shortcuts.
- Install locations and shared folders are now chosen with the Windows folder picker. Unreadable preferences prompt an optional repair that preserves the original file and leaves guest files untouched.
- The app icon, setup splash, and VM window now use the official Omarchy mark.

### Fixes
- Added stable-release update support, including a bridge for older preview launchers and recovery-state compatibility. Stable installs stay on stable releases.
- Fixed clipboard sharing after reconnects and when copying an earlier value again. Guest copies keep trailing newlines, failed sends are retried, and overlapping transfers no longer suppress a later copy. Existing guest disks receive the updated bridge with this release's guest payload.
- Interrupted setup can reuse a completed download after a server outage or an ignored resume request, with the checksum verified before use. Failed runtime extraction keeps the verified archive for the next attempt, and short disk writes or oversized responses are detected.
- Cancelling setup on an existing installation now removes only launcher staging files. Unrelated `.part` files, shared folders, retained recovery data, and linked guest folders are left alone.
- Portable reset now prepares the new disk before retaining the old disk and its backing identity in a recovery folder, and rolls back if publication fails. Recovery data also survives a cancelled setup after an interrupted reset.
- Updated active download, update, issue, clone, and module links after the repository moved to `omacom`. Signed update manifests and existing guest and runtime receipts remain compatible with the old release base, so the transfer does not force a payload refresh or strand older launchers.

Thanks to [tcballard](https://github.com/tcballard) for the official Omarchy mark in the app branding, [7Wdev](https://github.com/7Wdev) for requesting install-location and disk controls, and [Sperum](https://github.com/Sperum) for the backup request behind the new backup and restore controls.

## v0.0.11-preview - 2026-09-03

### Features
- Standard installs now offer a dedicated `Omarchy Shared` folder for moving files between Windows and Omarchy. It is opt-in, can be disabled without forgetting the path, opens in Files the first time it is attached, and stays pinned in the sidebar without replacing user bookmarks.
- Added a tray menu while Omarchy is running for reopening the VM, opening the shared folder, Settings, diagnostics, and clean shutdown. Start-menu installs also receive a separate Settings shortcut, including existing installs on their next successful launch.

### Fixes
- Fixed upgraded guest disks skipping newer launcher integration when the Linux kernel version had not changed. Existing v0.8 through v0.10 guests now receive the shared-folder link and Files bookmark without replacing the guest or user data.
- Kept folder sharing available with CPU rendering when the bundled WINQ-EMU runtime is installed.
- Invalid or unavailable saved folders no longer prevent Omarchy from starting. Unsafe broad, system, network, reparse-point, and VM-data paths are rejected before launch.
- Fixed Settings opening behind the maximized Omarchy window when selected from the tray.
- Refreshed the locked guest packages for Mesa 26.2.2, WirePlumber 0.5.17, and GNOME Autoar 0.5.2.

Thanks to [majilesh](https://github.com/majilesh) for portable USB mode, [Tom Ballard](https://github.com/tcballard) for disk-space preflight, [Pedro Perez](https://github.com/pjperez) for ARM64 host detection, and [Chainfire](https://github.com/Chainfire) for WHPX guidance. Thanks also to [Jocelyn Legault](https://github.com/joce), [eskwayrd](https://github.com/eskwayrd), [Anees Khan](https://github.com/aneeskhan47), and [Brady Walsh](https://github.com/knighthawkbro) for reports that led to fixes in this release.

## v0.0.10-preview - 2026-09-03

- Withdrawn during prerelease testing because upgraded guest disks could miss the new Files integration. Superseded by v0.0.11-preview.

## v0.0.9-preview - 2026-09-02

### Features
- Updated new and reset guest images to Omarchy 4.0.2, a security release covering sshd hardening, browser policy directories, sudoers tightening, and signed packages from the Omarchy repository. Existing writable guests keep their installed OS and user data; the updated initramfs adds the matching launcher integration without replacing them.
- Added disk-space checks before the large guest download, unpack, and writable-disk copy, using sizes from the authenticated guest manifest, so a full drive is reported before the expensive step instead of after a partial copy.
- Added an experimental offline portable mode (`-portable`) that runs from a payload and data folder beside the launcher, keeps all guest state on the removable drive, makes no setup-time network requests, and uses a compact QCOW2 overlay that survives drive-letter changes and works on exFAT. See docs/PORTABLE_USB.md.
- Added loopback-only port forwarding into Omarchy (`-forward tcp:8080:80`) and an opt-in SSH preset (`-ssh 2222`) that starts sshd for that session and authorizes your public key for the Omarchy account. Nothing listens unless asked, and nothing is reachable from the network.
- The shared folder now appears inside Omarchy under its own name (`~/Work` for `C:\Users\me\Work`) as well as at `/mnt/host`. The link is removed again on launches that share nothing, and a real folder with content is never replaced.
- Added `try-omarchy-export` inside the guest: one archive with your configuration, theme, and added packages plus a restore script for a real Omarchy install. See docs/MIGRATION.md.
- Added a settings window (`-settings`) and a persistent settings file (`settings.json` in the data folder) for fullscreen, guest memory, the shared folder, port forwards, and the SSH key, with matching flags that win for a single launch. `-memory` is new.
- Added `-diagnostics`, which writes one zip of launcher and QEMU logs, guest console output, settings, update state, and machine facts for bug reports.

### Fixes
- Stopped setup on ARM64 Windows PCs with a clear explanation instead of failing through a WHP feature enable, a reboot, and impossible BIOS advice. Try Omarchy remains x86_64-only.
- Fixed startup on PCs whose hypervisor refuses nested virtualization, such as Intel Core Ultra laptops and machines with the full Hyper-V feature set. The launcher now retries with the interrupt controller in QEMU instead of failing, and the source-built runtime no longer treats the refusal as fatal.
- Shipped yay and the base-devel toolchain in new and reset guest images, so Omarchy's AUR install and update flows work out of the box.
- Shipped Omarchy's LazyVim configuration and clang in new and reset guest images, so Neovim starts with the expected setup and Tree-sitter can compile parsers.
- Fixed screen recording in new and reset guest images, which never started because the recorder was missing, and shipped the other tools Omarchy's keybindings and menus expect: the screenshot editor, OCR and QR capture, emoji and clipboard paste, man pages, the calculator, writer and video trimmer, Herdr, and the screen-share picker.
- Kept launcher and guest-image rollback active until the booted guest reaches userspace and networking. QEMU's control socket alone can answer during a kernel panic, so it is no longer treated as proof that an update is healthy.
- Preserved existing writable guests when a release raises the virtual disk size. The launcher now grows the disk in place instead of mistaking it for an incomplete first-run copy and replacing it with the factory image.
- Bound portable QCOW2 data to the authenticated factory-image digest so replacing its backing payload is refused instead of risking silent filesystem corruption.
- Rebuilt the Windows runtime to avoid 1 ms SDL redraw polling while the guest is idle. Real-hardware idle CPU and graphics checks still gate publication.
- Raised the guest PipeWire quantum to prevent false underruns from QEMU's coarse emulated HDA position updates.
- Backported Omarchy's notification close control and kept notification contents hidden while the lock screen or screensaver is active.
- Hardened failed-update recovery, settings and receipt writes, clipboard size checks, audio fallback, directory setup, and diagnostics redaction.

## v0.0.8-preview - 2026-08-30

- Fixed the launcher quitting on its own after about half an hour. Omarchy kept running, but the Windows key and every Windows shortcut went back to Windows, and the window could no longer be closed normally.
- Fixed setup blaming your connection when the real problem was a full disk.
- Removed a stall of about a minute when the bundled runtime rolled back to its previous version.
- Added resumable downloads so an interrupted setup continues where it stopped instead of fetching the payload again, with bounded retries when antivirus or indexing briefly locks a finished file.
- Added version details to the launcher, so Explorer, Task Manager and the Windows permission prompt now show Try Omarchy instead of a blank entry.
- Added a source-locked CI build for the patched Windows QEMU runtime, including matching source, licenses, package inventory, provenance, and per-file hashes.
- Added isolated signed test launchers so runtime candidates can be exercised without changing the production payload.
- Hardened runtime packaging and validated clean setup, CPU fallback, scoped Windows-key handling, clipboard sharing, shutdown, relaunch, and persistent guest data in a nested Windows VM.
- Made text clipboard sharing survive late guest startup, Wayland reconnects, early Windows copies, and temporary Windows clipboard contention.
- Updated the guest image to nautilus 50.3 and fd 10.5.
- Known limitation: Win+L still locks Windows instead of reaching Omarchy. Windows reserves that shortcut and no application can intercept it, so rebind the Omarchy action if you need it.

Thanks to [Tom Ballard](https://github.com/tcballard) for resumable downloads in [PR #7](https://github.com/omacom/try-omarchy-windows/pull/7), and to everyone who reported Windows shortcuts leaking through while Omarchy was running.

## v0.0.7-preview - 2026-08-30

- Added CI for launcher builds, release-pin validation, and guest patch contracts.
- Added a two-phase release workflow that rebuilds and smoke-tests the guest, signs the optimized launcher through Azure OIDC, and verifies public downloads before marking a release Latest.
- Added authenticated automatic updates for the launcher, bundled runtime, and factory guest image, with staged installs and automatic rollback after a failed first boot.
- Added bounded retries for temporary DNS, connection, rate-limit, and server failures during setup downloads.
- Made instant-mode credentials explicit in the account choice, setup splash, and a one-time first-desktop notification.
- Removed the duplicate Windows pointer over the guest-rendered cursor, with `-host-cursor` retained as a diagnostic fallback.

Thanks to everyone testing Try Omarchy on real hardware and over remote sessions.

## v0.0.6-preview - 2026-08-29

- Added a stable launcher under `%LOCALAPPDATA%\TryOmarchy` with optional Start-menu and Desktop shortcuts selected inside the branded setup window.
- Added an app compatibility guide covering Arch packages, VS Code, and current VM limitations.
- Added an optional instant trial account that skips the first-boot form and lands directly on the desktop.

Thanks to [Marx-Bray](https://github.com/Marx-Bray) for suggesting the launcher shortcuts in [issue #1](https://github.com/omacom/try-omarchy-windows/issues/1), and to everyone testing Try Omarchy across different Windows setups.

## v0.0.5-preview - 2026-08-29

- Reworked the setup splash with a clear SUPER-key explanation and starter shortcuts.
- Added safe cancellation that stops active downloads, removes partial setup data, and keeps the launcher.
- Authenticated the release manifest before downloading payloads and added recovery for incomplete installs.
- Prevented QEMU from trapping the Windows cursor when Try Omarchy is used over RDP.
- Documented essential keys, uninstalling, compatibility expectations, and common questions.

Thanks to [Tom Ballard](https://github.com/tcballard) for the release-manifest hardening and incomplete-install recovery in [PR #2](https://github.com/omacom/try-omarchy-windows/pull/2), and to everyone who tested the early previews and reported rough edges.

## v0.0.4-preview - 2026-08-29

- Kept the progress window visible until Omarchy opened.
- Sized guest memory to what the PC could spare and retried with less when needed.
- Kept setup errors visible above other windows.

## v0.0.3-preview - 2026-08-29

- Shipped the signed one-file Windows launcher.
- Added GPU runtime setup, graceful shutdown, clipboard sharing, folder sharing, and reliable guest reboot handling.
- Added the Omarchy 4.0.1 guest image used by later launcher releases.

## v0.0.2-preview - 2026-08-28

- Updated the guest to Omarchy 4.0.1 with all upstream themes.
- Added screensavers, autologin, clipboard sharing, host-folder mounting, and a visible SDL cursor.

## v0.0.1-preview - 2026-08-28

- First developer preview of Omarchy running under QEMU and WHPX on Windows.
