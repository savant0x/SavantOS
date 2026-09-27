#!/bin/bash
# Host -> guest bridge diagnostics (FID-2026-0922-001 factory proof):
# text-crossing probe + guest bridge state + launcher clipboard log.
SSH="ssh -o ConnectTimeout=8 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 savant@127.0.0.1"
GE="export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"

echo "=== host sets text sentinel ==="
powershell -NoProfile -Command "Set-Clipboard -Value 'H2GTEXT-PROBE-20260927'"
sleep 3
echo "=== guest state ==="
$SSH "$GE; echo TYPES: \$(wl-paste --list-types 2>/dev/null | tr '\n' ' '); echo TEXT: \$(wl-paste 2>/dev/null | head -c 60)"
echo "=== guest bridge state dir ==="
$SSH "$GE; ls -la /run/user/1000/savantos-clipboard/ 2>/dev/null; echo last_content:; cat /run/user/1000/savantos-clipboard/last_content 2>/dev/null; echo; echo procs:; pgrep -a socat; pgrep -a wl-paste"
echo "=== guest service journal ==="
$SSH "$GE; journalctl --user -u savantos-clipboard -n 15 --no-pager 2>/dev/null | tail -12"
echo "=== launcher clipboard log ==="
grep "clipboard:" /c/Users/spenc/savantos-fp1/vm/shell.log | tail -8
