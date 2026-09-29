#!/usr/bin/env python3
"""Delta-store finalizer for the published payload (T2.1, FID-2026-0914-002).

Runs INSIDE the build container (build.sh mounts the payload). Given the new
payload directory and the PREVIOUS release's caibx (when one exists):

  1. Read the previous index's chunk IDs (the casync caibx table: offset+ID
     items, zero-terminated, 32-byte SHA-512/256 IDs).
  2. Remove every chunk file under <payload>/rootfs.castr/ whose ID is in
     that set — the client reconstructs those from its own previous image
     (the seed), verified per-chunk, so shipping them would be dead weight.
  3. Remove now-empty shard directories.
  4. Copy the previous caibx into the payload as rootfs.ext4.prev.caibx.

With no previous caibx, this is the first delta-capable release: the store
is REMOVED (nothing can use a store without a seed), the bare caibx stays
(it becomes the next release's prev), and the caller does not advertise the
delta path (no rootfs.ext4.prev.caibx entry in SHA256SUMS).

Exit codes: 0 ok; 2 usage; 3 payload/store layout unexpected (fail-closed —
the caller falls back to a non-delta payload).
"""
import os
import shutil  # copyfile for the prev index; removal helpers below are plain os
import sys

U64 = 8


def remove_file(path: str) -> "None":
    """Remove a possibly write-protected file.

    casync writes chunk files 0444 (chunks are immutable by design). This
    script runs HOST-side in build.sh's publish tail, and on the Windows
    host Python refuses to unlink read-only files (WinError 5, measured
    2026-09-28) — so chmod +w and retry. On Linux this is a no-op.
    """
    try:
        os.remove(path)
    except PermissionError:
        os.chmod(path, 0o644)
        os.remove(path)


def remove_tree(path: str) -> "None":
    """rmtree that tolerates write-protected files (see remove_file)."""
    for dirpath, dirnames, filenames in os.walk(path, topdown=False):
        for name in filenames:
            remove_file(os.path.join(dirpath, name))
        for name in dirnames:
            os.rmdir(os.path.join(dirpath, name))
    os.rmdir(path)


def fail(msg: str) -> "None":
    sys.stderr.write("delta-finalize: %s\n" % msg)
    sys.exit(3)


def read_u64(buf: bytes, off: int) -> int:
    return int.from_bytes(buf[off:off + U64], "little")


def index_chunk_ids(path: str) -> "set[bytes]":
    """Parse the caibx table and return the set of chunk IDs."""
    with open(path, "rb") as fh:
        data = fh.read()
    # Element 1: size 0x30, CaFormatIndex, featureFlags, min/avg/max.
    if len(data) < 0x30 + U64 * 2:
        fail("index too small: %s" % path)
    if read_u64(data, 0) != 0x30:
        fail("index header size is not 0x30: %s" % path)
    if read_u64(data, U64) != 0x96824D9C7B129FF9:
        fail("not a caibx index (magic): %s" % path)
    off = 0x30
    # Element 2: size MAX_UINT64, CaFormatTable, items, 4-u64 tail.
    tsize = read_u64(data, off)
    off += U64
    if tsize != (1 << 64) - 1:
        fail("table size is not MAX_UINT64: %s" % path)
    if read_u64(data, off) != 0xE75B9E112F17417D:
        fail("not a caibx table (magic): %s" % path)
    off += U64
    ids = set()
    while True:
        if off + U64 > len(data):
            fail("truncated table item: %s" % path)
        offset = read_u64(data, off)
        off += U64
        if offset == 0:
            break
        if off + 32 > len(data):
            fail("truncated chunk id: %s" % path)
        ids.add(bytes(data[off:off + 32]))
        off += 32
    if len(ids) == 0:
        fail("table has no chunks: %s" % path)
    return ids


def main() -> int:
    if len(sys.argv) not in (3, 4):
        sys.stderr.write(
            "usage: delta-finalize.py <payload-dir> <prev-caibx-or-NONE>\n")
        return 2
    payload = sys.argv[1]
    prev_path = sys.argv[2] if sys.argv[2] != "NONE" else None
    store = os.path.join(payload, "rootfs.castr")
    caibx = os.path.join(payload, "rootfs.ext4.caibx")
    if not os.path.isfile(caibx):
        fail("payload has no rootfs.ext4.caibx")
    if not os.path.isdir(store):
        fail("payload has no rootfs.castr directory")

    if prev_path is None:
        # First delta-capable release: ship the index (next release's prev),
        # drop the store (unusable without a seed), do not advertise.
        remove_tree(store)
        sys.stderr.write(
            "delta-finalize: first delta release — store removed, "
            "rootfs.ext4.caibx shipped for the next chain link\n")
        return 0

    prev_ids = index_chunk_ids(prev_path)
    kept = removed = 0
    removed_bytes = 0
    for shard in sorted(os.listdir(store)):
        shard_dir = os.path.join(store, shard)
        if not os.path.isdir(shard_dir):
            fail("unexpected non-directory in store: %s" % shard_dir)
        for name in sorted(os.listdir(shard_dir)):
            # Chunk file name: <64-hex>.cacnk — the ID IS the name.
            stem = name[:-6] if name.endswith(".cacnk") else name
            try:
                cid = bytes.fromhex(stem)
            except ValueError:
                fail("unexpected chunk file name: %s/%s" % (shard, name))
            if len(cid) != 32:
                fail("chunk id is not 32 bytes: %s/%s" % (shard, name))
            p = os.path.join(shard_dir, name)
            if cid in prev_ids:
                removed += 1
                removed_bytes += os.path.getsize(p)
                remove_file(p)
            else:
                kept += 1
        if not os.listdir(shard_dir):
            os.rmdir(shard_dir)
    shutil.copyfile(prev_path, os.path.join(payload, "rootfs.ext4.prev.caibx"))
    sys.stderr.write(
        "delta-finalize: kept %d new chunks, pruned %d seed-served chunks "
        "(%.1f MiB), prev index copied\n"
        % (kept, removed, removed_bytes / (1024 * 1024)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
