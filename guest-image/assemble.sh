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
