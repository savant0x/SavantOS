# Session Summary: 2026-09-12 (pivot + Phase 1 landing)

**Session ID:** 2026-09-12-pivot-and-phase1-first-party-builder
**Duration:** 2026-09-12 (pivot FID filed through Phase 1 boot proof;
summary backfilled 2026-09-14 per `session.auto_summary`)
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 host (Git Bash + PowerShell toolchain)
- **Language/Runtime:** Go launcher (`app/`); bash builder tooling
- **Branch:** main
- **Last Commit at Start:** dc60704 (Gemini Deep Research brief for the
  pivot) — the pivot debate was already running on disk.
- **Session lineage:** governed by `dev/echo-v0.1.2-single-agent.md`
  (single-agent ECHO v0.1.2).

### Known Issues

- The 48-patch Omarchy git-am patch train had hit its maintainability
  ceiling; the operator was weighing "wipe and restart" vs surgical
  replacement.
- The Deep Research brief's two load-bearing claims (EIS control plane;
  state destruction on A/B swap) were unverified.

---

## Planned Work

1. [x] Verify the brief's load-bearing claims against the live system
       before adopting anything (EIS busctl probe; state-decoupling read
       of `app/backup.go`).
2. [x] Reconcile the brief ADOPT/ADAPT/REJECT (`dev/research-reconciliation.md`).
3. [x] Operator rulings recorded (Law 2): reconciliation binding, safety
       law confirmed, pivot green-lit, NO-WIPE ruling.
4. [x] File FID-2026-0912-001 and run the full perfection loop to
       convergence BEFORE building (operator directive).
5. [x] Build Phase 1: first-party `guest-image/` builder.
6. [x] Boot proof through the unmodified launcher.

---

## Work Completed

### Research reconciliation + pivot FID

- **Status:** completed
- **FIDs:** FID-2026-0912-001 (critical)
- **Changes:** `dev/research-reconciliation.md` (live-verified EIS real,
  state-destruction premise false); FID filed with operator rulings
  verbatim, NO-WIPE ruling (surgical retirement, kill list gated on
  sign-off), payload contract F1–F7 derived from launcher source
  (`app/fetch.go`, `app/main.go`, `app/qemu.go`) — not from memory; three
  perfection loops (deltas 45% → 8% → 3%) converged the same day.
- **Verification:** every contract claim cites file:line; Loop-1 RED
  corrected the FID's own `root=LABEL` error and the mkosi
  disk-format error to directory build + `mke2fs -d`.

### Phase 1: first-party builder

- **Status:** completed
- **Commits:** 458a6a0 (perfection-loop convergence), 717bb15 (Phase 1
  landing).
- **Changes:** `guest-image/` — `build.sh` (mkosi 27 rootless directory
  build on the 2026-08-11 snapshot, `snapshot.lock.json` +
  `check-snapshot-lock.sh`), `assemble.sh` (mke2fs tar-stream assembly,
  fixed UUID/label/epoch), `finalize.sh`, dual-build digest gate,
  `sandbox/pacman.conf` fetch tuning after "Operation too slow" build
  failures; contract emitter (six files + SHA256SUMS + `release-base.json`).
- **Verification:** determinism gate build 18 — dual independent builds
  byte-identical across all six files; the gate caught and killed SSH
  host keys, chpasswd salt, shadow backup, ldconfig aux-cache, mkosi
  `/boot/arch` initrd, readdir order, and superblock wall-clock stamps.

### Boot proof (F7 honest path)

- **Status:** completed
- **Evidence:** fresh data dir + local release base; unmodified launcher
  downloaded, authenticated, unpacked, receipted, booted GPU-accelerated
  attempt 1; `guest userspace announced ready`; SSH-OK probe with
  zen kernel + `/dev/vda 24G`. Late find fixed: mkosi id-mapping
  broke `/home/savant` ownership (root:root 0700) and sshd StrictModes
  correctly refused it — assemble.sh reasserts uid/gid outside the
  sandbox; re-proven end-to-end.

---

## Validation Results

- [x] `go build ./...`, `go vet -unsafeptr=false ./...`, `go test ./...`,
      `gofmt -l .`: PASS (repo gates per protocol.config.yaml)
- [x] Dual-build determinism gate: PASS (six digests equal)
- [x] Boot proof via dev VM + local release base: PASS

---

## Lessons / Handoff

- Phase 2 (Plasma desktop) continues under FID-2026-0912-002; phases 3–4
  tracked in FID-2026-0914-001/-002 (filed 2026-09-14 after the folder
  audit found the tracking gap).
- The working tree after this session carries the Phase 2/identity bake
  UNCOMMITTED — see the 0913 summary.
