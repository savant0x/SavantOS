#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
builder_dir="$repo_root/guest-image"
output=""
contract_only=0

while (($#)); do
  case "$1" in
    --output)
      output=${2:-}
      shift 2
      ;;
    --contract-only)
      contract_only=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ((contract_only == 0)) && [[ -z $output ]]; then
  echo "Usage: $0 --output DIR [--contract-only]" >&2
  exit 2
fi

# --- contract gate for the builder tree (cheap, no image build; CI runs this
# on every push, the full dual-build mkosi gate runs at release time —
# FID-2026-0914-002 step 2). The old gate's git-am contract test is replaced;
# the script's interface survives (FID-2026-0912-001 keep-list).

# 1. Snapshot-lock consistency: mkosi.conf AND sandbox/pacman.conf must pin
#    the same Arch snapshot as the lock file — a silent pin drift ships a
#    guest from a different archive than the one that was tested.
"$builder_dir/check-snapshot-lock.sh" "$builder_dir/snapshot.lock.json" "$builder_dir/mkosi.conf"

# 2. Builder scripts must parse (a syntax-broken gate is a gate that fails).
bash -n "$builder_dir/build.sh" "$builder_dir/assemble.sh" \
  "$builder_dir/check-snapshot-lock.sh"

# 3. CRLF gate: no KConfig/unit/theme file may carry CR (KConfig mis-parses
#    '[Group]\r' — verified 2026-09-13, the whole L&F layer no-op'd on CRLF).
#    Byte-exact scan, not grep: CR is a byte question and grep's binary/text
#    heuristics proved irreproducible in this environment (2026-09-15: the
#    same tree alternately reported 0 and 34 CR hits between runs while a
#    full Python byte scan showed 0). Byte semantics are strictly stronger
#    than grep -I.
PY=$(command -v python3 || command -v python)
BUILDER_DIR_ABS="$builder_dir" "$PY" - <<'PYEOF'
import os, sys
bad = []
root = os.path.join(os.environ["BUILDER_DIR_ABS"], "skeletons")
for dirpath, _, files in os.walk(root):
    for name in files:
        if name.endswith(".png"):
            continue
        p = os.path.join(dirpath, name)
        try:
            with open(p, "rb") as f:
                if b"\r" in f.read():
                    bad.append(p)
        except OSError:
            pass
if bad:
    print("CR bytes found in:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
PYEOF

# 4. Skeleton presence: the load-bearing files must ship in the skeleton
#    tree before any build can embed them (skeleton-level mirror of the
#    assemble.sh image probes).
for probe in \
    usr/share/kwin/decorations/savant-traffic-lights/contents/ui/main.qml \
    usr/share/plasma/look-and-feel/savant.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
    usr/share/Kvantum/Savant/Savant.kvconfig \
    usr/share/color-schemes/Savant.colors \
    usr/share/konsole/Savant.profile \
    etc/systemd/system/savantos-keyring-init.service \
    etc/sddm.conf.d/10-savantos-autologin.conf \
    usr/share/wallpapers/savant/contents/images/savant-traffic-lights.png \
    usr/lib/systemd/user/savant-core.service \
    usr/lib/systemd/user-preset/91-savantos-desktop.preset; do
  [[ -f "$builder_dir/skeletons/$probe" ]] || {
    echo "skeleton content assertion FAILED — $probe missing" >&2
    exit 1
  }
done

if ((contract_only)); then
  # Phase 3 (FID-2026-0915-005): the guest daemon must compile and its
  # safety-law tests must pass on every CI push — the same bar app/ meets.
  ( cd "$repo_root/guest-daemon/savant-core" && \
      go vet ./... && go test ./... ) \
      || { echo "savant-core gate FAILED" >&2; exit 1; }
  exit 0
fi

# --- full build: mkosi ×2 inside an Arch container (dual-build determinism
# gate) → six contract files + SHA256SUMS. RELEASE_NAME/VERSION flow through
# from the environment when set; docker (or podman) on the runner, no root
# on the host.
( cd "$builder_dir" && ./build.sh )

# The builder publishes the payload in guest-image/out/contract; move the
# finished artifacts to the requested output directory (mv, not cp: the
# uncompressed rootfs is 6 GiB).
[[ -d "$builder_dir/out/contract" ]] || {
  echo "builder produced no contract payload in $builder_dir/out/contract" >&2
  exit 1
}
mkdir -p "$output"
mv "$builder_dir/out/contract/"* "$output"/
# Container-root writes in the /work bind stay root-owned on the host; the
# later pipeline steps (SHA256SUMS append, upload) run as the runner user.
sudo chown -R -- "$(id -u):$(id -g)" "$output"
[[ -f "$output/rootfs.ext4" ]] || {
  echo "builder produced no rootfs.ext4 in $output" >&2
  exit 1
}