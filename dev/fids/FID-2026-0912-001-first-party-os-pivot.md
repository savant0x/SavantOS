# FID: First-party OS pivot — mkosi builder, Plasma guest, Omarchy retirement

**Filename:** `FID-2026-0912-001-first-party-os-pivot.md`
**ID:** FID-2026-0912-001
**Severity:** critical
**Status:** implemented (Phase 1)
**Created:** 2026-09-12 00:00
**YAGNI-Compliance:** Verified

---

## Summary

Operator-approved pivot of the SavantOS guest from the Omarchy/Hyprland fork
(48-patch git-am train against a pinned upstream builder repo) to a **first-party
guest builder**: plain Arch base installed with **mkosi (rootless directory
build)** and assembled into a **plain unpartitioned ext4 raw image** with
`mke2fs -d`, **KDE Plasma 6 (Wayland)** desktop, the traffic-lights identity as
native KWin theming, and the Savant agent embedded as a first-class peer via the
verified KWin EIS + AT-SPI2 control plane. The host/launcher/hypervisor layer
(Go, WHPX, virtio) is explicitly **unchanged**. The Gemini Deep Research brief
and its reconciliation (`dev/gemini-deep-research-prompt.md`,
`dev/research-reconciliation.md`) are adopted as binding design inputs per the
operator's rulings.

## Operator rulings (ECHO Law 2 — recorded verbatim)

1. **Reconciliation adopted** — `dev/research-reconciliation.md` ADOPT/ADAPT/REJECT
   lists become binding design decisions.
2. **Agent safety law confirmed** — tiered approvals (read = silent, project writes =
   logged, destructive/network/shell = out-of-band human approval); un-hideable audit
   overlay; kill switch severing the agent's input channel; agent confined to an
   unprivileged identity that cannot modify its own permissions.
3. **Pivot green-lit** — FID filed; Phase 1 builds after the FID perfection loop
   converges (operator directive: "run the full perfection loop on the fid before
   building"); Omarchy retirement plan returns for final sign-off before any
   removal executes.

## Ruling: NO WIPE — surgical retirement, not a reset

Operator question: "do we simply need to wipe this dir and start over?"
**Answer: no.** The repo is 307 tracked files; the parts that die are ~60
(`guest-build/` patch train = 51 files + the Omarchy derivations in ~17 other
files). The launcher, release pipeline, dev loop, governance, and signing work —
~80% of the system by value — survive untouched and continue to work throughout.
A wipe would destroy the SignPath trail, CI, backup/restore, and the update
ladder for zero benefit. Git history is the archive; nothing needs deleting to
start building.

### Kill list (executes ONLY after operator sign-off, as a numbered step)

| Item | Files | Disposition |
|---|---|---|
| Patch train | `guest-build/` (48 patches + README + source.lock.json + runtime.lock.json) | Deleted when the mkosi builder replaces it; locks' *roles* move into the mkosi manifest |
| Omarchy docs derivations | `docs/COMPATIBILITY.md`, `docs/MIGRATION.md`, `docs/FINDINGS.md` (+ omarchy sections in `BACKUP.md`, `PORTABLE_USB.md`, `TESTING.md`, `SAVANT-VERSIONING.md`) | Rewritten or retired with the builder |
| Omarchy test harness | `scripts/boot-savantos-test.ps1`, `scripts/vmtest/` omarchy assumptions | Re-targeted to the new image |
| Workflow wiring | `.github/workflows/release.yml` omarchy inputs | Re-pointed at mkosi outputs |
| Prose refs | `README.md`, `CHANGELOG.md`, `ECHO.md` mentions | Updated |
| Dev VM live layer | Omarchy inside `savantos-dev` data disk | Persisted disk (3c ruling); it self-obsoletes once the new image boots — no action needed |

### Keep list (untouched by the pivot)

- `app/` — Go launcher: WHPX/QEMU, memory ladder, close guard, updates, backup,
  clipboard/share/SSH bridges, provisioning, port forwards.
- `scripts/release/` — release pipeline (prepare → pin → publish), verify/validate
  tooling, SignPath integration; build-guest.sh's *contract* concept survives,
  its git-am implementation is replaced.
- `scripts/dev/` — dev VM loop (dev-vm.sh, guest-patch.sh retargets later).
- `dev/signpath-*`, `.signpath/`, ECHO governance, FIDs, CHANGELOG, CI.
- Guest integration set (provisioning, trial mode, clipboard bridge, sshd-per-boot,
  catch-up, export, update notify) — extracted from the patch train into the new
  builder as first-party files.

## The payload contract (verified against code, Loop-1 evidence)

The launcher consumes a **directory payload** (`<data>/guest/`) swapped
atomically with rollback (`app/fetch.go` `ensureGuest` → `publishDirectoryUpdate`,
`app/payload_update.go`). The contract the new builder must satisfy **without any
launcher changes**:

**F1. Six digest-tracked files, exact names** (`app/fetch.go`
`ensureGuestFiles`): `guest-manifest.json`, `build-spec.json`,
`vmlinuz-linux`, `initramfs-linux.img`, `rootfs.ext4`, `rootfs.ext4.zst` —
every one must carry a valid SHA256 in the release `SHA256SUMS`, which the
launcher authenticates first. Receipt (`install-state.json`,
`app/install_state.go`) binds release identity + manifest digest + per-file
size/mtime; the builder emits the files, the pipeline emits the sums.

**F2. build-spec.json** — the Go struct (`app/main.go:76-84`) requires
exactly `runtime.kernelCommandLine` and `runtime.storage.expandedSizeMiB`;
`scripts/release/smoke-guest.py:77` also reads `kernelCommandLine`; backup
archives the file (`app/backup.go:48`). Everything else in the schema is ours
to author (the Omarchy spec proves the shape: image/guest/supply-chain/runtime
sections). Required content decisions:

- kernel command line pattern `root=/dev/vda rw rootwait console=tty0
  console=hvc0 ...` — the launcher rewrites `console=hvc0`→`console=ttyS0`
  and appends `savantos.*` words (`app/main.go:593-603`). The image is a
  **plain unpartitioned ext4 filesystem**: root IS /dev/vda.
- guest-facing words use the `savantos.*` namespace (e.g. `savantos.qemu=1`
  replacing upstream's `omarchy.qemu=1`); VM tuning inherited from the proven
  spec (`loglevel=4`, `systemd.show_status=false`, `mitigations=off`,
  `nowatchdog`).
- `storage.expandedSizeMiB` (24 GiB today) — `prepareDisk`
  (`app/qemu.go:152-273`) sparse-copies `rootfs.ext4` to `vm/disk.raw` and
  truncates to this size.

**F3. The image must grow itself at boot.** `prepareDisk` only truncates the
file; the guest extends ext4 to the disk size (`app/qemu.go:160-161` names
the existing mechanism: systemd-growfs-root). Without a grow unit the image
ships with no writable headroom.

**F4. A userspace readiness unit is part of the payload contract's lifecycle.**
Update commit (`commitPayloadUpdates`, `app/payload_update.go`) fires only
when "the guest's userspace readiness service reaches the lifecycle
listener"; a Phase-1 image needs its `savantos-ready` equivalent or updates
never confirm.

**F5. Kernel/initramfs output names are fixed** (`-kernel guest/vmlinuz-linux`,
`-initrd guest/initramfs-linux.img`, `app/qemu.go` buildQemuArgs) regardless
of which kernel package provides them (linux-zen installs
`vmlinuz-linux-zen`) — the builder renames at assembly.

**F6. Minimum viable boot set inside the image:** virtio_blk/virtio_pci,
ext4 in the initramfs or kernel; a rootfs population path; the readiness
unit; sshd-per-boot consumption of the launcher's `savantos.ssh.*` cmdline
words (dev loop depends on SSH verification).

**F7. Local verification path for pre-release builds** (no GitHub release
exists yet): the launcher's download path is URL-driven
(`normalizedRelease(release)+"/"+name`, `app/fetch.go`) with the trusted
manifest digest passed by flag — so the honest full-path E2E is a **local
release base**: serve SHA256SUMS + the six files over loopback HTTP, pass
`-release`/manifest-digest flags, and let the *unmodified* launcher download,
authenticate, unpack, receipt, boot. No fabricated receipts; the trust chain
is exercised end to end.

## Proposed Solution

### Approach

Four workstreams, ordered to de-risk the control plane before aesthetics
(Deep Research build order, durations treated as pacing not schedule):

1. **Phase 1 — Builder (next):** `guest-image/` in-tree builder: mkosi config
   pinning Arch (snapshot-pinned mirror timestamp in a lock file), rootless
   directory build; assembly step emitting the six contract files (mke2fs -d
   with fixed label `savantos-factory` + fixed UUID; kernel/initramfs renamed
   per F5; zstd-compressed twin per F1); grow unit (F3); readiness unit (F4);
   minimal ssh-per-boot consumption (F6); dual-build digest-compare gate;
   local-loopback release base (F7) proving boot through the unmodified
   launcher in the dev VM. Launcher kernel flag policy (`-cpu host` vs
   x86-64-v3+enlightenments) benchmarked separately — the builder does not
   gate on it.
2. **Phase 2 — Desktop:** Plasma 6 Wayland profile: Aurorae traffic-lights
   decoration + colors from savant-code's palette; Kiosk `[$i]` immutable
   system-wide defaults; Electron decoration/accessibility env; virtio-gpu
   (venus) with llvmpipe fallback flag; virtiofs evaluation for the host share.
3. **Phase 3 — Agent control plane:** Savant Core as systemd user daemon; input
   adapter (EIS primary → portal fallback); AT-SPI2-first interaction with
   ScreenShot2 vision fallback; safety law implemented as designed in ruling 2;
   Kirigami layer-shell UI; cursor yielding; crash-resilient daemon.
4. **Phase 4 — Factory & trust:** casync + sysupdate deltas (byte-range support
   verified on GitHub Releases first); contract gate rebuilt for mkosi
   (Docker-run Linux); release.yml re-pointed; launcher probes (AVX2, Vulkan 1.3,
   metered) extended; Omarchy kill list executed on sign-off.

### Steps

1. Phase 1 scaffolding (begins only after this FID's loop converges): mkosi
   manifest + assembly script + snapshot lock + reproducibility gate +
   contract file emitter + local release base + dev-VM boot proof.
2. Phases 2–4 per workstream above; each lands contract-gated and direct-pushed
   per the 3c flow.
3. Kill-list execution: single operator-signed-off change removing
   `guest-build/` + Omarchy derivations, with CHANGELOG record.

### Verification

- Every phase: repo gates (`go build/vet/test`, markdownlint) + Docker contract
  run of the builder tree + live boot in the dev VM.
- Phase 1 exit: a fresh dev data dir, pointed at the local release base, boots
  the new raw image to a shell via the *unmodified* launcher — download,
  digest verification, receipt, `prepareDisk`, grow, readiness all observed.
- Phase 3 exit: live demo — agent injects input via EIS, reads AT-SPI2 tree,
  kill switch severs it — in the dev guest.
- Phase 4 exit: full release cycle (prepare → pin → publish) producing the first
  Plasma-based signed release; smoke test on a fresh data dir.

## Verification Gates

(Implementation milestone evidence pasted above, 2026-09-12 — Phase 1.)

```markdown
- gate: build (cd app && go build ./...)
- gate: vet (cd app && go vet -unsafeptr=false ./...)
- gate: test (cd app && go test ./...)
- gate: fmt (gofmt -l .) — empty output
- gate: docs (markdownlint on changed *.md)
- gate: contract (Docker: mkosi build ×2 → digests equal; six-file contract
  emitter output verified against SHA256SUMS; boot smoke via dev VM + local
  release base)
```

## Missed Questions

1. **Does deleting `guest-build/` orphan old releases?** No — releases pin their
   payloads as release assets, not repo paths; v0.0.1/v0.0.2 remain verifiable.
2. **Do existing dev-VM data disks survive the pivot?** Yes (operator 3c ruling:
   data dir persists); they self-obsolete as the new image replaces the dev
   payload — persisted user data is the thing we preserve, which is the point.
3. **Does the launcher need code changes for mkosi images?** No — F1–F5 are the
   complete interface and none of it requires launcher edits. Any discovered
   drift becomes an explicit launcher PR, never a silent contract bend.
4. **Where does the builder live?** In-tree (`guest-image/`), same repo, same
   PR-less direct-push flow — separate repos at this scale add friction, not
   isolation. Revisit only if build times hurt CI.
5. **Partitioned or plain image?** Plain unpartitioned ext4 — `root=/dev/vda`
   is the shipped contract and the upstream image proves the shape boots under
   WHPX. mkosi's disk formats emit partition tables and would break it; hence
   directory build + mke2fs -d (Loop-1 correction).
6. **Can the builder stay rootless?** Yes for the package install (mkosi
   directory build uses user namespaces); mke2fs -d needs no root either. CI
   runs in Docker with `--privileged` avoided; the current build-guest.sh
   already demonstrates the container pattern.
7. **How does the image handle `-instant`, `-ssh`, `-share`, locale words?**
   The kernel cmdline carries them (`app/main.go:597-603`); the image's init
   consumes `savantos.*` words. Phase 1 implements ssh-per-boot + readiness;
   instant/share/locale ride existing integration set code ported in Phase 2.
8. **What about `guest-manifest.json` contents?** Authenticated artifact sizes
   are read from it (`readGuestArtifactSizes`, `app/fetch.go`) for disk
   preflight — the emitter generates it with sizes + digests of the five other
   artifacts.

## Perfection Loop

### Loop 1 — RED

- **RED:** (1) FID v1 claimed `root=LABEL`; the shipped contract is
  `root=/dev/vda` with a plain unpartitioned ext4 (verified: dev data dir
  `build-spec.json` kernelCommandLine; `prepareDisk` copies rootfs.ext4
  verbatim as the boot disk). (2) FID v1 specified "mkosi + systemd-repart
  raw ext4 output"; mkosi disk formats are partitioned and would break the
  contract — corrected to mkosi directory build + `mke2fs -d` assembly.
  (3) FID v1 omitted: six-file contract enumeration (F1), build-spec.json
  authoring requirements (F2), grow-at-boot unit (F3), readiness unit (F4),
  fixed kernel names (F5), minimal boot set (F6), and the pre-release
  verification mechanism (F7 — local release base, no fabricated receipts).
- **GREEN:** Contract section written from code evidence; approach and steps
  rewritten; missed questions 5–8 added.
- **AUDIT:** Every contract claim cites file:line (F1–F7 section). The real
  build-spec.json from the live dev data dir was read and compared field by
  field against `app/main.go`'s parse.
- **ADVERSARIAL:** "Maybe mkosi *can* emit plain ext4?" — formats are
  directory/tar/cpio/esp/sysext/disk(gpt_*); no plain-fs output. And
  `mke2fs -d` is the same mechanism upstream's own builder used to produce
  the shipped image shape, so the assembly path has production precedent.
- **CHANGE DELTA:** ~45% (contract section + approach rewrite).

### Loop 2 — Independent audit and self-correction

- **RED:** Swept the launch path end to end for further unmodeled coupling:
  (a) `-no-update` does NOT bypass `ensureGuest` — a fresh data dir still
  downloads/authenticates from the release base, confirming F7 is the only
  honest pre-release boot path; (b) `savantos.instant=1`, ssh, share, locale
  words are appended unconditionally — a Phase-1 image that ignores them must
  still boot (unknown cmdline words are inert), so no ordering hazard; (c)
  `memoryStarved`/`nestedVirtRefused` retry logic is payload-agnostic.
- **GREEN:** F7 wording tightened (flags exist for release + trusted manifest
  digest; local HTTP base suffices; `-no-update` only suppresses the *check*,
  not first-run provisioning). Step 1 scoped to include the local base.
- **AUDIT:** `app/main.go:545-603` re-read; flag wiring confirmed.
- **ADVERSARIAL:** "Why not fake an install-state.json receipt instead of the
  HTTP base?" — because fabricating a receipt bypasses exactly the trust
  machinery (sums authentication, digest verify, mtime binding) that Phase 1
  is supposed to prove; the F7 path exercises all of it with zero launcher
  changes and zero trust shortcuts.
- **CHANGE DELTA:** ~8%.

### Loop 3 — Final convergence

- **RED:** Residual risks named: mke2fs -d determinism (timestamps inside the
  tree) is unproven until the dual-build gate runs; mkosi-on-Arch-in-Docker
  layer versions shift; readiness semantics for update-commit are inferred
  from comments and one call site, not yet from the unit's source.
- **GREEN:** All three are Phase-1 exit criteria (dual-build gate, pinned
  mkosi/snapshot locks, readiness unit ported from the patch train's
  `savantos-ready` where the exact listener contract is visible), not open
  design questions. No further FID text changes needed.
- **AUDIT:** Convergence declared with risks assigned to verification rather
  than assumption.
- **ADVERSARIAL:** The strongest remaining challenge — "the readiness contract
  is inferred" — is answered by making the port of `savantos-ready` (with its
  listener protocol) a named Phase 1 deliverable rather than an assumption.
- **CHANGE DELTA:** ~3%.

**Convergence declared:** three loops, deltas 45% → 8% → 3%, RED items resolved
or converted into named exit criteria.

## Phase 1 Implementation Evidence (landed 2026-09-12)

All Phase 1 steps **implemented**. Builder: `guest-image/` (build.sh → mkosi 27
rootless directory build on the date-pinned Arch snapshot → assemble.sh
mke2fs tar-stream assembly → dual-build digest gate → SHA256SUMS + release
base). No deferrals.

- **F1 (six-file contract):** all six emitted verbatim; guest-manifest carries
  authenticated sizes for the disk-space preflight.
- **F2 (plain ext4, root=/dev/vda):** mke2fs over a name-sorted GNU tar stream
  (`--sort=name`, fixed epoch, fixed UUID/label/hash-seed).
- **F3 (grow at boot):** systemd-growfs-root drop-in + preset policy; proof below.
- **F4 (readiness):** `savantos-ready` ported with the `10.0.2.2:4450` listener.
- **F5 (fixed names):** linux-zen kernel/initramfs renamed to contract names.
- **F6 (minimal boot set):** base + linux-zen + openssh + networkd; no desktop.
- **F7 (honest boot path):** loopback release base serving the contract dir +
  the real v0.0.1 WINQ-EMU archive; unmodified launcher, no fabricated state.

**Determinism gate (build 18):** dual independent builds byte-identical across
all six files. Nondeterminism the gate caught and killed along the way: SSH
host keys (now generated at first boot by the sshd unit's ExecStartPre),
random chpasswd salt (fixed salt), shadow's `-` backup carrying a stale hash
(ordering fix), glibc ldconfig aux-cache, mkosi's post-postinst
`/boot/arch` modules-initrd (deleted pre-tar), per-volume readdir order
(tar-stream population), and mke2fs wall-clock superblock stamps
(`SOURCE_DATE_EPOCH`).

**Boot proof (the launcher's own log + guest probe):**

    17:29:13 runtime archive unchanged in v0.0.1; kept the installed runtime
    17:29:27 booting - GPU accelerated (virgl + Venus Vulkan) (attempt 1)
    17:29:37 guest userspace announced ready
    $ ssh -p 2223 savant@127.0.0.1
    SSH-OK / savantos / 7.1.7-zen1-1-zen / running / /dev/vda 24G 1.4G 22G 7% /

**Late find, fixed and re-proven:** the first boot-proof round reached the
login prompt but SSH refused pubkey auth. Forensics on the mounted image:
`/home/savant` was `root:root 0700` — `useradd -m` ran inside mkosi's
id-mapped sandbox, which rewrites non-root ownership to root, and sshd's
StrictModes correctly refuses a home the user cannot traverse. Fix:
assemble.sh reasserts the account's uid/gid (read from the image's own
passwd/group) on the home tree outside the sandbox, and the tar stream no
longer overrides ownership. Verified in-image (`1000:1000` == passwd) and
end-to-end (SSH-OK above).

## Lessons Learned

Verify an external report's load-bearing claims against the live system before
adopting its red-team (the EIS interface was real; its state-destruction premise
was not). Architecture arguments end when someone boots the thing — and design
documents end when someone reads the code that consumes them: the payload
contract in this FID was corrected from the launcher's source, not from memory.

## Resolution

- **Closed Date:** 2026-09-12 (Phase 1)
- **Fix Description:** First-party builder landed; Phase 1 scope complete.
- **Tests Added:** guest-image dual-build determinism gate (build.sh); boot
  proof via boot-proof.sh flow (fresh data dir + local release base).
- **Verification Evidence:** see Implementation Evidence above (gate digests +
  launcher log + guest SSH probe).
- **Archived:** — (Phase 2/3 continue under new FIDs)

## Implementation Evidence (REQUIRED for `closed`)

> To be filled at closure: commit SHAs, file:line of the builder surfaces,
> pasted gate output (including the dual-build digest match and the dev-VM
> boot proof), and step statuses — every step `implemented`, `blocked`, or
> `deferred` (operator-approved only). No silent deferrals.
