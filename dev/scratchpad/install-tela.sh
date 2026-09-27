#!/bin/bash
# One-shot: install tela-circle-icon-theme-black on the dev guest.
# Installs ride the factory sudoers grant (wheel NOPASSWD,
# guest-image/finalize.sh:33) inside the disposable dev VM.
set -uo pipefail
timeout 500 sudo pacman -S --noconfirm --needed tela-circle-icon-theme-black 2>&1 | tail -2
ls /usr/share/icons/ | grep -i tela | head -3
