# FID: Window close is broken — PowerDevil blocks the ACPI power key

**Filename:** `FID-2026-0914-003-window-close-powerdevil.md`
**ID:** FID-2026-0914-003
**Severity:** high
**Status:** proven — landed `bd2e62f` (seed in finalize.sh, identity-apply.sh
and skel) and `40f36ff` (assemble.sh value probe); close-flow proof passed
2026-09-15 on the first image built from this tree
**Created:** 2026-09-14
**Parent:** FID-2026-0912-002 (Phase 2 desktop) — its "restart/shutdown
path" premise item; defect discovered live 2026-09-14

---

## Summary

On the first-party Plasma image, closing the SavantOS window (the
product's normal shutdown gesture) does not work: the close guard confirms,
QEMU raises the ACPI power-down, logind logs `Power key pressed short` —
and the guest never powers off. QEMU stays alive and the window stays on
screen. Root cause, experimentally verified twice in the same boot: the
PowerDevil daemon ships with the desktop and takes a **`block` inhibitor
on `handle-power-key`** ("KDE handles power events"), intending to show
its own on-screen power dialog — which is unreachable when the shutdown
gesture comes from the host's close button. The builder ships no override,
so every factory image would ship this defect.

## Environment

- **OS:** Windows 11 host; Arch Linux guest (Plasma 6.7, first-party
  `~/savantos-phase1` image, 2026-09-13 build)
- **Commit/State:** working tree 2026-09-14; observed through the
  unmodified launcher (dev build of clean `app/` at `717bb15`)

## Detailed Description

### Contract being violated

`app/closeguard.go`: the window's X (and Alt+F4) is intercepted,
confirmed with the user, and executed as a **graceful guest shutdown over
QMP `system_powerdown`** — "the guest shuts down; the supervisor reaps as
usual." The X itself does nothing by design (`window-close=off`); the
entire close flow terminates in the guest's ACPI power-button handler.

### Root cause (evidence)

1. **The event arrives.** Guest logind journal: `Power key pressed short`
   at 18:18:37, 18:21:30, 18:22:23 — all three close attempts.
2. **The event is blocked.** `systemd-inhibit --list`:
   `PowerDevil (org_kde_powerdevil, pid 719) … handle-power-key:
   handle-suspend-key: handle-hibernate-key: handle-lid-switch … block`.
   `HandlePowerKey` is at its commented default (`poweroff`) — the
   inhibitor, not the config, eats the event.
3. **Removing the inhibitor restores the contract.** Same boot, same
   command: killed `org_kde_powerdevil` → inhibitor gone → QMP
   `system_powerdown` → guest powered off and QEMU exited within seconds.
   (PowerDevil is not a systemd user unit here — `powerdevil.service` is
   not loaded — so it must be removed or configured, not stopped.)

### Dependency fact (checked on the pinned snapshot, container probe)

`plasma-workspace` does NOT depend on powerdevil; the dependency runs the
other way (`powerdevil Depends On: … plasma-workspace …`). Removing
powerdevil from the Phase-2 package set violates nothing upstream. The
Phase-2 FID's plan listed powerdevil under "Restart/shutdown:
powerdevil + polkit-kde-agent + systemd-logind integration" — the live
experiment shows the opposite contribution: it breaks the host-driven
shutdown path. In-guest Leave/shutdown works via plasma-workspace's exit
dialog + polkit-kde-agent + logind, no powerdevil involved.

## Impact Assessment

### Affected Components

- `guest-image/mkosi.conf` (Phase-2 package block: `powerdevil`)
- Phase-2 FID premise (restart/shutdown path)
- Launcher contract unchanged (`app/closeguard.go` is correct as built)

### Risk Level

- [x] High: the normal window-close gesture silently does nothing on
      every factory image; users would need the in-guest menu (unreachable
      from the host gesture) or a hard kill (which the close guard exists
      to prevent).

## Proposed Solution

**Option A (recommended): drop `powerdevil` from `mkosi.conf`.** An
appliance in a VM has no battery, lid, or brightness keys — power
management is meaningless here — and the dependency analysis shows nothing
else pulls it in. One-line deletion; the in-guest shutdown menu keeps
working through logind + polkit-kde-agent. Annotate the Phase-2 FID's
premise (ButtonsColor precedent: verified in-guest, not assumed).

**Option B (chosen by operator ruling, 2026-09-14): keep powerdevil,
configure it.** Pre-seed PowerDevil's power-button action to Shutdown so
its handler performs an immediate clean shutdown instead of inhibiting.
Keeps battery/brightness machinery for a future portable use.

CORRECTION during implementation: this option originally sketched the key
as `buttonAction=2`. Source verification against the exact image version
(PowerDevil v6.7.4, `daemon/powerdevilcore.cpp` + the generated
`PowerDevilGlobalSettings` reader) fixed both halves: the file is
`powermanagementprofilesrc`, the group `[AC][HandleButtonEvents]`, the key
`powerButtonAction`, and the enum value **8 = Shutdown**. The same source
shows PowerDevil auto-detects VMs and adjusts profile defaults, so the
seed is asserted for the AC profile explicitly (VMs report AC power only —
no battery device in the launcher's QEMU flags); runtime proof on the
first fixed image re-verifies the live inhibitor state either way.
Repeated `--group` nesting is the documented kwriteconfig6 form (Arch
Wiki power-management examples). Implemented in the established
factory-default pattern:

### Verification

- Builder: `--contract-only` + dual-build digest gate green after the
  change; assemble.sh probes unchanged (powerdevil was never probed).
- Live: fresh boot → host-side window close (or QMP `system_powerdown`)
  → guest powers off and QEMU exits without touching any guest process.
- `systemd-inhibit --list` in the new image shows no `handle-power-key`
  blocker.

## Verification Gates

> Run at implementation time.

- gate: `scripts/release/build-guest.sh --contract-only`
- gate: full dual-build determinism run at next image build
- gate: live close-flow proof in the dev VM (above)

## Perfection Loop

### Loop 2 (2026-09-14, first-image build session)

Context: the fixed image build (dual-build gate) was launched to produce
the artifact the live close-flow proof needs.

- **RED:** Build died at the new value probe — `assemble: power-button
  shutdown seed missing or wrong (expected powerButtonAction=8)` — while
  the existence loop one line above had just "passed".
- **DIAGNOSIS (forensics on the leftover artifact, pasted evidence):**
  1. `debugfs -R "cat …" rootfs.ext4` in a container against the leftover
     image: `[AC][HandleButtonEvents]` / `powerButtonAction=8`, 45 bytes,
     mode 0600 — the seed is byte-perfect; the seed was never the problem.
  2. The exact probe pipeline under `set -euo pipefail`, 10 runs: 10/10
     ok — SIGPIPE/pipefail false-positive eliminated.
  3. `debugfs -R "stat …" /nonexistent/image.ext4; echo $?` → **exit 0**
     — debugfs succeeds against a missing image file.
  4. In `assemble.sh` the `mv "$img" "$out/rootfs.ext4"` sat ABOVE the
     assertion block, so every probe targeted a path that no longer
     existed at probe time. All existence probes passed **vacuously**
     since the block landed (uncommitted working tree; absent at
     `717bb15` — verified via `git show`). The value probe was the only
     assertion strict enough to fail on empty stdout, and its failure is
     what exposed the latent bug.
  5. Independent blocker found in the same run: `mkosi.conf:124`
     `noto-fonts` at column 0 inside the package list — mkosi parses it
     as a config key (`‣ Setting noto-fonts must be followed by '='`),
     fatal. Every prior build predated this line; the Sep 13 image
     escaped it. Fixed (indentation restored) and disclosed as the
     previously-logged out-of-scope formatting defect now escalated to a
     live build blocker.
- **GREEN:** assemble.sh reordered — image-existence guard → existence
  probes → value probe → rename → compress. `bash -n` green on assemble.sh
  and build.sh. Build relaunched.
- **AUDIT:** Every claim above cites pasted tool output. The vacuous-pass
  mechanism is reproduced, not inferred.
- **ADVERSARIAL:** "Just loosen the probe" — no: the probe was right, the
  plumbing around it was wrong. "The value probe saved us from nothing
  real" — the opposite: it validated the seed byte-for-byte in the real
  image AND exposed a gate that could never fail. "Fix the indentation in
  mkosi.conf silently" — disclosed here and in SCOPE per the
  out-of-scope-escalation rule.
- **CHANGE DELTA:** ~6% of the FID (this loop + the Resolution note).
- **STATUS:** build relaunched; the close-flow proof runs on the first
  image this build produces.

### Loop 1 (2026-09-14, diagnosis session)

- **RED:** Close flow broken; event-vs-inhibitor question answered with
  journal + `systemd-inhibit` evidence; dependency direction verified on
  the snapshot.
- **GREEN:** Fix decomposed to A/B with a recommendation; both verifiable
  by the same live proof.
- **AUDIT:** Every claim cites tool output reproduced above.
- **ADVERSARIAL:** "Just set HandlePowerKey=poweroff in logind.conf" —
  it already is the default; the inhibitor bypasses the handler, so a
  config no-op would be a false fix. "PowerDevil re-spawns" — it did not
  return during the verification window; on the fixed image it is absent
  entirely.
- **CHANGE DELTA:** ~5%.
- **STATUS:** analyzed; fix awaits operator pick (A/B), then one-line
  implementation + gates.

## Resolution

- **Closed Date:** — (closes only after the live close-flow proof below)
- **Fix Description:** Operator chose Option B. Landed 2026-09-14 in the
  working tree:
  1. `guest-image/finalize.sh` — `kwriteconfig6 --file
     /etc/skel/.config/powermanagementprofilesrc --group AC --group
     HandleButtonEvents --key powerButtonAction 8` (factory seed for new
     accounts; the payload's later `cp -a /etc/skel/.config /home/savant/`
     carries it to the factory account at build time).
  2. `guest-image/skeletons/usr/lib/savantos/identity-apply.sh` — the same
     key re-asserted on every login (covers accounts predating the skel
     plant; KConfigWatcher applies it live).
  3. `guest-image/assemble.sh` — content assertion extended: ships
     `/etc/skel/.config/powermanagementprofilesrc` (existence) plus a
     value probe (`powerButtonAction=8` read back through debugfs) so a
     silently-wrong seed — the exact regression this FID records — is
     unshippable, not just a missing file.
- **Tests Added:** assemble.sh existence + value probes (above).
- **Verification Evidence:** `bash -n` green on all three scripts; LF
  line endings confirmed (the CRLF lesson); `build-guest.sh
  --contract-only` exit 0; root cause + fix mechanism proven live in the
  same boot (inhibitor present: 3 ignored powerdowns; inhibitor released:
  identical powerdown shut the guest down in seconds).
- **Owed (gates the FID's own Verification section names):** full dual-
  build determinism run and the live close-flow proof on the FIRST image
  built from this tree — fresh boot → QMP `system_powerdown` (the exact
  event that failed) → guest powers off, QEMU exits, and
  `systemd-inhibit --list` shows no `handle-power-key` blocker. Note the
  working tree is uncommitted; the proof must boot a build of this tree,
  not the Sep 13 disk.
- **Archived:** —

### Loop 3 (2026-09-15, close-flow proof on the first built image) — PROVEN

- **Image:** full dual-build run of this tree (gate green, all six digests
  matched; the build's publish step initially died on a Windows
  file-lock — the loopback HTTP server holding `out/contract` — and was
  completed by re-running the publish tail; determinism verdict
  unaffected). Payload: rootfs `06715df6…`, sums digest `eaa8bc9d…`,
  provisioned by the unmodified launcher from a loopback release base;
  fresh-disk first boot ready in ~12 s.
- **Pre-powerdown state (Option B exactly as designed):** user config shows
  `[AC][HandleButtonEvents] powerButtonAction=8`; PowerDevil RUNNING
  (`/usr/lib/org_kde_powerdevil`, pid 773) and holding the
  `handle-power-key` `block` inhibitor; healthy Plasma session (plasmashell
  ×1, kwin ×2).
- **The proof:** one QMP `system_powerdown` (the event that was swallowed
  three times on 2026-09-14 with the old, unseeded config) → POWERDOWN at
  11:46:20 → **QEMU exited in ~5 s**, ports 2222/4450 released, launcher
  exited cleanly. The seed converts the ACPI power key into a real
  shutdown WITHOUT removing PowerDevil — both root-cause halves
  (inhibitor present + unseeded config) are now addressed by the fix.
- **New finding (recorded here, hardening follow-up):** the shipped image
  carries `/usr` and `/usr/share` as mode **0777** (world-writable). Seen
  as pacman "directory permissions differ" warnings during the keyring
  proof; confirmed by debugfs on the published rootfs. For a factory
  appliance this is a permissions-hardening defect; fix belongs in the
  builder (assemble-time mode normalization), not the skeleton.
- **New finding (launcher UX):** `-fresh` with an existing disk blocks on
  `confirmResetBackup` — a GUI dialog unreachable in headless automation
  (the reset never started; no staging dir). Worked around by hand
  (retention rename + relaunch without `-fresh`); a `-yes`/headless flag
  or a probe-bypass is the launcher-side follow-up.
