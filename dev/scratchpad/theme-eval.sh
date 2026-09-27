#!/bin/bash
# Theme evaluation v4 for FID-2026-0915-006 D6 (dev-guest experiment).
# v3 post-mortem fixes: sudo on -Sy (v3 synced nothing), and the factory
# capture-path fix — xdg-desktop-portal-kde is missing from the image, so
# every Wayland screenshot request hangs; install it first and restart
# the portals. Everything else per v3 (bus env, per-package fallback,
# function reverts, detached execution).
set -uo pipefail
export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0
export DISPLAY=:0
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
OUT=/tmp/theme-eval
mkdir -p "$OUT"
notes="$OUT/notes.md"
rm -f "$OUT/DONE" "$OUT/FAILED"
: > "$notes"

log() { echo "$(date +%H:%M:%S) $*" | tee -a "$notes"; }

[ -S "$XDG_RUNTIME_DIR/bus" ] || { echo "no session bus" > "$OUT/FAILED"; exit 1; }

run() { # run <timeout-s> <cmd...>
  local t="$1"; shift
  timeout "$t" "$@" 2>&1
  local rc=$?
  [ $rc -eq 124 ] && log "TIMEOUT(${t}s): $*"
  return $rc
}

# -- consistent scene: chromium window on screen for every shot --------------
scene_label="theme-eval-scene"
start_scene() {
  if ! pgrep -f "$scene_label" >/dev/null; then
    rm -rf /tmp/theme-profile
    nohup chromium --no-first-run --no-default-browser-check \
      --disable-session-crashed-bubble --user-data-dir=/tmp/theme-profile \
      --start-maximized \
      "data:text/html,<body style='margin:0;background:%23101014;color:%23e8e8ec;font-family:sans-serif;display:flex;height:100vh;align-items:center;justify-content:center'><h1>SavantOS theme evaluation</h1></body>" \
      >/dev/null 2>&1 &
    disown
  fi
  sleep 4
}
stop_scene() { pkill -f "$scene_label" 2>/dev/null; sleep 1; true; }

scene() { # $1 = output png
  local f="$1" i
  for i in 1 2 3; do
    run 20 spectacle -b -n -o "$f" >/dev/null 2>&1
    if [ -s "$f" ]; then
      log "captured: $(basename "$f") ($(stat -c%s "$f") bytes)"
      return 0
    fi
    log "capture attempt $i failed — retrying"
    sleep 2
  done
  log "CAPTURE FAILED: $f"
  return 1
}

# -- state capture + revert functions (no string-quoting traps) --------------
icons_before=$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null)
[ -n "$icons_before" ] || icons_before=Papirus-Dark
gtk_before=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
[ -n "$gtk_before" ] || gtk_before="'Adwaita'"
kv_before="$HOME/.config/Kvantum/kvantum.kvconfig"
log "# Theme eval v3 $(date -Iseconds)"
log "before: gtk=$gtk_before icons=$icons_before kvantum=$([ -f "$kv_before" ] && echo set || echo none)"

revert_gtk()     { gsettings set org.gnome.desktop.interface gtk-theme "$gtk_before"; }
revert_kv()      { rm -f "$kv_before"; revert_gtk; }
revert_icons()   { kwriteconfig6 --file kdeglobals --group Icons --key Theme "$icons_before"; }

run_case() { # $1 label, $2 apply cmd, $3 revert-fn name
  local label="$1"
  log "## $label"
  log "apply: $2"
  run 60 bash -c "$2" >>"$notes" 2>&1
  sleep 2.5
  scene "$OUT/$label.png" || true
  log "revert: $3"
  "$3" >>"$notes" 2>&1
  sleep 1.2
}

log "## base (shipped identity)"
start_scene
scene "$OUT/base.png"

# --- installs from the pinned snapshot --------------------------------------
log "## sync + installs (mirrorlist pins the 2026-08-11 snapshot)"
run 300 sudo pacman -Sy >>"$notes" 2>&1 && log "-Sy: OK" || log "-Sy: FAILED"

# Factory finding: xdg-desktop-portal-kde is NOT in the image — the generic
# portal is active with no KDE backend, so every Wayland screenshot request
# (spectacle -b, portals) hangs. Install it FIRST, then restart portals.
log "portal backend (factory capture-path fix)"
run 1200 sudo pacman -S --noconfirm --needed xdg-desktop-portal-kde >>"$notes" 2>&1 \
  && log "  xdg-desktop-portal-kde: OK" || log "  xdg-desktop-portal-kde: FAILED"
run 30 systemctl --user restart xdg-desktop-portal.service >>"$notes" 2>&1 || true
sleep 2

PKGS="kvantum-theme-materia materia-kde materia-gtk-theme orchis-theme graphite tela-circle-icon-theme-black"
log "pacman -S --noconfirm $PKGS"
if run 1200 sudo pacman -S --noconfirm --needed $PKGS >>"$notes" 2>&1; then
  log "installs: OK"
else
  log "batch failed — per-package fallback"
  for p in $PKGS; do
    run 1200 sudo pacman -S --noconfirm --needed "$p" >>"$notes" 2>&1 \
      && log "  $p: OK" || log "  $p: FAILED"
  done
fi
log "installed check:"
for p in xdg-desktop-portal-kde $PKGS; do pacman -Q "$p" >>"$notes" 2>&1 || true; done

# --- cases -------------------------------------------------------------------
run_case "materia-kvantum-dark" \
  "kvantummanager --set MateriaDark; gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark'" \
  revert_kv

run_case "orchis-gtk-dark" \
  "gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-dark'" \
  revert_gtk

run_case "graphite-gtk-dark" \
  "gsettings set org.gnome.desktop.interface gtk-theme 'Graphite-dark'" \
  revert_gtk

run_case "tela-circle-icons" \
  "kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-circle-black" \
  revert_icons

# --- restore + verify --------------------------------------------------------
log "## revert verification"
log "gtk now: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
log "icons now: $(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null)"
log "kvantum: $([ -f "$kv_before" ] && echo set || echo none)"
stop_scene
log "## files"
ls -la "$OUT" >>"$notes" 2>&1
echo done > "$OUT/DONE"
echo "EVAL DONE: $(ls "$OUT"/*.png 2>/dev/null | wc -l) captures"
