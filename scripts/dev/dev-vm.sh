#!/bin/bash
# SavantOS developer live-loop VM.
#
# One entry point for the host-side dev loop described in README.md beside
# this script: a dedicated data directory, a shared folder, SSH into the
# running guest, and a locally built launcher with live console logs.
#
# Subcommands: init | boot | shell | stop | help
# Overrides:   SAVANTOS_DEV_DIR, SAVANTOS_DEV_SHARE, SAVANTOS_DEV_PORT
#
# Everything this script creates lives outside the repo and outside any real
# SavantOS install; delete the two folders to remove it completely.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="${SAVANTOS_DEV_DIR:-$USERPROFILE/savantos-dev}"
SHARE_DIR="${SAVANTOS_DEV_SHARE:-$USERPROFILE/savantos-share}"
SSH_PORT="${SAVANTOS_DEV_PORT:-2222}"
GUEST_USER="savant"
QMP_PORT=4450
SEED_DEFAULT="$USERPROFILE/Downloads/savantos-e2e/data"
LAUNCHER_EXE="$REPO/app/SavantOS-dev.exe"

w() { cygpath -w "$1"; } # Windows path for launcher-boundary arguments

usage() {
  cat <<'EOF'
SavantOS dev live-loop VM

  dev-vm.sh init [--seed-from DIR]   create the dev data dir + shared folder
                                     (seed from an existing install's data/
                                     dir, skipping the 1.7 GB download; or
                                     leave empty and let first boot download
                                     the factory payload)
  dev-vm.sh boot [extra flags...]    build (if needed) and launch the dev
                                     launcher with -share, -ssh, -instant,
                                     -no-update; runs in the foreground with
                                     live logs. Extra flags pass through
                                     (e.g. boot -nogpu -fullscreen).
  dev-vm.sh shell [command...]       ssh into the running guest as 'savant'
  dev-vm.sh stop                     how to shut the VM down cleanly

Environment overrides:
  SAVANTOS_DEV_DIR    (default: %USERPROFILE%\savantos-dev)
  SAVANTOS_DEV_SHARE  (default: %USERPROFILE%\savantos-share)
  SAVANTOS_DEV_PORT   (default: 2222)

Typical loop:  dev-vm.sh init && dev-vm.sh boot     (terminal 1)
               dev-vm.sh shell                      (terminal 2)
Edit files in the share folder on Windows; they appear in the guest at
/mnt/host instantly.
EOF
}

need_launcher() {
  if [[ ! -f "$LAUNCHER_EXE" ]]; then
    echo "[dev-vm] building dev launcher (console build, live logs)..."
    (cd "$REPO/app" && go build -o SavantOS-dev.exe .)
  fi
}

guest_up() {
  ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new \
    -p "$SSH_PORT" "$GUEST_USER@127.0.0.1" true 2>/dev/null
}

cmd_init() {
  local seed=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --seed-from)
        [[ $# -ge 2 ]] || { echo "error: --seed-from needs a directory" >&2; exit 2; }
        seed="$2"; shift 2 ;;
      *) echo "error: unknown init option: $1" >&2; exit 2 ;;
    esac
  done
  if [[ -z "$seed" && -d "$SEED_DEFAULT" ]]; then seed="$SEED_DEFAULT"; fi

  mkdir -p "$SHARE_DIR"
  if [[ ! -f "$SHARE_DIR/hello.sh" ]]; then
    # LF endings only: this file runs under bash inside the guest.
    printf '#!/bin/bash\n# Dev smoke: run inside the guest with: bash /mnt/host/hello.sh\necho "dev share works: $(uname -n) $(date -Is)" > /mnt/host/from-guest.txt\n' \
      > "$SHARE_DIR/hello.sh"
    echo "[dev-vm] wrote $SHARE_DIR/hello.sh (guest->host round-trip smoke)"
  fi

  if [[ -n "$seed" ]]; then
    if [[ ! -d "$seed" ]]; then
      echo "error: seed source not a directory: $seed" >&2; exit 2
    fi
    echo "[dev-vm] seeding $DEV_DIR from $seed (sparse copy; nothing downloads)"
    local tool
    tool="$(mktemp -u /tmp/sparsetool-XXXXXX).exe"
    # sparsetool is its own Go module (own go.mod) — build from inside it.
    (cd "$REPO/scripts/vmtest/sparsetool" && go build -o "$tool" .)
    "$tool" copy "$(w "$seed")" "$(w "$DEV_DIR")"
    rm -f "$tool"
    echo "[dev-vm] seeded. Receipts copied byte-for-byte, so the launcher will"
    echo "[dev-vm] verify the local payload instead of re-downloading it."
  else
    echo "[dev-vm] no seed source found; first boot downloads the factory"
    echo "[dev-vm] payload (~1.7 GB) and digest-verifies it automatically."
    mkdir -p "$DEV_DIR"
  fi
  echo "[dev-vm] init complete. Next: scripts/dev/dev-vm.sh boot"
}

cmd_boot() {
  need_launcher
  if netstat -an | grep -q ":${QMP_PORT} .*LISTENING"; then
    echo "[dev-vm] WARNING: port ${QMP_PORT} (QMP) is busy — another SavantOS" \
         "instance may be running; stop it first to avoid two VMs fighting" \
         "over the control plane." >&2
  fi
  echo "[dev-vm] data dir:  $DEV_DIR"
  echo "[dev-vm] share:     $SHARE_DIR  (guest: /mnt/host)"
  echo "[dev-vm] ssh:       port $SSH_PORT (user: $GUEST_USER)"
  echo "[dev-vm] launching; from another terminal: scripts/dev/dev-vm.sh shell"
  echo "[dev-vm] stop by closing the window/tray icon (Ctrl+C is abrupt-kill)"
  "$LAUNCHER_EXE" \
    -dir "$(w "$DEV_DIR")" \
    -share "$(w "$SHARE_DIR")" \
    -ssh "$SSH_PORT" \
    -instant -no-update "$@"
}

cmd_shell() {
  if ! guest_up; then
    echo "error: no ssh on 127.0.0.1:${SSH_PORT} — boot first:" \
         "scripts/dev/dev-vm.sh boot" >&2
    exit 1
  fi
  if [[ $# -gt 0 ]]; then
    ssh -o StrictHostKeyChecking=accept-new -p "$SSH_PORT" \
      "$GUEST_USER@127.0.0.1" "$@"
  else
    exec ssh -o StrictHostKeyChecking=accept-new -p "$SSH_PORT" \
      "$GUEST_USER@127.0.0.1"
  fi
}

cmd_stop() {
  echo "Clean shutdown: close the SavantOS window or quit from the tray icon;"
  echo "the launcher powers the guest down and finishes cleanup itself."
  echo
  echo "Full removal of the dev environment:"
  echo "  1. shut down as above"
  echo "  2. dev-vm.sh shell -- exit any sessions"
  echo "  3. \"$LAUNCHER_EXE\" -dir \"$(w "$DEV_DIR")\" -uninstall"
  echo "     (removes shortcuts/Apps&features entry + the data folder)"
  echo "  4. delete the share folder:  rm -rf \"$(w "$SHARE_DIR")\""
}

case "${1:-help}" in
  init)  shift; cmd_init "$@" ;;
  boot)  shift; cmd_boot "$@" ;;
  shell) shift; cmd_shell "$@" ;;
  stop)  cmd_stop ;;
  help|-h|--help) usage ;;
  *) echo "error: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
