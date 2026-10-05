# RUNBOOK — dual-build determinism run (T1.3, FID-2026-0914-002 contract gate)

How to run `guest-image/build.sh` correctly and what to do when it fights
back. Distilled from the 2026-09-28 T1.3 runs (two green gates, one publish
failure) and the FID's declared gate: *Docker: mkosi build ×2 → digests
equal; six-file contract emitter verified against SHA256SUMS.* Since the
late-2026-09-28 builder change the build also emits the T2.1 casync delta
artifacts (FID-2026-0914-002) and finalizes the payload's delta store
before publish — this runbook covers both.

## When to run this

- After any factory-tree change lands (`guest-image/`, `guest-daemon/`,
  runtime/wallpaper/skeleton content) and the new image must become the
  delta baseline (master plan T1.3 → T2.1 seed).
- Before any release-cycle dry run (stage 3) — the release consumes this
  payload.
- To re-prove determinism after a builder-toolchain change.

**Definition of done:** two independent assemblies with all seven gated
contract files (the six originals plus `rootfs.ext4.caibx`) hashing
identically, the payload published under `out/contract` with its delta
store finalized, and `release-base.json` re-emitted. A single assembly is
NOT the gate.

## Prerequisites (all measured on the reference host)

| Check | How | Why |
|---|---|---|
| Docker engine running | `docker info` answers | Docker Desktop does not auto-start; launch `Docker Desktop.exe`, engine answers in ~1 min |
| ≥ 35 GiB transient disk | `df -Pm` on the build drive | `build.sh` fails closed below 35000 MiB (2 workspaces + 2 contracts + payload ≈ 35 G peak) |
| Runtime archive | `out/runtime-archive/winq-emu-alpha10-portable.zip` (durable home), `$USERPROFILE/Downloads/`, or `RUNTIME_ZIP=<path>`; when none exists the build fetches from `scripts/release/runtime.lock.json` and digest-verifies before use | the lock is the single pin (stage-3 one-owner change); every staged copy — fast-path or fetched — is verified against the lock before it enters the payload |
| Vendor caches | `out/cursor.AppImage`, `out/savant-code.tar.gz` present | saves ~360 MB of fetch; digests are re-verified against the locks either way |
| Host tools | `bash`, `docker`, `go`, `python3`, `sha256sum` | savant-core cross-compiles host-side; lock reads + the CRLF byte scan use python3 |
| Clean factory tree | `git status` shows no uncommitted `guest-image/` skeleton/finalize changes | the build embeds the tree as-is; never publish a baseline from a dirty tree |

**Cheap pre-flight first:** `scripts/release/build-guest.sh --contract-only`
runs the builder-tree gates without building (snapshot lock, `bash -n`,
CRLF scan, skeleton presence probes). Run it before committing two hours.

## Procedure

1. Pre-flight (table above + `--contract-only`).
2. Archive the previous run's evidence if `out/t13-*.log` files exist — a
   new run does not overwrite them (use dated names), but gate-digest
   extracts should be saved (`t13-runN-gate-digests.txt` pattern).
3. Launch detached, per the process rules (`scripts/dev/README.md`):

   ```bash
   nohup bash guest-image/build.sh > guest-image/out/t13-dual-build-<date>.log 2>&1 &
   ```

   Redirect the child's stdio IN the nohup command; never `&` a longer
   chain whose earlier members share the tool call's stdout pipe.
4. Wait ~2 hours. Measured on the reference host (2026-09-28): run 1
   12:22→14:26, run 2 14:38→16:44 — the pacman cache volume does not
   meaningfully shorten a run; plan 2 h per run, not per assembly.
5. Verify the gate (below), then the publish tail (below).

## What a green run looks like (in log order)

```text
snapshot-lock: OK (Arch snapshot 20260811)
[build] savant-core built: <16-hex>
[build] cursor AppImage cache hit: <16-hex>          # or staged: after a fetch
[build] savant-code cache hit: <16-hex>
[build] rotation guard: <N> MiB free, pruning stale artifacts
[build] assembly A
[build] savant-code exec bits verified in-container
[finalize] savantos factory image configuration … / [finalize] done
assemble: kernel=vmlinuz-linux-zen initramfs=initramfs-linux-zen.img
assemble: cursor vendor digest verified … / savant-code vendor digest verified …
assemble: mode assertion passed (/usr /usr/share 755; savant-core 755; unit+preset 644)
assemble: delta index emitted (<bytes> bytes; <chunks> chunks)  # T2.1: caibx + rootfs.castr/
assemble: six contract files in /work/build-a/contract  # echo wording is historical — 8+ files ship now
[build] assembly B (determinism gate)
… same sequence, /work/build-b …
[build] CRLF gate: no KConfig/unit/theme file may carry CR …
[build] dual-build digest comparison
  rootfs.ext4            <64-hex>     # and the other six files — rootfs.ext4.caibx is gated (T2.1)
[publish] staged payload: verified (7 gated files present, SHA256SUMS clean)
[publish] previous payload parked at …/out/contract.prev
[publish] published payload: verified (7 gated files present, SHA256SUMS clean)
[publish] previous payload removed after verification
[build] GATE GREEN — payload in …/out/contract
[build] SHA256SUMS digest for -sums-sha256: <64-hex>
```

Cosmetic noise, not failures: pacman provider prompts ("Enter a number
(default=1)") are non-interactive defaults; the `libgpg-error` `.INSTALL
arithmetic` line is hook-script noise under `bash -ceu`.

## Delta artifacts and the publish tail (T2.1, FID-2026-0914-002)

What the builder now emits and when the store gets touched:

- **assemble.sh** emits `rootfs.ext4.caibx` (casync block index of the
  image) and `rootfs.castr/` (its sharded chunk store,
  `<4-hex>/<64-hex>.cacnk` chunk files) after the zstd twin. The store
  path is passed via `--store` explicitly — measured 2026-09-28: casync
  writes its DEFAULT store next to the index file, not in the cwd, which
  is exactly what the first delta build's `mv default.castr` tripped on.
  Both outputs are fail-closed asserted (chunk count > 0, index non-empty).
  casync installs in-container via build.sh's pacman list; nothing
  host-side is needed.
- **The caibx joins the dual-build digest gate** (seven files now).
  casync output was measured deterministic (same input + flags →
  byte-identical index, even across different store paths), so it gates
  like every other artifact.
- **Delta finalization runs on `build-a/contract` BEFORE the publish
  swap.** Given the previous release's caibx (newest `out/contract-*`
  sibling), the finalizer prunes every seed-served chunk from the store
  and copies the prev index in as `rootfs.ext4.prev.caibx`. Doing this
  pre-swap means first-release mode deletes the whole ~6 GiB store before
  the payload is renamed into place — never dragged through the virtiofs
  mount only to be deleted host-side.
- **What a FIRST delta-capable release ships** (no previous payload —
  the T1.3 baseline is one): the bare `rootfs.ext4.caibx` only — the
  store is REMOVED (unusable without a seed) and no prev index exists, so
  nothing advertises the delta path. It becomes the next release's chain
  link. From release N+1 on, the payload carries the pruned store +
  `rootfs.ext4.prev.caibx` and SHA256SUMS entries for both.
- **Fail-closed, not fail-dead:** a finalizer layout surprise (rc=3)
  strips the delta artifacts and ships a working NON-delta payload — the
  launcher's zst path is untouched. rc≠3 aborts the build (gate green,
  `build-a/` preserved).
- **Never re-run `delta-finalize.py` on the published `out/contract`.**
  In first-release mode its rc=3 fallback deletes the already-shipped
  caibx; a second prune pass double-counts. `build-a/contract` is already
  final when `publish-tail.sh` runs — it is renamed into place verbatim;
  never mutate it by hand.
- Chunk files are written 0444 (immutable by design); the finalizer's
  remove path chmods on PermissionError — required host-side on Windows
  (WinError 5, measured), no-op on Linux.

## Failure modes (each observed at least once)

- **`out/contract` busy (rename failure)** at the publish tail (the old
  `rm` tail hit it 2026-09-19 and 2026-09-28, and husked the published N
  payload on 2026-09-29). A host-side handle holds the payload directory —
  prime suspect: Docker Desktop's file-sharing layer, which serves `out/`
  through the `/work` bind during the build; Explorer or the search
  indexer can too. Since FID-2026-1005-001 the publish path never
  deletes: `publish-tail.sh` parks the previous payload with a rename
  (retried 6 × 10 s), installs the new one with a second rename, and
  removes the park only after re-verifying the published payload.
  Exhausted retries exit with the **previous payload still published and
  intact** plus `build-a/contract` intact — no code path destroys a
  payload before its replacement verifies.
- **Manual publish fallback** (only if the rename itself stays blocked):
  everything survives on disk — previous payload published (or parked at
  `out/contract.prev`), new payload at `build-a/contract`. Once the handle
  releases, follow the recovery the FATAL message prints:
  `mv out/contract.prev out/contract` (restore) and/or
  `mv build-a/contract out/contract` (install), then verify per the
  Post-run checklist (published `rootfs.ext4` digest equals the gate
  digest, `sha256sum -c SHA256SUMS` clean, `release-base.json` sumsSha256
  matches). There is no husk case anymore: renames are all-or-nothing.
- **Docker engine down** — start Docker Desktop, poll `docker info`.
- **Runtime archive missing** — since the stage-3 one-owner change the
  build fetches it from the runtime lock's pinned url and digest-verifies
  before use; only a failed fetch or a digest mismatch FATALs (check
  network/proxy, or set `RUNTIME_ZIP=<pinned copy>`). A local copy whose
  digest has drifted also FATALs, naming want/have — replace or delete
  it; the lock digest is the truth, never the local file.
- **Vendor digest mismatch** — the cache or the vendor changed; re-fetch;
  if the vendor re-released, update the lock and the cache in one commit.
- **CRLF gate failure** — a text file in `skeletons/` carries CR bytes
  (KConfig mis-parses them); fix the file, never the gate.
- **`NONDETERMINISM: <file> (a != b)`** — STOP. Do not publish. Record
  both digests in the owning FID; the file name is the investigation.
- **Disk space FATAL** — clean stale payloads/data dirs; the rotation
  guard normally handles `out/contract-*` siblings itself.
- **`mv: cannot stat 'default.castr'`** (2026-09-28, first delta build) —
  pre-fix symptom only: casync's default store lands next to the index,
  not in the cwd, so the old cwd-relative `mv` found nothing. Current
  assemble.sh passes `--store` explicitly; seeing this means a stale
  script is running — stop and sync.
- **`assemble: casync produced no chunks` / "casync missing"** — the
  emitter fails closed rather than shipping an unindexable payload; check
  the container's pacman step.
- **`delta finalization failed (rc=3) — shipping a NON-DELTA payload`** —
  not a lost build: the payload publishes without delta artifacts and the
  zst path serves every client. Record the finalizer's stderr in
  FID-2026-0914-002; the layout surprise is the investigation.

## Post-run checklist

1. Gate verdict: six `  <file>  <digest>` lines, no NONDETERMINISM.
2. Cross-run reproducibility (when a previous run's digests exist): the
   digest files diff clean. Tree-identical reruns MUST be byte-identical
   (2026-09-28: run 2 == run 1 on all six). Drift means the tree or the
   toolchain changed — investigate before publishing.
3. Published payload: `out/contract/` has the six files + the runtime zip
   + `SHA256SUMS`; published `rootfs.ext4` digest == gate digest. Delta
   shape per the first-release rule: `rootfs.ext4.caibx` present, NO
   `rootfs.castr/`, no `rootfs.ext4.prev.caibx` — until a previous index
   exists to prune against.
4. `release-base.json`: `sumsSha256` == `sha256sum out/contract/SHA256SUMS`.
   The sums include the delta entries (caibx, prev index, store files when
   present), so the digest is only final after the publish tail completes.
5. `build-a/`/`build-b/` gone (trap or manual); stale
   `guest-image-ws-*` volumes pruned (`docker volume ls`).
6. Records: master plan T1.3 row, FID-2026-0914-002 gate note, CHANGELOG,
   SCOPE current position. Evidence: the run log + digest files stay in
   `guest-image/out/`.

## Scope honesty (what a green run does NOT prove)

A green dual-build discharges T1.3 (determinism + baseline) only. Stage-3
rows it does not touch: reliable content-negative tests in `assemble.sh`
(absence assertions), and isolated harness ownership. The one-owner
reconciliation of runtime acquisition and manifest assembly across
`build.sh` and `scripts/release/prepare-assets.sh` is RESOLVED
(2026-10-03): the builder owns the runtime archive and its sums entry,
and prepare-assets asserts the pin and stages only the source archive.
The remaining rows are separate stage-3 items with their own evidence
obligations.

## Consuming the baseline (operator-gated)

Serve `out/contract` over loopback HTTP and pass
`-release http://127.0.0.1:<port> -sums-sha256 <sumsSha256>` to the
unmodified launcher (`guest-image/boot-proof.sh` automates the shape).
Per the 2026-09-28 ruling, any VM launch — including a fresh-provision
re-provision of a dev/accept target from this baseline — is operator-gated.

The delta path activates from the SECOND delta-capable release: a payload
carrying `rootfs.ext4.prev.caibx` + a pruned `rootfs.castr/` lets an
already-installed launcher reconstruct the new image from its current one
plus the advertised chunks. The first delta-capable release ships the bare
caibx, so every install of THIS baseline takes the zst path by design.
