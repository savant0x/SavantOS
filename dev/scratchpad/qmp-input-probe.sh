#!/bin/bash
# Input-path discriminator: capture virtio-tablet events during a QMP click,
# then map the input device tree and who holds the evdev nodes.
set -uo pipefail
nohup bash -c "sudo timeout 10 cat /dev/input/event3 > /tmp/ev2.raw 2>/dev/null" >/dev/null 2>&1 &
echo capture2-started
sleep 8
echo "raw during QMP click: $(stat -c %s /tmp/ev2.raw 2>/dev/null) bytes"
echo "=== input devices:"
grep -E "N: Name|H: Handlers" /proc/bus/input/devices | head -14
echo "=== evdev holders:"
for f in /dev/input/event*; do
  o=$(sudo fuser "$f" 2>/dev/null | tr -d " ")
  echo "$f: holder-pids=${o:-none}"
done
echo "=== libinput seat assignments:"
grep -E "N: Name|H: Handlers" /proc/bus/input/devices | paste - - | head -8
