# FID: Phase 2 — Plasma 6 desktop with the traffic-lights identity

**Filename:** `FID-2026-0912-002-phase2-plasma-desktop.md`
**ID:** FID-2026-0912-002
**Severity:** high
**Status:** converged — landed `bd2e62f` (desktop factory; carries the
mkosi noto-fonts indent fix and the FID-2026-0914-003 seed), `.gitattributes`
LF pin in `bd2e62f`
**Created:** 2026-09-12
**YAGNI-Compliance:** Pending
**Parent:** FID-2026-0912-001 (first-party OS pivot — Phase 1 landed `717bb15`)

---

## Summary

Build Phase 2 of the pivot: a full KDE Plasma 6 (Wayland) desktop inside the
first-party builder's image, skinned with the Savant traffic-lights identity.
This delivers the operator's standing complaints about the Omarchy-based
image: no working minimize/close titlebars, no taskbar, no Mint-style start
menu, no desktop icons, no restart path, and residual Omarchy branding.
Everything ships through the existing gated builder
(`guest-image/build.sh`, dual-build digest gate) and boots via the
unmodified launcher, exactly like Phase 1.

## Evidence (read before writing, per Law 1)

- **Pinned packages verified on the 2026-08-11 snapshot** (from
  `extra.files`/`core.files` of `archive.archlinux.org`):
  plasma-workspace 6.7.4-1, plasma-desktop 6.7.4-1, kwin 6.7.4-3,
  `aurorae` 6.7.4-1 (standalone decoration engine package),
  sddm 0.21.0-7, sddm-kcm 6.7.4-1, plasma-login-manager 6.7.4-1,
  konsole/dolphin/kate/gwenview/ark/okular 26.04.3-1, plasma-nm,
  plasma-pa, powerdevil, plasma-systemmonitor, kdeplasma-addons,
  plasma-sdk (qdbus), breeze + breeze-icons 6.28.0-1, kdecoration,
  libplasma/plasma5support/plasma-activities 6.7.4-1, polkit-kde-agent,
  xdg-desktop-portal-kde 6.7.4-2, qt6-wayland 6.11.1, qt6-svg 6.11.1,
  mesa 26.1.6, vulkan-virtio + vulkan-swrast 26.1.6, pipewire 1.6.8,
  wireplumber 0.5.15, noto-fonts 2026.08.01, upower, power-profiles-daemon,
  xdg-user-dirs, xdg-utils.
- **Plasma ships the traffic-light buttons natively**: KWin's default
  `org.kde.breeze` decoration renders minimize/maximize/close as colored
  dots when `ButtonsColor` is set. The build does NOT need a custom Aurorae
  theme on day one; it needs `kreadconfig` calls (or a `kdeglobals` drop-in)
  setting `[org.kde.kdecoration2][ButtonsColor]` + ButtonClose/Maximize/
Minimize on the left group. A custom Aurorae theme is the fallback if
  Breeze's dot rendering is insufficient — decided by visual proof, not
  assumption. **REFUTED 2026-09-13** (FID-2026-0913-001): the premise does
  not hold on KWin 6.7 — breeze exposes only `AnimationDurationFactor`
  (kconfig read back one key) and the aurorae frame rendered without ever
  painting dots (session probes); the identity shipped as a custom QML
  KDecoration package (`savant-traffic-lights`, dots top-right) instead.
- **Savant palette is canonical** in savant-code
  `cli/src/utils/theme-system/palette.ts`: `#050508` background,
  `#18faf9` accent, `#39ff14`/`#ff9500`/`#ff2d55` lights,
  `#e4e4e8` foreground, `#8f8f99` muted, `#0b0b11` surface,
  `#14141c` hover. A previous session's
  `dev/scratchpad/gen-wallpapers.py` already generated deterministic
  traffic-lights wallpapers from this palette
  (`dev/scratchpad/out/savant{,-light}/`).
- **Phase-1 units that must keep working** (regression surface):
  `savantos-ready` (lifecycle `ready` to 10.0.2.2:4450), per-boot sshd,
  growfs-root, systemd-networkd DHCP. Phase 2 adds units on top; it must
  not reorder their boot relationships.
- **Launcher console policy**: `main.go` rewrites `console=tty0` out and
  pins `console=ttyS0` + `vt.global_cursor_default=0`; the VGA surface is
  owned by the compositor, the serial console stays text. Phase 2 relies
  on this: SDDM autologin starts kwin_wayland on tty1 (or tty7 — verified
  at boot) with the VGA output.

## Plan

1. **Package set** (`mkosi.conf`): append the verified Plasma/SDDM stack +
   `plasma-login-manager` (or `sddm` + greeter directly — whichever the
   snapshot's dependency graph favors at install time), `xterm` as the
   emergency X11 fallback, `spectacle` for visual-proof screenshots.
2. **Display manager**: SDDM with autologin config dropped in
   `/etc/sddm.conf.d/autologin.conf` (`User=savant`,
   `Session=plasma.desktop`, `Relogin=true`). `systemctl preset` policy
   gains `enable sddm.service`. Getty autologin from Phase 1 stays as the
   tty fallback but is masked for the graphical target only if SDDM and
   getty fight over tty1 — resolved by evidence at boot, not assumption.
3. **Traffic-lights identity** (factory defaults, system-wide, Kiosk
   `[$i]`-style immutability where practical):
   - `kdeglobals`: color scheme savant (see `colors/` below),
     `[KDE][widgetStyle]`, decoration `org.kde.breeze` with
     `ButtonsColor=semantically` colored traffic lights and
     close/max/min buttons present (left group, macOS order).
     (SUPERSEDED 2026-09-13 by FID-2026-0913-001: the ButtonsColor premise
     was refuted on KWin 6.7; the identity shipped as a custom QML
     `savant-traffic-lights` decoration with dots top-right.)
   - `kwinrc`: Windows decoration + focus policy; night-light off.
   - `plasmarc`: theme `breeze-dark` with Savant color scheme overlay.
   - `krunnerrc`, `kiorc`, `kscreenlockerrc`: consistent dark.
   - `colors/`: a `Savant.colors` KDE color scheme generated from the
     canonical palette (dark theme; light variant ships later with the
     light wallpaper work — not deferred, just out of this FID's scope
     and tracked as the light-mode follow-up).
   - Wallpapers: deterministic traffic-lights PNGs from
     `gen-wallpapers.py` become the factory wallpaper (plasma-org
     override + `wallpapers/` install).
4. **Desktop furniture** (the operator's explicit asks):
   - Taskbar: default Plasma panel bottom-centered with
     Icons-Only Task Manager pinned to (Konsole, Dolphin, Savant Code
     placeholder .desktop), system tray, clock. Layout via
     `plasma-org.kde.plasma.desktop-appletsrc` factory drop-in.
   - Start menu: Application Dashboard OR Kickoff pinned bottom-left
     with the Savant mark; verified clickable → menu anchors
     bottom-left (Mint-like). If Kickoff's default anchoring satisfies,
     keep it; custom QML is explicitly out of scope for this FID.
   - Desktop icons: enable the desktop folder view
     (`plasma-org.kde.plasma.desktop-appletsrc` contains the desktop
     containment) with Home + Trash + Konsole as initial icons.
   - Restart/shutdown: powerdevil + `polkit-kde-agent` +
     `systemd-logind` integration; verify the exit dialog offers
     Restart/Shutdown and that Restart actually reboots (QEMU `-no-reboot`
     is set by the launcher, so Restart must be exercised carefully in
     the proof — expected behavior is guest exit, host sees clean close).
   - Titlebars: minimize/maximize/close via the decoration config above;
     proved by screenshot showing the three dots.
5. **Branding sweep**: `/usr/share/{icons,wallpapers,pixmaps}` + SDDM
   face icons; `hostnamectl`-level identity already `savantos` from
   Phase 1; remove Omarchy strings from any inherited default config in
   the skeleton tree (grep-verified: `grep -ri omarchy guest-image/
   → zero hits in shipped files`).
6. **Gate**: existing `guest-image/build.sh` dual-build digest gate.
   Phase 2 adds a content assertion to `assemble.sh`: after population,
   `debugfs -R "cat /usr/bin/plasma_session" rootfs.ext4` exists (or
   equivalent presence probe for kwin_wayland + sddm + plasmashell) so a
   silently-empty desktop can never pass the gate.
   **2026-09-14 correction (FID-2026-0914-003 Loop 2):** the assertion
   block as landed probed `rootfs.ext4.part` AFTER the rename to
   `rootfs.ext4`, and debugfs exits 0 against a missing image file — every
   existence probe passed vacuously. The block now runs before the rename
   behind an explicit image-existence guard; the full evidence chain lives
   in FID-2026-0914-003 Loop 2.

## Perfection Loop

### Loop 1 — RED (adversarial, evidence-grounded)

- **R1 (contract):** The launcher caps guest RAM at 6144 MiB and CPU at
  8 (observed in `vm/shell.log` from Phase 1). Plasma 6 comfortably fits
  (it idles ~1 GiB), but `RecommendedMemoryMiB: 4096` in build-spec is
  aspirational; the actual allocation is launcher-controlled. No builder
  change needed; noted so a "Plasma is slow" report isn't misdiagnosed.
- **R2 (SDDM vs. launcher GPU flags):** The launcher boots QEMU with
  `virtio-gpu-pci` + venus/virgl. SDDM's default X11 greeter would try
  modesetting on top of that; `Session=plasma.desktop` (Wayland) is the
  only combination Phase 2 supports. Autologin must therefore point at
  the Wayland session explicitly, and `sddm.conf` should set
  `DisplayServer=wayland` for the greeter too. VERIFIED approach, not
  guessed: both values are documented SDDM 0.21 keys.
- **R3 (preset-all risk for SDDM):** Phase 1 proved `systemctl preset`
  strips hand-made enable symlinks. SDDM ships an `[Install]` section
  (WantedBy=graphical.target) so a preset `enable sddm.service` line
  works — but ONLY if `display-manager.service` alias resolution holds.
  Rather than trusting the alias chain, the preset enables `sddm.service`
  directly AND `finalize.sh` creates the canonical
  `/etc/systemd/system/display-manager.service → /usr/lib/systemd/system/sddm.service`
  symlink explicitly. Both mechanisms are idempotent; preset-all cannot
  undo the finalize-created alias because preset runs after postinst and
  only manages unit-name symlinks in `.wants/` dirs, not the
  display-manager alias. (Adversarial check: preset CAN manage the alias
  via `[Install]` Alias= — but only when the unit is being enabled, and
  our preset line enables sddm, so both paths converge on the same
  alias. Either way the alias exists at boot.)
- **R4 (wireplumber/pipewire user services):** Audio needs
  `pipewire.socket` + `wireplumber` as USER services. `preset-all` runs
  in the SYSTEM context. Arch's shipped user-service presets live in
  `/usr/lib/systemd/user/` with their own preset policy — verify during
  the build that `systemd --user` preset default-action for
  pipewire/wireplumber is `enable` (Arch ships `90-systemd.preset`
  enabling them). If the built image lacks the user wants-symlinks,
  `finalize.sh` creates them explicitly via a chroot'd
  `systemctl --global enable` (chroot via `mkosi-chroot`, the Phase-1
  proven path). Decided by build-tree inspection, not hope.
- **R5 (determinism surface grows):** Every new factory config file is a
  new nondeterminism vector (mtimes — solved by the existing epoch
  touch; content — all files are static text except wallpapers, which
  are deterministic PNGs from a deterministic generator). Plasma also
  generates machine-specific state on FIRST BOOT (kded caches,
  ksycoca, baloo index) — but that lands on the persistent data disk,
  not the factory image, so the gate is unaffected. The Phase-2 gate
  addition (presence probe) must itself be deterministic — it reads the
  image, writes nothing.
- **R6 (konsole default profile):** Konsole ships no profile file;
  first launch writes one. Factory color scheme: drop a
  `savant.colorscheme` (Konsole format) + `profile` that references it
  into `/usr/share/konsole/` — verified format from konsole packages
  (`WhiteOnBlack` ships as the example). System-wide default profile is
  set via `kdeglobals` `[KDE]` `DefaultProfile`... ACTUALLY via
  `consolerc` `[Desktop Entry]`-style `defaultProfile`... decided by
  reading konsole's shipped examples during implementation; recorded
  here so it isn't forgotten.
- **R7 (Kickoff favorite apps):** Kickoff favorites reference
  `.desktop` IDs. Factory favorites list: `org.kde.konsole.desktop`,
  `org.kde.dolphin.desktop`, `org.kde.kate.desktop`,
  `org.kde.systemsettings.desktop`. All four exist in the pinned
  package set (konsole, dolphin, kate, systemsettings).
- **R8 (guest-agent not required):** The launcher's clipboard/agent
  bridges are host-side TCP listeners; Phase 1 proved the guest reaches
  them with curl-equivalent tools. Phase 2 adds nothing there. SPICE
  vdagent is NOT needed (no SPICE display in the launcher's QEMU args).

### Loop 2 — GREEN (delta from source re-read)

- Launcher `main.go:593-607` re-verified: `console=` rewrite + append
  order means our cmdline additions must be appended in build-spec, not
  assumed merged — Phase 1 already ships `savantos.image=1` in the spec,
  Phase 2 adds nothing cmdline-related. Delta ~5%.
- The `vt.global_cursor_default=0` + SDDM interplay: the VGA cursor is
  hidden until a compositor draws — SDDM/kwin takes over fine (Phase 1
  serial log already showed a clean handoff to userspace). No change.
- Confirmed from `app/qemu.go` during Phase 1 forensics: GPU flags are
  virtio-gpu + venus; llvmpipe fallback exists via `vulkan-swrast` in
  the Phase 2 package list (already included above).

### Loop 3 — AUDIT (exit criteria)

1. Gate green on the extended package set (dual build, six digests).
2. Presence probe in assemble.sh passes (kwin_wayland, sddm,
   plasmashell binaries verifiably in the image).
3. Boot proof: unmodified launcher boots; guest announces ready; SSH
   probe confirms `systemctl is-system-running` STILL `running` with
   sddm active (`systemctl is-active sddm` → `active`).
4. Visual proof: spectacle screenshot pulled over SSH shows the Plasma
   desktop with traffic-light titlebars, bottom taskbar, and the Savant
   start menu open — pasted into the FID as evidence.
5. Restart proof: from the guest, `systemctl reboot -i` exits QEMU
   cleanly (launcher's `-no-reboot` turns guest reboot into exit);
   launcher log shows graceful close. Full relaunch behavior is Phase 4
   territory (deltas), not this FID.

### Loop 4 — Convergence (2026-09-14 folder audit; claims re-verified against code)

- **RED:** Claims re-audited against the working tree: R2 landed
  (`skeletons/etc/sddm.conf.d/10-savantos-autologin.conf` —
  DisplayServer=wayland, Relogin=true), R3 landed (91-savantos-desktop.preset
  `enable sddm.service` + the finalize.sh display-manager alias), R4 landed
  (finalize.sh pipewire.socket `--global enable` check), R6 landed
  (`skeletons/usr/share/konsole/Savant.colorscheme` + `Savant.profile`), the
  content assertion landed (assemble.sh presence probes). Two plan items
  SUPERSEDED: the Breeze ButtonsColor premise (refuted above) and the
  appletsrc factory drop-in (retired — the L&F layout script is the single
  panel source, per FID-2026-0913-001).
- **GREEN:** Both superseded items annotated in-place (2026-09-13); loop
  record added; status advanced.
- **AUDIT:** Every claim cites a file verified 2026-09-14 with grep counts
  (konsole profile=1, colorscheme Background=2, DisplayServer=1, Relogin=2,
  preset=1, alias=1, appletsrc-heredoc=0).
- **ADVERSARIAL:** "Exit criteria 3–5 (boot proof, visual proof, restart
  proof) never ran in THIS FID" — absorbed by FID-2026-0913-001's
  verification gates (boot proof + rendered proof owed on the next boot):
  a named exit criterion, not an open question.
- **CHANGE DELTA:** ~9%.
- **Convergence declared:** status → converged; remaining proofs assigned
  to FID-2026-0913-001.

## Status

**Superseded in part by FID-2026-0913-001** (desktop identity convergence —
the traffic-lights decoration re-scoped there after the ButtonsColor premise
above was refuted). The Phase-2 desktop otherwise landed in the builder
working tree 2026-09-12/13: the Plasma package set in `mkosi.conf`, SDDM
autologin + factory presets, the desktop factory in `finalize.sh`, and the
assemble.sh content assertion. Remaining closure evidence is absorbed by
FID-2026-0913-001's verification gates — **boot proof DELIVERED 2026-09-14**
(first-party image, unmodified launcher, system `running`, sddm `active`,
readiness ~12 s; see 0913-001's evidence section); the rendered titlebar-dot
proof is still owed there (portal/spectacle defect characterized).

## Lessons Learned

(written at closure)

## Resolution

- **Closed Date:** —
- **Fix Description:** —
- **Tests Added:** —
- **Verification Evidence:** —
- **Archived:** —
