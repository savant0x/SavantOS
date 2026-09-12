# guest-image — first-party SavantOS guest builder (Phase 1)

Builds the factory payload from a plain Arch base with mkosi (rootless
directory build) and assembles the raw unpartitioned ext4 image with
`mke2fs -d`. Consumed by the **unmodified** Windows launcher through the
payload contract (F1–F7 in `dev/fids/FID-2026-0912-001-first-party-os-pivot.md`,
verified against `app/fetch.go`, `app/qemu.go`, `app/main.go`).

## Layout

| Path | Role |
|---|---|
| `mkosi.conf` | mkosi distribution/content config; Arch mirror pinned by snapshot date |
| `snapshot.lock.json` | the pinned Arch snapshot date (must match `mkosi.conf`; checked at build) |
| `skeletons/` | files copied into the image tree before packages install |
| `finalize.sh` | post-install script run inside the image (user, units, initramfs) |
| `assemble.sh` | tree → raw ext4 → six contract files (run inside a container) |
| `build.sh` | container orchestration + dual-build determinism gate |
| `boot-proof.sh` | local release base + unmodified-launcher boot proof (host side) |

## Build

```bash
bash guest-image/build.sh            # Docker: two assembles + digest gate
```

Gate output lands in `guest-image/out/`. The dual-build gate passes only when
`rootfs.ext4` (and its zstd twin) hash identically across two independent
assembles.

## Boot proof

```bash
bash guest-image/boot-proof.sh       # serves a local release base, boots a
                                     # fresh data dir via the real launcher
```

The launcher downloads, authenticates (`-sums-sha256`), unpacks, receipts, and
boots the new image; success is SSH reaching the guest as `savant` with the
growable root mounted.
