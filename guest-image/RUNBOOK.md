# RUNBOOK — dual-build determinism run (T1.3, FID-2026-0914-002 contract gate)

How to run `guest-image/build.sh` correctly and what to do when it fights
back. Distilled from the 2026-09-28 T1.3 runs (two green gates, one publish
failure) and the FID's declared gate: *Docker: mkosi build ×2 → digests
equal; six-file contract emitter verified against SHA256SUMS.*

## When to run this

- After any factory-tree change lands (`guest-image/`, `guest-daemon/`,
  runtime/wallpaper/skeleton content) and the new image must become the
  delta baseline (master plan T1.3 → T2.1 seed).
- Before any release-cycle dry run (stage 3) — the release consumes this
  payload.
- To re-prove determinism after a builder-toolchain change.

**Definition of done:** two independent assemblies with all six contract
files hashing identically, the payload published under `out/contract`, and
`release-base.json` re-emitted. A single assembly is NOT the gate.

## Prerequisites (all measured on the reference host)

| Check | How | Why |
|---|---|---|
| Docker engine running | `docker info` answers | Docker Desktop does not auto-start; launch `Docker Desktop.exe`, engine answers in ~1 min |
| ≥ 35 GiB transient disk | `df -Pm` on the build drive | `build.sh` fails closed below 35000 MiB (2 workspaces + 2 contracts + payload ≈ 35 G peak) |
| Runtime archive | `out/runtime-archive/winq-emu-alpha10-portable.zip` (durable home) or `$USERPROFILE/Downloads/`, or `RUNTIME_ZIP=<path>` | fail-closed since the 2026-09-16 build: SHA256SUMS cannot authenticate the runtime path without it |
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
assemble: six contract files in /work/build-a/contract
[build] assembly B (determinism gate)
… same sequence, /work/build-b …
[build] CRLF gate: no KConfig/unit/theme file may carry CR …
[build] dual-build digest comparison
  rootfs.ext4            <64-hex>     # and the other five files
[build] GATE GREEN — payload in …/out/contract
[build] SHA256SUMS digest for -sums-sha256: <64-hex>
```

Cosmetic noise, not failures: pacman provider prompts ("Enter a number
(default=1)") are non-interactive defaults; the `libgpg-error` `.INSTALL
arithmetic` line is hook-script noise under `bash -ceu`.

## Failure modes (each observed at least once)

- **`rm -rf out/contract`: "Device or resource busy"** at the publish tail
  (2026-09-19, 2026-09-28). A host-side handle holds the previous payload
  directory — prime suspect: Docker Desktop's file-sharing layer, which
  serves `out/` through the `/work` bind during the build; Explorer or the
  search indexer can too. Since 2026-09-28 `build.sh` releases its EXIT
  trap once the gate has spoken, retries the removal 6 × 10 s, and on
  residual failure exits with **`build-a/contract` intact** and
  hand-publish instructions. The old behavior destroyed both proven copies
  via the EXIT trap — never run a pre-fix `build.sh` for a baseline you
  cannot afford to rebuild.
- **Manual publish fallback** (when the FATAL above fires): the husk may
  remain (empty dir, children deleted). Once writable
  (`touch out/contract/.probe`), publish into it:
  `cp -r build-a/contract/. out/contract/`, then copy the runtime zip in
  and re-emit `SHA256SUMS` + `release-base.json` exactly as the script
  would (see Post-run checklist). Verify the published `rootfs.ext4`
  digest equals the gate digest before calling it published.
- **Docker engine down** — start Docker Desktop, poll `docker info`.
- **Runtime archive missing** — FATAL names the paths; set `RUNTIME_ZIP`.
- **Vendor digest mismatch** — the cache or the vendor changed; re-fetch;
  if the vendor re-released, update the lock and the cache in one commit.
- **CRLF gate failure** — a text file in `skeletons/` carries CR bytes
  (KConfig mis-parses them); fix the file, never the gate.
- **`NONDETERMINISM: <file> (a != b)`** — STOP. Do not publish. Record
  both digests in the owning FID; the file name is the investigation.
- **Disk space FATAL** — clean stale payloads/data dirs; the rotation
  guard normally handles `out/contract-*` siblings itself.

## Post-run checklist

1. Gate verdict: six `  <file>  <digest>` lines, no NONDETERMINISM.
2. Cross-run reproducibility (when a previous run's digests exist): the
   digest files diff clean. Tree-identical reruns MUST be byte-identical
   (2026-09-28: run 2 == run 1 on all six). Drift means the tree or the
   toolchain changed — investigate before publishing.
3. Published payload: `out/contract/` has the six files + the runtime zip
   + `SHA256SUMS`; published `rootfs.ext4` digest == gate digest.
4. `release-base.json`: `sumsSha256` == `sha256sum out/contract/SHA256SUMS`.
5. `build-a/`/`build-b/` gone (trap or manual); stale
   `guest-image-ws-*` volumes pruned (`docker volume ls`).
6. Records: master plan T1.3 row, FID-2026-0914-002 gate note, CHANGELOG,
   SCOPE current position. Evidence: the run log + digest files stay in
   `guest-image/out/`.

## Scope honesty (what a green run does NOT prove)

A green dual-build discharges T1.3 (determinism + baseline) only. Stage-3
rows it does not touch: reliable content-negative tests in `assemble.sh`
(absence assertions), one-owner reconciliation of runtime acquisition and
manifest assembly across `build.sh` and `scripts/release/prepare-assets.sh`
(this runbook's flow owns the local baseline; the release flow's ownership
is still a named addendum defect), and isolated harness ownership. Those
are separate stage-3 items with their own evidence obligations.

## Consuming the baseline (operator-gated)

Serve `out/contract` over loopback HTTP and pass
`-release http://127.0.0.1:<port> -sums-sha256 <sumsSha256>` to the
unmodified launcher (`guest-image/boot-proof.sh` automates the shape).
Per the 2026-09-28 ruling, any VM launch — including a fresh-provision
re-provision of a dev/accept target from this baseline — is operator-gated.
