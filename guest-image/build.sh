#!/bin/bash
# Build the SavantOS Phase 1 factory payload:
#   1. snapshot-lock consistency check
#   2. mkosi directory build inside an Arch container (rootless package install)
#   3. assemble.sh inside the same container (mke2fs -d, six contract files)
#   4. dual-build determinism gate: assemble twice, digests must match
#   5. SHA256SUMS emission for the local release base
#
# Host prerequisites: docker (or podman) and bash. No root on the host.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
out="$here/out"
# Host-side steps below use guest-image-relative paths (build-a/contract, …);
# anchor the cwd so the script works from any directory.
cd "$here"
container_bin=${CONTAINER_BIN:-docker}
image=archlinux:base-devel
release_name=${RELEASE_NAME:-local/phase1}
version=${VERSION:-0.0.0-phase1}

"$here/check-snapshot-lock.sh" "$here/snapshot.lock.json" "$here/mkosi.conf"

mkdir -p "$out"

# --- Phase 3: build savant-core into the skeleton tree (FID-2026-0915-005
# m2). Runs before BOTH assemblies so A and B embed the identical binary;
# the build flags pin CGO off (pure-Go, static) and trimpath (no host paths
# in the binary) so the two assemblies verify byte-identical.
build_savant_core() {
    local gocache="$(pwd)/.gocache"
    mkdir -p "$gocache" "skeletons/usr/bin"
    ( cd guest-daemon/savant-core && \
        GOCACHE="$gocache" GOFLAGS=-mod=mod CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build -trimpath -ldflags "-s -w" -o "../../skeletons/usr/bin/savant-core" . ) \
        || { echo "[build] FATAL: savant-core go build failed" >&2; exit 1; }
    echo "[build] savant-core built: $(sha256sum skeletons/usr/bin/savant-core | cut -c1-16)"
}
build_savant_core

run_build() {
    local tag=$1
    # MSYS_NO_PATHCONV: Git Bash rewrites POSIX paths in argv to Windows paths
    # (documented in the patch-train contract runs — the /work mount must
    # reach Docker verbatim).
    # seccomp/apparmor unconfined: mkosi's rootless builds unshare a user
    # namespace, which Docker's default seccomp profile refuses inside the
    # container. The container itself is still throwaway and unprivileged.
    #
    # /mkosi-ws is a NAMED VOLUME, not a host bind: mkosi's sandbox runs
    # systemd-hwdb against a workspace-tree bind (root -> /buildroot), and
    # hwdb's temp-file+rename write pattern fails with ENOENT on Docker
    # Desktop's virtiofs host mounts (plain creates like depmod's succeed —
    # proved empirically 2026-09-12). A named volume lives on the Docker VM's
    # native fs with full POSIX semantics, and the 683M package cache reads
    # faster. Named volumes persist across runs, so the cache survives.
    # The whole /mkosi-ws side (workspace AND output) must live on that ONE
    # volume: mkosi's final step renames the built tree from its workspace
    # into the output dir, and a rename across the volume/bind boundary
    # degrades to a copy that breaks on duplicate entries (87 'File exists'
    # collisions, proved 2026-09-12). /work stays a host bind for sources in
    # and contract files out only.
    "$container_bin" volume create "guest-image-ws-$tag" >/dev/null
    "$container_bin" volume create guest-image-cache >/dev/null
    MSYS_NO_PATHCONV=1 "$container_bin" run --rm \
        --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
        -v "$(cygpath -w "$here" 2>/dev/null || echo "$here"):/work:rw" \
        -v "guest-image-ws-$tag:/mkosi-ws:rw" \
        -v "guest-image-cache:/mkosi-cache:rw" \
        -e RELEASE_NAME="$release_name" -e VERSION="$version" \
        -w /work "$image" /bin/bash -ceu '
        pacman -Sy --noconfirm --needed mkosi e2fsprogs zstd python-pefile python-pillow go
        useradd -m builder 2>/dev/null || true
        export HOME=/home/builder
        rm -rf /mkosi-ws/'"$tag"' /work/build-'"$tag"'
        # Phase 3 (FID-2026-0915-005): savant-core is cross-compiled on the
        # HOST (before the container starts) into skeletons/usr/bin, so it
        # rides SkeletonTrees into the image like every other factory file.
        # GOFLAGS=-mod=mod with GOMODCACHE on the repo tree: the container
        # has no network beyond pacman, so the build is network-free.
        # Phase 2: the factory wallpaper is generated deterministically
        # before the build so it lands in the skeleton tree and rides
        # SkeletonTrees into the image (FID-2026-0912-002). v2 generates on
        # the HOST (numpy + Pillow needed); the skeleton tree already ships
        # the rendered PNGs, verified fresh by the host-side freshness gate.
        if [[ ! -f /work/skeletons/usr/share/wallpapers/savant/contents/images/savant-traffic-lights.png ]]; then
            echo "[build] FATAL: wallpaper PNGs missing from skeletons (run gen-wallpaper.py host-side)" >&2
            exit 1
        fi
        cp -f /work/wallpapers/metadata.desktop \
              /work/skeletons/usr/share/wallpapers/savant/metadata.desktop
        mkosi --directory=/work --package-cache-dir=/mkosi-cache --output-directory=/mkosi-ws/'"$tag"'/out --workspace-directory=/mkosi-ws/'"$tag"'/ws --force
        bash /work/assemble.sh /mkosi-ws/'"$tag"'/out/image /work/build-'"$tag"'/contract "$RELEASE_NAME" "$VERSION"
    '
    rc=$?
    "$container_bin" volume rm "guest-image-ws-$tag" >/dev/null || true
    return $rc
}

echo "[build] assembly A"
run_build a
echo "[build] assembly B (determinism gate)"
run_build b

echo "[build] CRLF gate: no KConfig/unit/theme file may carry CR (KConfig mis-parses '[Group]\r' — verified 2026-09-13, whole L&F layer no-op'd on CRLF)"
# Byte-exact scan, not grep: CR is a byte question and grep's binary/text
# heuristics proved irreproducible in this environment (2026-09-15: the same
# tree alternately reported 0 and 34 CR hits between runs while a full Python
# byte scan showed 0). Byte semantics are strictly stronger than grep -I.
PY=$(command -v python3 || command -v python)
crlf_hits=$("$PY" - <<'PYEOF'
import os, sys
bad = []
for dirpath, _, files in os.walk("skeletons"):
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
print("\n".join(bad))
sys.exit(1 if bad else 0)
PYEOF
) || true
if [[ -n $crlf_hits ]]; then
    echo "[build] GATE FAILED: CR bytes found in:" >&2
    echo "$crlf_hits" >&2
    exit 1
fi

echo "[build] dual-build digest comparison"
for f in rootfs.ext4 rootfs.ext4.zst vmlinuz-linux initramfs-linux.img build-spec.json guest-manifest.json; do
    a=$(sha256sum "build-a/contract/$f" | cut -d' ' -f1)
    b=$(sha256sum "build-b/contract/$f" | cut -d' ' -f1)
    if [[ $a != "$b" ]]; then
        echo "[build] NONDETERMINISM: $f ($a != $b)" >&2
        exit 1
    fi
    echo "  $f  $a"
done

# Publish build A as the payload; drop the gate copy.
rm -rf "$out/contract"
cp -r build-a/contract "$out/contract"
rm -rf build-a build-b

# --- SHA256SUMS for the local release base (format the launcher parses:
# "<digest>  <name>", binary-mode star tolerated, plain names here)
(
    cd "$out/contract"
    sha256sum guest-manifest.json build-spec.json vmlinuz-linux \
        initramfs-linux.img rootfs.ext4 rootfs.ext4.zst > SHA256SUMS
)

# The runtime path (app/setup.go ensureRuntime) authenticates the runtime
# archive against the SAME SHA256SUMS, so a local release base must carry it.
# Source: the published v0.0.1 asset (digest e8d0be…, matching the runtime
# receipt of every installed launcher). Copied in when present, with a clear
# failure otherwise.
runtime_zip_src="${RUNTIME_ZIP:-$USERPROFILE/Downloads/winq-emu-alpha10-portable.zip}"
if [[ -f $runtime_zip_src ]]; then
    cp -f "$runtime_zip_src" "$out/contract/"
else
    echo "[build] WARNING: runtime archive not found at $runtime_zip_src" >&2
    echo "[build] WARNING: the local release base will fail launcher runtime setup;" >&2
    echo "[build] WARNING: set RUNTIME_ZIP=<path> to include it." >&2
fi

(
    cd "$out/contract"
    sha256sum guest-manifest.json build-spec.json vmlinuz-linux \
        initramfs-linux.img rootfs.ext4 rootfs.ext4.zst \
        winq-emu-alpha10-portable.zip > SHA256SUMS
)

sums_digest=$(sha256sum "$out/contract/SHA256SUMS" | cut -d' ' -f1)
cat > "$out/release-base.json" <<JSON
{
  "releaseName": "$release_name",
  "version": "$version",
  "sumsSha256": "$sums_digest",
  "note": "Serve this directory over loopback HTTP and pass -release <url> -sums-sha256 <sumsSha256> to the unmodified launcher. Includes the v0.0.1 WINQ-EMU runtime archive so the runtime path authenticates."
}
JSON

echo "[build] GATE GREEN — payload in $out/contract"
echo "[build] SHA256SUMS digest for -sums-sha256: $sums_digest"
