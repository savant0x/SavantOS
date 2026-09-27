#!/bin/bash
# Capture the full desktop to the host share (mounted at /mnt/host).
# Uses spectacle's clean invocation that survived the CRLF-fix session.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1
f=/mnt/host/phase2-final.png
spectacle -b -n -o "$f" >/dev/null 2>&1
for i in 1 2 3 4 5 6 7 8; do [ -s "$f" ] && break; sleep 1; done
ls -la "$f"
