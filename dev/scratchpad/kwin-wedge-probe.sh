#!/bin/bash
# Read the wedged KWin's per-thread syscall states and kernel stacks.
pid=$(pgrep -x kwin_wayland | head -1)
echo "wedged kwin: $pid"
echo "=== main thread syscall:"
cat /proc/$pid/syscall 2>/dev/null
echo "=== per-thread syscalls:"
for t in /proc/$pid/task/*; do
  echo "$(basename $t): syscall=$(cat $t/syscall 2>/dev/null | awk '{print $1}') wchan=$(cat $t/wchan 2>/dev/null) name=$(cat $t/comm 2>/dev/null)"
done
echo "=== kernel stacks of threads stuck in real syscalls:"
for t in /proc/$pid/task/*; do
  s=$(cat $t/syscall 2>/dev/null | awk '{print $1}')
  case "$s" in
    *[0-9]*)
      echo "--- thread $(basename $t) ($(cat $t/comm 2>/dev/null)) syscall $s:"
      sudo cat "$t/stack" 2>/dev/null | head -10
      ;;
  esac
done
echo "=== dmesg tail (drm/venus/gpu errors):"
sudo dmesg 2>/dev/null | grep -iE "drm|venus|virtio_gpu|gpu|hung|stall" | tail -10
