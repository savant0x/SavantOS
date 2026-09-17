#!/bin/bash
# One-shot: install the missing Qt-xcb dependency + collect close evidence.
# Runs INSIDE the guest as 'savant' (factory sudoers permit pacman).
set -uo pipefail
echo "=== install libxcb-cursor:"
sudo pacman -S --noconfirm libxcb-cursor 2>&1 | tail -2
echo "=== kate --version now (must not crash):"
kate --version 2>&1 | head -1
echo "=== fresh theme state (factory = breeze, no Tela):"
grep -hE "^Name=|CursorTheme|widgetStyle" ~/.config/kdeglobals ~/.config/kcminputrc 2>/dev/null | head -6
echo "=== cursor-ide procs still alive:"
pgrep -c -f /usr/bin/cursor
echo "=== done"
