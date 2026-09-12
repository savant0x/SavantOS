# FID: First-party OS pivot — mkosi builder, Plasma guest, Omarchy retirement

**Filename:** `FID-2026-0912-001-first-party-os-pivot.md`
**ID:** FID-2026-0912-001
**Severity:** critical
**Status:** analyzed
**Created:** 2026-09-12 00:00
**YAGNI-Compliance:** Verified

---

## Summary

Operator-approved pivot of the SavantOS guest from the Omarchy/Hyprland fork
(48-patch git-am train against a pinned upstream builder repo) to a **first-party
guest builder**: plain Arch base assembled with **mkosi + systemd-repart**,
**KDE Plasma 6 (Wayland)** desktop, the traffic-lights identity as native KWin
theming, and the Savant agent embedded as a first-class peer via the verified
KWin EIS + AT-SPI2 control plane. The host/launcher/hypervisor layer (Go, WHPX,
virtio) is explicitly **unchanged**. The Gemini Deep Research brief and its
reconciliation (`dev/gemini-deep-research-prompt.md`,
`dev/research-reconciliation.md`) are adopted as binding design inputs per the
operator's rulings.

## Operator rulings (ECHO Law 2 — recorded verbatim)

1. **Reconciliation adopted** — `dev/research-reconciliation.md` ADOPT/ADAPT/REJECT
   lists become binding design decisions.
2. **Agent safety law confirmed** — tiered approvals (read = silent, project writes =
   logged, destructive/network/shell = out-of-band human approval); un-hideable audit
   overlay; kill switch severing the agent's input channel; agent confined to an
   unprivileged identity that cannot modify its own permissions.
3. **Pivot green-lit** — this FID filed; Phase 1 starts now; Omarchy retirement plan
   (below) returns for final sign-off before any removal executes.

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

## Proposed Solution

### Approach

Four workstreams, ordered to de-risk the control plane before aesthetics
(Deep Research build order, durations treated as pacing not schedule):

1. **Phase 1 — Builder (now):** `savantos-guest` builder repo/realm in-tree:
   mkosi config pinning Arch (snapshot-pinned mirror timestamp in a lock file),
   systemd-repart raw ext4 output consumable by the launcher's direct-kernel
   boot (root=LABEL), linux-zen kernel, trademark-stripping stage, dual-build
   digest-compare gate. The launcher's payload contract (file names + digests +
   manifest) is the interface; the builder must satisfy it unchanged.
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

1. Phase 1 scaffolding: mkosi manifest + repart definitions + snapshot lock +
   reproducibility gate, proven by building a bootable raw image the dev VM can
   direct-kernel-boot. *(this FID's first implementation commit)*
2. Phases 2–4 per workstream above; each lands contract-gated and direct-pushed
   per the 3c flow.
3. Kill-list execution: single operator-signed-off change removing
   `guest-build/` + Omarchy derivations, with CHANGELOG record.

### Verification

- Every phase: repo gates (`go build/vet/test`, markdownlint) + Docker contract
  run of the builder tree + live boot in the dev VM.
- Phase 1 exit: new raw image boots to a shell in the dev VM via the *unmodified*
  launcher payload path.
- Phase 3 exit: live demo — agent injects input via EIS, reads AT-SPI2 tree,
  kill switch severs it — in the dev guest.
- Phase 4 exit: full release cycle (prepare → pin → publish) producing the first
  Plasma-based signed release; smoke test on a fresh data dir.

## Verification Gates

(To be pasted at implementation milestones; none claimed yet — status `analyzed`.)

```markdown
- gate: build (cd app && go build ./...)
- gate: vet (cd app && go vet -unsafeptr=false ./...)
- gate: test (cd app && go test ./...)
- gate: fmt (gofmt -l .) — empty output
- gate: docs (markdownlint on changed *.md)
- gate: contract (Docker: mkosi build ×2 → digests equal; boot smoke in dev VM)
```

## Missed Questions

1. **Does deleting `guest-build/` orphan old releases?** No — releases pin their
   payloads as release assets, not repo paths; v0.0.1/v0.0.2 remain verifiable.
2. **Do existing dev-VM data disks survive the pivot?** Yes (operator 3c ruling:
   data dir persists); they self-obsolete as the new image replaces the dev
   payload — persisted user data is the thing we preserve, which is the point.
3. **Does the launcher need code changes for mkosi images?** None planned: the
   payload contract (rootfs.ext4 + vmlinuz + initramfs + manifest digests) is
   preserved; kernel package changes (linux-zen) flow through the same file
   names. Any contract drift becomes an explicit launcher PR.
4. **Where does the builder live?** In-tree (`guest-image/`), same repo, same
   PR-less direct-push flow — separate repos at this scale add friction, not
   isolation. Revisit only if build times hurt CI.

## Lessons Learned

Verify an external report's load-bearing claims against the live system before
adopting its red-team (the EIS interface was real; its state-destruction premise
was not). Architecture arguments end when someone boots the thing.
