#!/bin/bash
# Runtime install of the bridge deps (factory criterion: runtime pacman -S).
for i in 1 2 3 4; do
  sudo -n pacman -Sy --noconfirm --needed socat wl-clipboard >/tmp/pac.log 2>&1
  if pacman -Q socat wl-clipboard >/dev/null 2>&1; then echo "INSTALLED (try $i)"; break; fi
  sleep 5
done
pacman -Q socat wl-clipboard 2>&1
systemctl --user restart savantos-clipboard.service
sleep 4
systemctl --user is-active savantos-clipboard.service
pgrep -a wl-paste | head -2
pgrep -a socat | head -3
echo READY
