#!/bin/bash
# mkosi PostInstallationScript, run inside mkosi's sandbox. mkosi 27 mounts
# the image tree at $BUILDROOT — the sandbox's own / is read-only staging —
# so every mutation of the image happens through a chroot into it. The chroot
# needs /proc, /sys and /dev mounted (mkinitcpio hard-fails without /proc:
# "==> ERROR: /proc must be mounted!").
# Installs the factory identity: the savant account, enabled units, host
# identity, and the factory initramfs.
set -euo pipefail

echo "[finalize] savantos factory image configuration (BUILDROOT=$BUILDROOT)"
[[ -d $BUILDROOT/etc ]] || { echo "finalize: BUILDROOT not mounted" >&2; exit 1; }

# The configuration payload as a script INSIDE the tree, so it runs the same
# way regardless of which chroot mechanism executes it (no stdin threading).
# Not under /tmp: the sandbox tmpfs-mounts /tmp, hiding anything planted
# there from the chroot (proved empirically 2026-09-12).
payload=/usr/local/lib/savantos/finalize-payload.sh
cat > "$BUILDROOT$payload" <<'CHROOT'
set -eux

# Skeletons arrive via mkosi SkeletonTrees=skeletons:/ (copied into the image
# tree before packages install); fix the exec bits the copy normalizes away.
chmod 755 /usr/local/lib/savantos/guest-ready /usr/local/lib/savantos/request-sshd \
    /usr/lib/savantos/identity-apply.sh

# --- factory account (F6): single desktop user, passwordless sudo for the
# dev/admin path until the desktop phase brings the real policy.
if ! id savant >/dev/null 2>&1; then
    useradd -m -G wheel -s /bin/bash savant
fi
printf 'savant:savant\n' | chpasswd
printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/90-savant-wheel
chmod 440 /etc/sudoers.d/90-savant-wheel

# --- autologin on tty1 so the boot proof shows a usable console without a
# display manager (the desktop phase adds SDDM).
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'UNIT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-f savant' --noclear --autologin savant %I $TERM
UNIT

# --- hostname + hosts
printf 'savantos\n' > /etc/hostname
cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
::1 localhost
HOSTS

# --- locale (C is honest for Phase 1; the desktop phase carries the host
# locale sync from the integration set)
printf 'LANG=C.UTF-8\n' > /etc/locale.conf

# --- deterministic UTC clock at first boot. systemd-firstboot is disabled
# on the kernel command line (systemd.firstboot=0), but /etc/localtime must
# still exist: without it the RTC stays UTC and the firstboot timezone
# question was the Phase 1 boot blocker (interactive prompt on the serial
# console, hanging sysinit.target before sshd). The Phase 2 host-locale
# service replaces this with the Windows zone per boot.
ln -sfn /usr/share/zoneinfo/UTC /etc/localtime

# --- unit enablement is NOT done with hand-made wants symlinks: mkosi runs
# `systemctl preset-all` AFTER this script and strips them (observed
# 2026-09-12). Enablement is declared in the factory preset policy
# (skeletons/usr/lib/systemd/system-preset/90-savantos-factory.preset),
# which preset-all applies; the growfs-root [Install] comes from its drop-in.

# --- sshd host keys: NOT generated at build — random keys per build broke
# the dual-build determinism gate. The sshd unit's ExecStartPre generates
# them at first boot (idempotent), where /etc rides the launcher's
# persistent data disk and survives updates.

# --- /etc/shadow determinism: chpasswd hashes with a random salt per build
# (gate breaker). Set the hash directly with a FIXED salt instead (dev
# password 'savant'; the production hardening pass replaces this).
savant_hash=$(openssl passwd -6 -salt savantosfixedsalt 'savant')
usermod -p "$savant_hash" savant

# ===================== Phase 2: desktop factory (FID-2026-0912-002) =====

# --- display-manager alias (R3): preset enables sddm.service, but the
# canonical alias the logind/preset chain resolves must exist too. Both
# mechanisms are idempotent.
ln -sfn /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service

# --- Savant start icon: traffic-lights trio (green/amber/red) on void.
# Ships via SkeletonTrees (usr/share/icons/hicolor/scalable/apps/) so the
# kickoff button carries the Savant identity instead of the KDE logo. The
# former in-payload heredoc wrote through $BUILDROOT inside the chroot,
# where that variable does not exist (unbound under set -u; a stray nested
# path when inherited through the environment).
# --- traffic-lights identity via the Savant Look & Feel package. The L&F
# is the mechanism Plasma itself applies on first login (defaults file:,
# color scheme, Kvantum widgets, the QML traffic-lights decoration, Papirus
# icons, the savant wallpaper), so first-run config migration carries the
# identity instead of stripping hand-written keys (observed 2026-09-12: a
# bare [Wallpaper] Image= line in the appletsrc was dropped by migration).
mkdir -p /etc/skel/.config
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group KDE --key LookAndFeelPackage savant.desktop
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key ColorScheme Savant
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group Icons --key Theme Papirus-Dark
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group KDE --key widgetStyle kvantum
kwriteconfig6 --file /etc/skel/.config/kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file /etc/skel/.config/kwinrc --group org.kde.kdecoration2 --key theme savant-traffic-lights
# Button layout uses KWin letter codes (I=minimize A=maximize X=close); name
# strings silently break the key (verified live 2026-09-12). The QML
# decoration paints its dot row anchored to the RIGHT edge (min, max, close
# left-to-right — Windows order), so kwinrc must agree: nothing on the left,
# IAX on the right (FID-2026-0913-001: dots top-right).
kwriteconfig6 --file /etc/skel/.config/kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft ""
kwriteconfig6 --file /etc/skel/.config/kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight IAX
kwriteconfig6 --file /etc/skel/.config/plasmarc --group theme --key name breeze-dark
# Konsole default profile (Savant colors are system-wide in /usr/share/konsole).
kwriteconfig6 --file /etc/skel/.config/konsolerc --group "Desktop Entry" --key DefaultProfile Savant.profile
# Appliance power semantics (FID-2026-0914-003, Option B): powerdevil stays
# in the package set, but its power-button action is factory-seeded to a
# clean shutdown. Its default opens powerdevil's on-screen power dialog,
# and the dialog's block inhibitor on handle-power-key swallows the
# launcher's QMP ACPI powerdown — the host close button could never power
# the guest off (proved live 2026-09-14: three POWERDOWN events ignored
# with the inhibitor present, the identical event shutting the guest down
# seconds after the inhibitor was released). Key path
# powermanagementprofilesrc -> [AC][HandleButtonEvents] -> powerButtonAction
# and value 8 = PowerDevil::PowerButtonAction::Shutdown are verified
# against the pinned 6.7.4 source (daemon/powerdevilcore.cpp). VMs report
# AC power only (no battery device in the launcher's QEMU flags), so the
# AC profile is the one that governs.
kwriteconfig6 --file /etc/skel/.config/powermanagementprofilesrc --group AC --group HandleButtonEvents --key powerButtonAction 8
# Cursor theme stays breeze (breeze_cursors); icons come from Papirus-Dark;
# fonts are Noto.
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key font "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key fixed "Hack,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key menuFont "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key smallestReadableFont "Noto Sans,8,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group General --key toolBarFont "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig6 --file /etc/skel/.config/kdeglobals --group WM --key activeFont "Noto Sans,10,-1,5,50,0,0,0,0,0"

# Apply the factory identity to the existing account too (useradd -m ran
# before skel gained these files).
cp -a /etc/skel/.config /home/savant/ 2>/dev/null || true
# NOTE: no chown here — this script runs inside mkosi's id-mapped sandbox,
# where uid 1000 does not exist (chown fails with EINVAL). assemble.sh
# reasserts the account's ownership over the whole /home/savant tree after
# postinst, outside the sandbox.

# --- per-user Plasma shell layout: RETIRED as a panel source
# (FID-2026-0913-001). The hand-rolled appletsrc raced the L&F layout
# script (two taskbars; the edit-mode band) and carried form-factor values
# the shell mis-parses (location=0 is Desktop, not a panel edge). The L&F
# layout script (usr/share/plasma/look-and-feel/savant.desktop/contents/
# layouts/) is the single panel source; identity-apply.sh runs
# plasma-apply-lookandfeel on every login, so the panel converges to the
# script's shape. The desktop icons below are folder-view content,
# independent of appletsrc.
# --- desktop icons: the desktop containment shows ~/Desktop (folder-view
# convention). Ship the core four as factory icons: Files, Terminal,
# Settings, and the host share (mounted at /mnt/host by
# savantos-host-share.service).
install -d /home/savant/Desktop
desktop=/home/savant/Desktop
install -d /etc/skel/Desktop
cat > "$desktop/org.kde.dolphin.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Files
GenericName=File Manager
Icon=system-file-manager
Exec=dolphin
Categories=Qt;KDE;System;FileManager;
DESKTOP
cat > "$desktop/org.kde.konsole.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Terminal
GenericName=Terminal
Icon=utilities-terminal
Exec=konsole
Categories=Qt;KDE;System;TerminalEmulator;
DESKTOP
cat > "$desktop/org.kde.systemsettings.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Settings
GenericName=System Settings
Icon=preferences-system
Exec=systemsettings
Categories=Qt;KDE;Settings;
DESKTOP
cat > "$desktop/savantos-host-share.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Host Share
GenericName=Shared folder from the host
Icon=folder-network
Exec=dolphin /mnt/host
Categories=Qt;KDE;System;
DESKTOP
chmod 755 "$desktop" "$desktop"/*.desktop
# Mirror into skel so any future account gets the same factory desktop.
cp -a "$desktop"/. /etc/skel/Desktop/

# --- factory wallpaper: deterministic traffic-lights PNG (generator in
# the builder tree; output copied into the tree pre-assembly).
# installed by assemble-time copy — see guest-image/Makefile-less flow in
# build.sh (wallpapers/savant/contents/images/).

# --- restart/shutdown plumbing: polkit agent autostarts with the session
# (shipped XDG autostart), powerdevil ships its own plasmoid. Nothing to
# factory-set beyond the wheel policy already granted in Phase 1; logind
# defaults allow wheel to poweroff/reboot interactively.

# --- user services for audio: pipewire/wireplumber are default-enabled in
# Arch's shipped user preset; verify rather than hope (R4).
if ! ls /usr/lib/systemd/user/sockets.target.wants/pipewire.socket >/dev/null 2>&1; then
    systemctl --root=/ enable --global pipewire.socket wireplumber.service 2>/dev/null || true
fi

# --- factory initramfs with the virtio-only drop-in
mkinitcpio -p linux-zen


# --- the build metadata lives at a stable path for the emitter and for
# in-guest inspection
mkdir -p /usr/share/savantos
printf 'phase2\n' > /usr/share/savantos/image-stream

# --- nondeterminism hygiene: caches regenerated by the guest at boot.
# ldconfig aux-cache varies with build-time filesystem ordering; the boot
# ldconfig rebuilds it. /etc/shadow- is shadow's automatic backup, holding
# the pre-usermod random-salt hash; the fixed-salt hash above is the last
# account mutation, then the backup is refreshed to match.
# NOTE: mkosi's kernel-modules initrd (/boot/arch) is created AFTER this
# script runs, so it cannot be removed here — assemble.sh removes it.
rm -f /var/cache/ldconfig/aux-cache
# Icon caches from the pacman gtk-update-icon-cache hook embed directory
# mtimes taken at install wall-clock — build-to-build variance that breaks
# the dual-build digest gate. Caches are pure accelerators (apps scan dirs
# without them); absent = deterministic.
find /usr/share/icons -maxdepth 2 -name 'icon-theme.cache' -delete
rm -f /etc/shadow-
cp /etc/shadow /etc/shadow-
CHROOT
chmod 755 "$BUILDROOT$payload"

# Chroot with the API VFS mounted. mkosi-chroot is mkosi's own helper: it
# chroots into the image tree by itself (BUILDROOT is baked into it) and runs
# the given command inside. Probed empirically rather than assumed; if it is
# absent or refuses, fall back to manual mounts in a private user+mount
# namespace.
if mkosi-chroot /bin/true >/dev/null 2>&1; then
    echo "[finalize] chroot via mkosi-chroot"
    mkosi-chroot /bin/bash "$payload"
else
    echo "[finalize] mkosi-chroot unusable; unshare fallback"
    unshare --user --map-root-user --mount /bin/bash -eux <<FALLBACK
mount -t proc proc '$BUILDROOT/proc'
mount --rbind /sys '$BUILDROOT/sys'
mount --rbind /dev '$BUILDROOT/dev'
chroot '$BUILDROOT' /bin/bash '$payload'
umount -R '$BUILDROOT/dev' '$BUILDROOT/sys' '$BUILDROOT/proc'
FALLBACK
fi

rm -f "$BUILDROOT$payload"
echo "[finalize] done"
