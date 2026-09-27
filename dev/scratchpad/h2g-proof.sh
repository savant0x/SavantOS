#!/bin/bash
# Host -> guest image proof for FID-2026-0922-001 factory out-of-box.
# Usage: h2g-proof.sh [image|png]
#   image : classic app copy (CF_DIB) - bridge re-encodes DIB to PNG.
#   png   : browser-style copy (image + registered "PNG") - byte-exact.
SSH="ssh -o ConnectTimeout=8 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 2222 savant@127.0.0.1"
GE="export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0"
FIX='C:\Users\spenc\dev\SavantOS\dev\scratchpad\out\savant\backgrounds\savant.png'
FIXUNIX=dev/scratchpad/out/savant/backgrounds/savant.png
MODE=${1:-image}
case $MODE in
  image) GUESTOUT=/tmp/h2g-a.png ;;
  png)   GUESTOUT=/tmp/h2g-b.png ;;
  *) echo "usage: $0 [image|png]"; exit 2 ;;
esac

echo "=== fixture ($MODE) ==="
sha256sum "$FIXUNIX"
wc -c < "$FIXUNIX"
echo "=== guest baseline ==="
$SSH "$GE; wl-paste --list-types 2>/dev/null | tr '\n' ' '; echo"
echo "=== set clipboard ($MODE) ==="
powershell -NoProfile -ExecutionPolicy Bypass -File dev/scratchpad/set-clip-image.ps1 -Path "$FIX" -Mode "$MODE"
echo "=== poll guest ==="
for i in $(seq 1 30); do
  TYPES=$($SSH "$GE; wl-paste --list-types 2>/dev/null | tr '\n' ' '" 2>/dev/null)
  echo "poll $i: $TYPES"
  if echo "$TYPES" | grep -q image/png; then echo IMAGE-PRESENT; break; fi
  sleep 1
done
echo "=== guest image ($GUESTOUT) ==="
$SSH "$GE; wl-paste --type image/png > $GUESTOUT 2>/dev/null; sha256sum $GUESTOUT; wc -c < $GUESTOUT; file $GUESTOUT"
echo "=== launcher clipboard log ==="
grep "clipboard:" /c/Users/spenc/savantos-fp1/vm/shell.log | tail -6
