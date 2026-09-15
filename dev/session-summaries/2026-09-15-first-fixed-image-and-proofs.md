# Session Summary: 2026-09-15 (first fixed image, proofs, glyph fix, commit landing)

**Session ID:** 2026-09-15-first-fixed-image-and-proofs
**Duration:** 2026-09-15 (build watch through commit landing)
**Status:** completed

---

## Initial State

### Environment

- **OS:** Windows 11 host (Git Bash + PowerShell toolchain)
- **Branch:** main at `717bb15` (Phase 1 first-party builder); everything since
  uncommitted per the summaries of 2026-09-12/13
- **VM state:** dev guest down (previous session ended with the Phase-1
  close-flow cleanup); `~/savantos-phase1` provisioned from the Sep-13 image

### Problem Space

Three parallel obligations from the operator: (1) run the full dual-build to
produce the first image built from the fixed tree and collect the owed
FID-2026-0914-002/003 proofs on it; (2) earlier queued probes remained
untouched; (3) the approved path-scoped commit plan awaited execution. During
execution the operator reported a new defect: hover glyphs on the
traffic-light dots off-center.

## Planned Work

1. Dual-build → serve → boot → keyring first-boot proof + close-flow proof.
2. Diagnose and fix the hover-glyph defect.
3. Land the C1–C6 commit plan; FID hash-citing updates after.

## Work Completed

- **Build recovered after a publish-step abort:** the determinism gate itself
  PASSED (six digests printed), then `rm -rf out/contract` died on a Windows
  file lock (the loopback HTTP server serving that dir) and `set -e` stopped
  the script before the copy. Recovery: kill the lock holder, replay the
  publish tail byte-for-byte (disclosed deviation: `RELEASE_NAME/
  VERSION` set to the established `local/phase2-desktop` convention the
  original run's defaults missed). All artifacts verify; sums digest
  `eaa8bc9d…`.
- **mkosi.conf `noto-fonts` column-0 defect** (previously logged cosmetic)
  hit as a LIVE build blocker (`Setting must be followed by '='`) and was
  fixed by restoring the evident indentation.
- **First-launch lesson:** the launcher provisioned the new payload but
  booted the OLD disk — `prepareDisk` retains `vm/disk.raw` across payload
  updates by design. `-fresh` was tried and BLOCKED on the
  `confirmResetBackup` GUI dialog (headless-unreachable; launcher finding).
  Manual retention rename + relaunch without `-fresh` delivered the true
  first boot (~12 s to ready).
- **FID-2026-0914-002 keyring proof PASSED on the first boot:** unit ran
  (guard → `--init`/`--populate`, 38 revoked keys disabled, master key
  2026-09-15), `pacman -Sy && pacman -S tree` signature-verified. Documented
  characteristic: factory images ship empty sync DBs (offline deterministic
  install), so first runtime install needs one `-Sy`.
- **FID-2026-0914-003 close-flow PROVEN:** pre-powerdown state exactly
  Option B (seed live, PowerDevil running, inhibitor present); one QMP
  `system_powerdown` → QEMU exited ~5 s, launcher closed cleanly.
- **Hover-glyph defect FIXED and pixel-proven:** font-glyph hover marks
  replaced by anchored QML primitives in `SavantButton.qml`; spectacle
  `-a` works on the new image (old disk's portal dead-end did not
  reproduce); measured glyph centroids ≤0.5 px from dot center on all
  three dots; zero QML errors in the KWin journal; deployed file
  sha256 == repo file.
- **Commit plan executed:** C1 `34f6fa8` (sandbox pin), C2 `bd2e62f`
  (Phase 2 desktop; absorbed the PowerDevil seed + mkosi fix + a new
  `.gitattributes` LF pin so autocrlf checkouts cannot trip the CRLF
  gate), C3 `40f36ff` (keyring + assemble gates, relocated before the
  rename with an image-existence guard after the value probe exposed the
  vacuous-pass bug), C4 `9e48202` (release re-point; fixes broken CI at
  HEAD), C5 `c2e839b` (FIDs), C6 this summary set.

## Validation Results

- Contract gate (`build-guest.sh --contract-only`) exit 0 pre-commit;
  `py_compile` smoke OK; `lint:md` clean at every docs step.
- Dual-build digest match on all six contract files.
- Both owed proofs passed live (details in the FIDs).

## Lessons

- `set -euo pipefail` scripts die on ANY locked target of an `rm -rf`;
  builder publish steps should tolerate/take the lock explicitly.
- Payload update ≠ disk update: proving an image requires removing the
  writable disk, and `-fresh` is GUI-gated — a headless flag is owed.
- debugfs exits 0 on a missing image file: any debugfs-based gate needs an
  explicit existence guard first.
- The guest-side-script route (share + `sudo bash /mnt/host/x.sh`) remains
  the only reliable privileged path in this environment; `pkill -f` inside
  it must never pattern-match its own shell (use `pgrep -x`-style exactness).
