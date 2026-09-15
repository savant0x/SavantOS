# Session Summary: 2026-09-12/13 (Phase 2 — Plasma desktop + traffic-lights identity)

**Session ID:** 2026-09-12-phase2-plasma-desktop
**Duration:** 2026-09-12 → 2026-09-13 (summary backfilled 2026-09-14 per
`session.auto_summary`)
**Status:** completed (closure evidence tracked in successor FIDs)

---

## Initial State

### Environment

- **OS:** Windows 11 host; Arch Linux guest
- **Branch:** main @ 717bb15 (Phase 1 landed); Phase 2 built in the
  working tree (uncommitted through the whole session — still true).
- **Session lineage:** single-agent ECHO v0.1.2.

### Known Issues

- The operator's standing complaints about the Omarchy image: no working
  titlebar buttons, no taskbar, no start menu, no desktop icons, residual
  Omarchy branding.
- The dev VM data dir from the Omarchy era was still the one being booted.

---

## Planned Work

1. [x] Verify every package against the pinned 2026-08-11 snapshot
       (extra.files forensics) BEFORE listing it.
2. [x] Extend `mkosi.conf` with the Plasma 6 / SDDM stack.
3. [x] SDDM autologin (Wayland, Relogin) + factory presets +
       display-manager alias.
4. [x] Traffic-lights identity as factory defaults (color scheme,
       konsole profile, wallpapers).
5. [x] Desktop furniture: single bottom panel, start menu, desktop icons,
       restart/shutdown path.
6. [x] assemble.sh content assertion (kwin_wayland, sddm, plasmashell
       presence probes) so a silently-empty desktop can never pass the gate.

---

## Work Completed

### Phase 2 desktop bake (FID-2026-0912-002, status converged)

- **Status:** completed in the working tree 2026-09-12/13; UNCOMMITTED.
- **Changes:** `guest-image/mkosi.conf` Phase-2 package block
  (snapshot-verified); `skeletons/` grew the desktop factory: sddm
  autologin drop-in (`DisplayServer=wayland`, `Relogin=true`),
  `91-savantos-desktop.preset` (system + user), pipewire/wireplumber
  `--global enable` handling in `finalize.sh`, Savant color scheme +
  Konsole profile/colorscheme, `savant-start.svg`, traffic-lights
  wallpapers (deterministic generator); `assemble.sh` presence probes.
- **Plan corrections on the record (perfection loops):** the "native
  Breeze ButtonsColor" premise was REFUTED on KWin 6.7 (only
  AnimationDurationFactor is exposed) — the identity moved to a custom
  QML KDecoration package (`savant-traffic-lights`), re-scoped to
  FID-2026-0913-001 after the operator saw the real desktop fail.

### Omarchy-era leftovers found

- The dev disk's own `autologin.conf` (`Session=omarchy.desktop`) and the
  missing kvantum/papirus in the OLD image were later (2026-09-14 boot
  session) confirmed as legacy-disk artifacts, not builder defects — the
  first-party image carries the correct config.

---

## Validation Results

- [x] Dual-build digest gate on the extended package set: PASS
- [x] assemble.sh content probes: PASS (probe code landed; full gate run
      happens in the container build)
- [x] bash -n on all builder scripts, CRLF scan: PASS
- [x] lint:md on touched docs: PASS
- [ ] Boot proof + rendered proof: owed on next boot (tracked in
      FID-2026-0913-001; boot proof delivered 2026-09-14)

---

## Lessons / Handoff

- Everything from this session remains UNCOMMITTED in the working tree
  (`git status` 2026-09-14: mkosi.conf + skeletons + finalize/assemble +
  release re-point). A path-scoped atomic commit plan is still owed to the
  operator (G1–G9: agent prepares, operator executes).
- Successor evidence tracking: FID-2026-0913-001.
