#!/bin/bash
# Assemble the six contract files (F1 in FID-2026-0912-001) from a mkosi
# directory build. Runs INSIDE the build container (Linux, rootless-ok):
#   assemble.sh <mkosi-image-dir> <output-dir> <release-name> <version>
# Output:
#   rootfs.ext4, rootfs.ext4.zst, vmlinuz-linux, initramfs-linux.img,
#   build-spec.json, guest-manifest.json
set -euo pipefail

tree=${1:?usage: assemble.sh <image-tree> <out-dir> <release-name> <version>}
out=${2:?usage: assemble.sh <image-tree> <out-dir> <release-name> <version>}
release_name=${3:?usage: assemble.sh <image-tree> <out-dir> <release-name> <version>}
version=${4:?usage: assemble.sh <image-tree> <out-dir> <release-name> <version>}

# Determinism: fixed epoch for every file in the tree (must equal mkosi.conf's
# SOURCE_DATE_EPOCH) and a fixed filesystem UUID + label so mke2fs output is
# byte-stable across machines. hash_seed must be a dashed UUID (mke2fs rejects
# bare hex: "Invalid hash seed").
epoch=1787652758
uuid=9e7b6a52-4c33-4f9a-8d21-5a7c41f0be13
hash_seed=97f2e5a1-c8b3-4d6e-9a2f-5c81d3b47e60
label=savantos-factory
size_mib=6144
expanded_mib=24576

# e2fsprogs' built-in reproducibility knob: with SOURCE_DATE_EPOCH set,
# mke2fs stamps mkfs-time fields (s_mtime/s_lastcheck family + checksum
# inputs) from the epoch instead of the wall clock. Without it, two builds
# minutes apart differ in exactly those superblock bytes — the last
# nondeterminism the dual-build gate caught.
export SOURCE_DATE_EPOCH=$epoch

# mkosi builds its kernel-modules initrd into /boot/arch AFTER the postinst
# step, so a finalize.sh cleanup can never catch it — it lands in every tree
# with build-order-dependent bytes (the last survivor of the digest gate's
# forensics). Nothing reads it: the launcher boots vmlinuz + initramfs
# directly. Removed here, before the tar stream — absent = deterministic.
rm -rf "$tree/boot/arch"

# The account tree must be owned by the account: sshd StrictModes refuses
# pubkey auth when the home directory is not user-owned (observed 2026-09-12:
# Permission denied with authorized_keys present and correct). useradd ran
# inside mkosi's id-mapped sandbox, which rewrites non-root ownership to
# root; reassert it here OUTSIDE the sandbox, before the tar stream pins it.
# uid/gid are read from the image's own account database so they can never
# drift from what the guest actually resolves.
savant_uid=$(awk -F: '$1=="savant"{print $3}' "$tree/etc/passwd")
savant_gid=$(awk -F: '$1=="savant"{print $3}' "$tree/etc/group")
[[ $savant_uid =~ ^[0-9]+$ && $savant_gid =~ ^[0-9]+$ ]] || {
    echo "assemble: savant account not found in the image tree" >&2
    exit 1
}
chown -Rh "$savant_uid:$savant_gid" "$tree/home/savant"

find "$tree" -xdev -printf '%p\0' | while IFS= read -r -d '' p; do
    touch -h -d "@$epoch" "$p" 2>/dev/null || true
done

mkdir -p "$out"

kernel=""
initramfs=""
for k in "$tree/boot/vmlinuz-linux-zen" "$tree/boot/vmlinuz-linux"; do
    [[ -f $k ]] && { kernel=$k; break; }
done
for i in "$tree/boot/initramfs-linux-zen.img" "$tree/boot/initramfs-linux.img"; do
    [[ -f $i ]] && { initramfs=$i; break; }
done
[[ -n $kernel ]] || { echo "assemble: no kernel found in $tree/boot" >&2; exit 1; }
[[ -n $initramfs ]] || { echo "assemble: no initramfs found in $tree/boot" >&2; exit 1; }
echo "assemble: kernel=$(basename "$kernel") initramfs=$(basename "$initramfs")"

# --- kernel + initramfs under the contract's fixed names (F5)
install -m 0644 "$kernel" "$out/vmlinuz-linux"
install -m 0644 "$initramfs" "$out/initramfs-linux.img"

# --- plain unpartitioned ext4 (F2): the whole image IS the filesystem;
# root=/dev/vda. Population uses a NAME-SORTED tar stream, not -d "$tree":
# mke2fs -d walks the tree in readdir order, and readdir order on an ext4
# source volume is hash-seeded per volume — different build volumes gave
# different layout and a nondeterministic image (gate, builds 11–13). A tar
# stream read sequentially pins population order: tar --sort=name fixes
# member order; the fixed epoch fixes metadata. (e2fsprogs >= 1.47 parses
# .tar in -d.)
img="$out/rootfs.ext4.part"
rm -f "$img"
# Ownership comes from the tree (all root except the account tree chowned
# above) — the --owner/--group overrides are deliberately absent, or they
# would flatten the account fix back to root. --numeric-owner keeps uid/gid
# numeric so no host name resolution can alter them.
tar --sort=name --mtime="@$epoch" --numeric-owner \
    --clamp-mtime --format=gnu \
    -C "$tree" -cf - . | mke2fs -q -F -t ext4 -b 4096 \
    -d - \
    -L "$label" -U "$uuid" \
    -E hash_seed=$hash_seed \
    -T default \
    "$img" "$((size_mib))M"

# The filesystem must be smaller than the launcher's expanded disk
# (prepareDisk truncates to expandedSizeMiB); 6 GiB factory → 24 GiB disk.
actual_mib=$(( $(stat -c %s "$img") / 1024 / 1024 ))
(( actual_mib < expanded_mib )) || {
    echo "assemble: factory image ($actual_mib MiB) must be smaller than the expanded disk ($expanded_mib MiB)" >&2
    exit 1
}
# Content assertions run BEFORE the rename (the mv lives below the probe
# block): debugfs exits 0 even when the image file is absent (verified
# 2026-09-14 — a probe against a missing image passes vacuously, which is
# exactly how this block once passed while probing a renamed-away path),
# so the probes must never see anything but the real artifact.
[[ -f $img ]] || {
    echo "assemble: image $img missing before content assertion" >&2
    exit 1
}

# --- Phase 2 content assertion (FID-2026-0912-002, gate addition): a
# silently-empty desktop must be unshippable. Probe the image for the
# desktop's load-bearing binaries with debugfs (read-only, no mount, no
# writes — determinism-safe). The keyring unit joins the list
# (FID-2026-0914-002): preset-all only WARNS on a missing unit, so a
# silently keyring-less image must also be unshippable.
for probe in \
    /usr/bin/kwin_wayland \
    /usr/bin/plasmashell \
    /usr/bin/sddm \
    /usr/bin/sddm-greeter \
    /usr/share/color-schemes/Savant.colors \
    /usr/share/wallpapers/savant/metadata.desktop \
    /usr/share/kwin/decorations/savant-traffic-lights/contents/ui/main.qml \
    /usr/share/plasma/look-and-feel/savant.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
    /usr/share/Kvantum/Savant/Savant.kvconfig \
    /usr/lib/qt6/plugins/styles/libkvantum.so \
    /usr/share/icons/Papirus-Dark/index.theme \
    /usr/share/icons/hicolor/scalable/apps/savant-start.svg \
    /etc/skel/.config/powermanagementprofilesrc \
    /etc/systemd/system/savantos-keyring-init.service \
    /usr/bin/savant-core \
    /usr/lib/systemd/user/savant-core.service \
    /usr/lib/systemd/user-preset/91-savantos-desktop.preset \
    /usr/bin/chromium \
    /usr/bin/featherpad \
    /usr/bin/cursor \
    /usr/share/applications/cursor.desktop \
    /usr/bin/savant \
    /usr/lib/savant-code/savant-code \
    /usr/local/lib/savantos/provision-key \
    /usr/local/bin/clipboard-bridge \
    /usr/lib/systemd/user/savantos-clipboard.service \
    /etc/xdg/autostart/savantos-provision-key.desktop; do
    if ! debugfs -R "stat "$probe"" "$img" >/dev/null 2>&1; then
        echo "assemble: desktop content assertion FAILED — $probe missing" >&2
        exit 1
    fi
done
# Regression guard (FID-2026-0915-006 evidence): the shipped unit MUST set
# RuntimeDirectory — without it ReadWritePaths=%t/savant-core fails mount
# namespacing (226/NAMESPACE) and the daemon crash-loops into start-limit
# (found by the first boot of the 2026-09-15 image). Temp file: same
# SIGPIPE/pipefail discipline as the ELF probe below.
dbg_unit=$(mktemp)
debugfs -R "cat /usr/lib/systemd/user/savant-core.service" "$img" > "$dbg_unit" 2>/dev/null
if ! grep -q "^RuntimeDirectory=savant-core$" "$dbg_unit"; then
    rm -f "$dbg_unit"
    echo "assemble: savant-core.service missing RuntimeDirectory (226/NAMESPACE regression)" >&2
    exit 1
fi
rm -f "$dbg_unit"
echo "assemble: content assertion passed (kwin/plasma/sddm/savant scheme/keyring unit/savant-core/chromium/featherpad/cursor/unit-RuntimeDirectory)"

# cursor (FID-2026-0916-002): the vendor-locked AppImage must be the real
# pinned bytes — ELF magic (AppImages are ELF) + the digest of record from
# cursor.lock.json, computed from the image content itself. A stale cache
# or partial download otherwise ships silently.
cursor_tmp=$(mktemp)
debugfs -R "cat /usr/bin/cursor" "$img" > "$cursor_tmp" 2>/dev/null
if ! head -c 4 "$cursor_tmp" | grep -q $'\x7fELF'; then
    echo "assemble: cursor is not an AppImage (ELF magic missing)" >&2
    rm -f "$cursor_tmp"
    exit 1
fi
want_cursor=$(python3 -c "import json; print(json.load(open('/work/cursor.lock.json'))['sha256'])" 2>/dev/null || true)
have_cursor=$(sha256sum "$cursor_tmp" | cut -d' ' -f1)
rm -f "$cursor_tmp"
if [ -z "$want_cursor" ]; then
    echo "assemble: cursor.lock.json unreadable — cannot verify vendor digest" >&2
    exit 1
fi
if [ "$have_cursor" != "$want_cursor" ]; then
    echo "assemble: cursor digest mismatch (have ${have_cursor:0:16}, want ${want_cursor:0:16})" >&2
    exit 1
fi
echo "assemble: cursor vendor digest verified (${have_cursor:0:16})"
# Icon must ship too: extract from the verified AppImage and check hicolor
# 512px exists (the desktop entry references Icon=cursor).
icon_tmp=$(mktemp -d)
debugfs -R "cat /usr/share/icons/hicolor/512x512/apps/cursor.png" "$img" > "$icon_tmp/cursor.png" 2>/dev/null
if ! head -c 8 "$icon_tmp/cursor.png" | grep -q $'\x89PNG\r\n\x1a\n'; then
    echo "assemble: cursor icon missing or corrupt (PNG magic check failed)" >&2
    rm -rf "$icon_tmp"
    exit 1
fi
rm -rf "$icon_tmp"
echo "assemble: cursor icon verified"

# savant-code (FID-2026-0917-002): the embedded agent ships as native
# software. The image carries the untarred app at /usr/lib/savant-code/
# (Bun standalones resolve their sibling assets relative to the binary)
# with a /usr/bin/savant wrapper. Probe: ELF magic + the lock's
# binarySha256, computed from the image content itself — an existence
# probe alone would let a truncated or stale install ship silently.
sc_tmp=$(mktemp)
debugfs -R "cat /usr/lib/savant-code/savant-code" "$img" > "$sc_tmp" 2>/dev/null
if ! head -c 4 "$sc_tmp" | grep -q $'\x7fELF'; then
    echo "assemble: savant-code binary is not an ELF (magic missing)" >&2
    rm -f "$sc_tmp"
    exit 1
fi
want_sc=$(python3 -c "import json; print(json.load(open('/work/savant-code.lock.json'))['binarySha256'])" 2>/dev/null || true)
have_sc=$(sha256sum "$sc_tmp" | cut -d' ' -f1)
rm -f "$sc_tmp"
if [ -z "$want_sc" ]; then
    echo "assemble: savant-code.lock.json unreadable — cannot verify vendor digest" >&2
    exit 1
fi
if [ "$have_sc" != "$want_sc" ]; then
    echo "assemble: savant-code digest mismatch (have ${have_sc:0:16}, want ${want_sc:0:16})" >&2
    exit 1
fi
# Mode probe: the MSYS host cannot represent the exec bit (proved during
# wiring), so the image content is the only honest place to assert it.
# mkosi normalizes bind-mounted trees to 0777 (proved live: cursor ships
# 0777 and runs), so the assertion is the OWNER EXEC BIT, not a specific
# octal. debugfs 1.47.4 prints 'Mode:  0755' (verified on a synthetic
# ext4); take the last 3 octal digits, first digit = owner rwx.
sc_mode=$(debugfs -R "stat /usr/lib/savant-code/savant-code" "$img" 2>/dev/null \
    | sed -n 's/.*Mode: *[0-7]\{0,2\}\([0-7]\)\([0-7]\{2\}\).*/\1\2/p' | head -1)
sc_owner=${sc_mode:0:1}
if [ -z "$sc_mode" ] || [ $((sc_owner & 1)) -ne 1 ]; then
    echo "assemble: savant-code binary not owner-executable in image content (mode ${sc_mode:-none})" >&2
    exit 1
fi
wrapper_tmp=$(mktemp)
debugfs -R "cat /usr/bin/savant" "$img" > "$wrapper_tmp" 2>/dev/null
if ! grep -q "exec /usr/lib/savant-code/savant-code" "$wrapper_tmp"; then
    echo "assemble: /usr/bin/savant wrapper missing or wrong target" >&2
    rm -f "$wrapper_tmp"
    exit 1
fi
rm -f "$wrapper_tmp"
echo "assemble: savant-code vendor digest verified (${have_sc:0:16})"

# savant-core (FID-2026-0915-005 m2) must be the real cross-compiled
# binary, not a stale artifact from a previous build on this tree: an
# existence probe alone would let a Linux-embed COFF silently ship (the
# host build runs on Windows). ELF magic + mode check here.
# Pipefail trap avoided: debugfs | head -c 4 makes debugfs die of SIGPIPE
# (it writes 2.2MB into a pipe head closes after 4 bytes) and pipefail
# converts that into a false "not ELF" (caught 2026-09-15, first build
# with the daemon). Temp file: debugfs completes, exits 0, no SIGPIPE.
sc_tmp=$(mktemp)
debugfs -R "cat /usr/bin/savant-core" "$img" > "$sc_tmp" 2>/dev/null
if ! head -c 4 "$sc_tmp" | grep -q $'\x7fELF'; then
    echo "assemble: savant-core is not a Linux ELF binary" >&2
    rm -f "$sc_tmp"
    exit 1
fi
rm -f "$sc_tmp"

# Mode normalization for the daemon's files (narrow slice of the T1
# finding — the whole tree currently ships 0777): the unit must not be
# executable/world-writable (systemd warns and refuses to treat it as
# trusted), the binary must be executable. Normalized HERE, before the
# tar stream, so the shipped image is right regardless of worktree modes.
chmod 0755 "$tree/usr/bin/savant-core"
chmod 0644 "$tree/usr/lib/systemd/user/savant-core.service" \
           "$tree/usr/lib/systemd/user-preset/91-savantos-desktop.preset"

# The power-button seed is load-bearing for the launcher's close contract
# (FID-2026-0914-003): the loop above proves the file ships, this proves
# the VALUE — a silently-wrong seed reintroduces the can't-close bug an
# existence probe would miss. kwriteconfig6 writes the key as one line.
if ! debugfs -R "cat /etc/skel/.config/powermanagementprofilesrc" "$img" 2>/dev/null \
    | grep -q '^powerButtonAction=8$'; then
    echo "assemble: power-button shutdown seed missing or wrong (expected powerButtonAction=8)" >&2
    exit 1
fi

# Rename after the assertions: they must probe the artifact that actually
# exists on disk. (The rename used to sit above this block; every probe
# then ran against a missing path and — thanks to debugfs's exit-0 quirk —
# "passed" vacuously. Caught 2026-09-14 by the power-button value probe,
# the only assertion strict enough to fail on empty output.)
mv "$img" "$out/rootfs.ext4"

# --- compressed twin (the launcher downloads this one and verifies against
# the uncompressed digest after unpack). Level 6 at -T1: deterministic
# (fixed thread count) and fast enough for the dual-build gate; revisit
# level for release-size tuning later — the digest gate only needs
# identical flags in both builds.
zstd -q -f -k -T1 --no-progress -6 "$out/rootfs.ext4" -o "$out/rootfs.ext4.zst"

# --- build-spec.json (F2): the launcher requires runtime.kernelCommandLine
# and runtime.storage.expandedSizeMiB; the rest documents the build.
cat > "$out/build-spec.json" <<SPEC
{
  "schemaVersion": 1,
  "image": {
    "architecture": "x86_64",
    "filesystem": "ext4",
    "filesystemLabel": "$label",
    "filesystemUuid": "$uuid",
    "sizeMiB": $size_mib,
    "sourceDateEpoch": $epoch
  },
  "guest": {
    "profile": "factory",
    "hostname": "savantos",
    "username": "savant"
  },
  "builder": {
    "tool": "guest-image/mkosi+mke2fs",
    "releaseName": "$release_name",
    "version": "$version",
    "stream": "phase1"
  },
  "runtime": {
    "kernel": "vmlinuz-linux",
    "initramfs": "initramfs-linux.img",
    "disk": "rootfs.ext4",
    "compressedDisk": "rootfs.ext4.zst",
    "kernelCommandLine": "root=/dev/vda rw rootwait console=tty0 console=hvc0 loglevel=4 systemd.show_status=false rd.systemd.show_status=false systemd.firstboot=0 mitigations=off nowatchdog net.ifnames=0 savantos.image=1",
    "minimumMemoryMiB": 2048,
    "recommendedMemoryMiB": 4096,
    "minimumCpuCount": 2,
    "virtualMachineMonitor": "qemu-system-x86_64",
    "hypervisor": "whpx",
    "storage": {
      "device": "virtio-blk-pci",
      "format": "raw",
      "mode": "ephemeral",
      "initialization": "full-copy",
      "expandedSizeMiB": $expanded_mib
    }
  }
}
SPEC

# --- guest-manifest.json: authenticated artifact sizes for disk-space
# preflight (app/disk_space.go readGuestArtifactSizes). Path == basename.
digest() { sha256sum "$1" | cut -d' ' -f1; }

rootfs_sha=$(digest "$out/rootfs.ext4")
zst_sha=$(digest "$out/rootfs.ext4.zst")
kernel_sha=$(digest "$out/vmlinuz-linux")
initramfs_sha=$(digest "$out/initramfs-linux.img")
spec_sha=$(digest "$out/build-spec.json")
rootfs_bytes=$(stat -c %s "$out/rootfs.ext4")
zst_bytes=$(stat -c %s "$out/rootfs.ext4.zst")
kernel_bytes=$(stat -c %s "$out/vmlinuz-linux")
initramfs_bytes=$(stat -c %s "$out/initramfs-linux.img")
spec_bytes=$(stat -c %s "$out/build-spec.json")

cat > "$out/guest-manifest.json" <<MANIFEST
{
  "schemaVersion": 1,
  "artifacts": [
    { "path": "rootfs.ext4",    "bytes": $rootfs_bytes,    "sha256": "$rootfs_sha" },
    { "path": "rootfs.ext4.zst", "bytes": $zst_bytes,     "sha256": "$zst_sha" },
    { "path": "vmlinuz-linux",  "bytes": $kernel_bytes,    "sha256": "$kernel_sha" },
    { "path": "initramfs-linux.img", "bytes": $initramfs_bytes, "sha256": "$initramfs_sha" },
    { "path": "build-spec.json", "bytes": $spec_bytes,    "sha256": "$spec_sha" }
  ]
}
MANIFEST

echo "assemble: six contract files in $out"
ls -la "$out"
