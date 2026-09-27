#!/bin/bash
# Deploy the Savant traffic-lights QML decoration into the RUNNING guest.
# Runs INSIDE the guest over SSH; the trial account's passwordless sudo is
# guest-internal dev policy (docs/DEVELOPING.md), not a host operation.
set -euo pipefail
sudo tar -C /usr/share/kwin/decorations -xzf /mnt/host/savant-deco.tgz
sudo find /usr/share/kwin/decorations/savant-traffic-lights -type f -exec sed -i 's/\r$//' {} +
export XDG_RUNTIME_DIR=/run/user/$(id -u)
echo "=== deployed files ==="
find /usr/share/kwin/decorations/savant-traffic-lights -type f | sort
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key Theme savant-traffic-lights
echo "theme=$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key Theme)"
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
sleep 4
echo "=== kwin journal verdict ==="
journalctl --user -u plasma-kwin_wayland.service --since "-1 min" --no-pager | grep -iE "QML Decoration|savant|error" | tail -4 || echo "no decoration errors"
