#!/bin/sh
# Clipboard bridge (guest side) for two-way text sync with the Windows host.
# It waits for the active Wayland session and restarts both directions if the
# compositor is replaced. 10.0.2.2 is the host under QEMU user networking.
HOST=10.0.2.2
PUSH_PORT=4448
PULL_PORT=4449

XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
STATE=$XDG_RUNTIME_DIR/savantos-clipboard
export XDG_RUNTIME_DIR STATE
umask 077
mkdir -p "$STATE"

# wl-paste supplies the selected text on stdin. Keeping it in a file preserves
# trailing newlines and avoids a second clipboard read after the selection moves.
# --receive-image applies a host PNG frame (the launcher's "png:" prefix form,
# already stripped by the pull loop) with the same locking and sha state.
if [ "${1:-}" = --push ] || [ "${1:-}" = --receive ] || [ "${1:-}" = --receive-image ]; then
  outgoing=$(mktemp "$STATE/outgoing.XXXXXX") || exit 1
  trap 'rm -f "$outgoing"' EXIT
  if [ "${1:-}" = --receive-image ]; then
    # Mirrors maxClipboardImageBytes (16 MiB) on the host side.
    head -c 16777217 > "$outgoing" || exit 1
    size=$(wc -c < "$outgoing")
    [ "$size" -gt 8 ] && [ "$size" -le 16777216 ] || exit 0
    # PNG signature, mirroring the launcher's clipItem.allowed().
    [ "$(od -An -tx1 -N8 "$outgoing" | tr -d ' \n')" = "89504e470d0a1a0a" ] || exit 0
  else
    head -c 8388609 > "$outgoing" || exit 1
    size=$(wc -c < "$outgoing")
    [ "$size" -gt 0 ] && [ "$size" -le 8388608 ] || exit 0
  fi
  # Serialize both directions, including delivery. A completed push must not
  # overwrite the state of a newer host value received while it was sending.
  exec 9> "$STATE/lock"
  flock -x 9 || exit 1
  sha=$(sha256sum < "$outgoing" | cut -d' ' -f1)
  if [ "$1" = --receive ] || [ "$1" = --receive-image ]; then
    printf '%s\n' "$sha" > "$STATE/last_content"
    # wl-copy forks a clipboard owner. It must not inherit the lock descriptor.
    copy_ok=1
    case "$1" in
      --receive-image) wl-copy --type image/png < "$outgoing" 9>&- || copy_ok=0 ;;
      *)               wl-copy < "$outgoing" 9>&- || copy_ok=0 ;;
    esac
    if [ "$copy_ok" != 1 ]; then
      rm -f "$STATE/last_content"
      exit 1
    fi
    exit 0
  fi
  [ "$sha" = "$(cat "$STATE/last_content" 2>/dev/null)" ] && exit 0
  if { base64 -w0 < "$outgoing"; echo; } | timeout 10s socat -u - TCP:$HOST:$PUSH_PORT,connect-timeout=3 2>/dev/null 9>&-; then
    printf '%s\n' "$sha" > "$STATE/last_content"
  else
    exit 1
  fi
  exit 0
fi

find_wayland() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    export WAYLAND_DISPLAY
    return 0
  fi
  for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$socket" ] || continue
    WAYLAND_DISPLAY=${socket##*/}
    export WAYLAND_DISPLAY
    return 0
  done
  unset WAYLAND_DISPLAY
  return 1
}

PULL_PID=
cleanup() {
	pull_pid=$PULL_PID
	PULL_PID=
	if [ -n "$pull_pid" ]; then
		kill "$pull_pid" 2>/dev/null || true
		wait "$pull_pid" 2>/dev/null || true
	fi
}
stop() {
	cleanup
	exit 0
}
trap cleanup EXIT
trap stop INT TERM

while :; do
  if ! find_wayland; then
    sleep 2
    continue
  fi

  # host -> guest
  (
    while :; do
      # Keep socat directly connected to read. An extra pipe stage buffers
      # small clipboard payloads and makes ordinary text appear stuck.
      socat -u TCP:$HOST:$PULL_PORT,connect-timeout=3 - 2>/dev/null | while IFS= read -r line; do
        line=${line%"$(printf '\r')"}
        frame=--receive
        case "$line" in png:*) frame=--receive-image; line=${line#png:} ;; esac
        printf '%s' "$line" | base64 -d > "$STATE/incoming" 2>/dev/null || continue
        "$0" "$frame" < "$STATE/incoming" || break
      done
      sleep 2
    done
  ) &
  PULL_PID=$!

  # guest -> host. wl-paste exits when its Wayland connection disappears, so
  # the outer loop can discover the replacement socket and restart both sides.
  wl-paste --type text --watch "$0" --push || true

	cleanup
  sleep 2
done
