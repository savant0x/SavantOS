#!/bin/bash
# First-login identity activation (runs as the desktop user, inside the
# Plasma session via savantos-identity.service).
#
# 1. Apply the Savant Look & Feel through Plasma's supported path — this is
#    what makes the taskbar layout (the L&F layout script is the single
#    panel source), wallpaper, and color scheme survive first-run config
#    migration.
# 2. Re-assert the keys plasma-apply-lookandfeel drops. Verified live
#    2026-09-13: the L&F apply persists the wallpaper Image= key but leaves
#    kwinrc's org.kde.kdecoration2 keys unset (KWin falls back to breeze)
#    and does not land kdeglobals widgetStyle/Icons, so they are rewritten
#    here and KConfigWatcher/DBus reconfigure engages them.
# 3. Ensure the Kvantum theme selection exists (skel plants it for new
#    accounts; this guards accounts created before the plant).
set -euo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

plasma-apply-lookandfeel -a savant.desktop || \
    echo "identity: L&F apply returned $? (continuing to key re-assert)" >&2

# Widget style + icon theme (Kvantum engine, Papirus icons).
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kvantum
kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark

# QML traffic-lights decoration (loads via the aurorae bridge:
# Library=org.kde.kwin.aurorae + Theme=<KPackage id>).
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme savant-traffic-lights
# KWin letter codes (I=minimize A=maximize X=close); the QML decoration
# paints its dot row anchored to the RIGHT edge (min, max, close — Windows
# order), so nothing on the left and IAX on the right. Name strings
# silently break these keys (verified live 2026-09-12).
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft ""
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight IAX

# Kvantum theme selection (idempotent guard; skel plants it for new
# accounts).
mkdir -p "$HOME/.config/Kvantum"
printf '[General]\ntheme=Savant\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"

# Appliance power semantics (FID-2026-0914-003): re-assert the factory
# power-button seed for accounts that predate the skel plant (finalize.sh
# copies skel only at build time). PowerDevil's default power-button action
# opens its on-screen power dialog, whose block inhibitor on
# handle-power-key swallows the launcher's QMP ACPI powerdown (full
# evidence chain in finalize.sh). PowerDevil watches this file via
# KConfigWatcher, so the value lands live. 8 = Shutdown in the pinned
# 6.7.4 enum; VMs report AC power only, so the AC profile governs.
kwriteconfig6 --file powermanagementprofilesrc --group AC --group HandleButtonEvents --key powerButtonAction 8

# Nudge KWin to load the decoration now (KConfigWatcher usually beats us,
# but an explicit reconfigure makes first-boot deterministic).
dbus-send --session --dest=org.kde.KWin --type=method_call /KWin org.kde.KWin.reconfigure 2>/dev/null || true