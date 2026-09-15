# Session Summary: 2026-09-13/14 (identity convergence bake + live deployment + next-boot proofs)

**Session ID:** 2026-09-13-desktop-identity-convergence
**Duration:** 2026-09-13 → 2026-09-14 late sessions (summary backfilled
2026-09-14 per `session.auto_summary`)
**Status:** completed (one evidence item owed, precisely characterized)

---

## Initial State

### Environment

- **OS:** Windows 11 host; Arch Linux guest (Plasma 6.7)
- **Branch:** main @ 717bb15; Phase 2/identity work uncommitted in tree.
- **Trigger:** operator's live-VM screenshots showed four accepted
  identity requirements failing at once (two taskbars — one stuck in
  edit mode; monochrome left titlebar buttons; 24h clock; "built in
  2000" look).

### Known Issues at Start

- The Aurorae SVG decoration path rendered frames but never painted its
  buttons (KSvg FrameSvg contract mismatch).
- `finalize.sh`'s hand-rolled `appletsrc` AND the L&F layout script both
  created panels — Plasma merged them (the two-taskbar root cause).

---

## Planned Work (operator green-lit all four + full build-out)

1. [x] QML `savant-traffic-lights` decoration — dots top-right, true red
       `#ff2d55`, soft glow.
2. [x] `kvantum` + `papirus-icon-theme` + Savant-palette Kvantum config —
       kills the 2000s surfaces.
3. [x] Single panel at the builder source (appletsrc retired; L&F layout
       script = single source of truth).
4. [x] 12-hour clock.
5. [x] Live-first, then bake (screenshot-diff verification in the running
       guest before touching the builder).

---

## Work Completed (FID-2026-0913-001, status fixed)

### Builder bake (10 items, all bash -n / lint / CRLF gated)

- **Status:** completed (uncommitted working tree).
- **Changes:** `savant-traffic-lights` QML KDecoration package
  (Decoration root + `installTitleItem`, SavantButton on the
  DecorationButton idiom after "Insufficient arguments" on Qt 6.7);
  L&F layout script rewritten on the supported `currentConfigGroup`/
  `writeConfig` mechanism (the `addWidget` config-object form is
  silently dropped — the stock-KDE-icon root cause) as the single panel
  source (remove-all + one 48px panel, savant-start icon, 12h clock,
  wallpaper); identity-apply.sh rewritten (re-asserts widget style/icons
  after L&F apply; Kvantum selection guard);
  `identity.service After=plasma-plasmashell.service` (config-restore
  race); `mkosi.conf` += kvantum + papirus-icon-theme (snapshot-confirmed);
  `finalize.sh` appletsrc retired + `$BUILDROOT`-inside-chroot fixes +
  icon-theme.cache determinism cleanup; gen-aurorae.py retired.

### Live deployment (Sep 13/14)

- **Status:** completed — kvantum 1.1.8-1 + papirus-icon-theme
  20260801-1 installed in the guest FROM the pinned snapshot; all
  identity files deployed and verified on disk.
- **Discovery:** the first-party builder installs packages from OUTSIDE
  the image → runtime pacman keyring never initialized → `pacman -S`
  failed signature verification (fixed live: `pacman-key --init` +
  `--populate archlinux`). Operator decision: first-boot keyring-init
  unit → IMPLEMENTED Sep 14 under FID-2026-0914-002.

### Sep 14 (follow-on session): proofs + session bookkeeping

- **Status:** completed.
- **Changes:** FID-2026-0914-001 (Phase 3 agent control plane) and
  FID-2026-0914-002 (Phase 4 factory & trust) filed after the folder
  audit found the tracking gap; FID-2026-0914-002 looped to convergence
  with operator rulings D1–D3; GitHub Releases byte-range CONFIRMED
  (16-byte ranged GETs on live v0.0.1 assets); casync 2 +
  systemd-sysupdate confirmed on the pinned snapshot (container probe).
- **Boot + keyring proofs (dev guest `~/savantos-phase1`, unmodified
  launcher):** system `running`, sddm `active`, plasmashell + kwin
  alive, readiness ~12 s; receipt digests re-verified ALL MATCH against
  the local release base; runtime `pacman -S tree` installed
  signature-verified (no keyring errors) and runs. Rendered identity:
  config-level proof complete (`Theme=savant-traffic-lights`,
  `ButtonsOnRight=IAX`, single panel, 12h, correct package versions);
  the titlebar-dot SCREENSHOT remains owed — blockers characterized:
  spectacle hangs because `plasma-xdg-desktop-portal-kde.service` (the
  6.7 unit name) fails host-portal registration and times out; QEMU
  `screendump` returns `no surface` on the blob path; PrintWindow
  returns a cached frame (pixel-identical second capture). Wallpaper +
  panel captured and pixel-verified
  (`~/savantos-share/proof-rendered-20260914.png`).
- **Also:** guest ignores ACPI powerdown (suspected
  `HandlePowerKey=ignore`) — factory-image question filed as out-of-scope
  in SCOPE.md; two legacy dev disks identified (the Omarchy-era
  `~/savantos-dev` vs the first-party `~/savantos-phase1`).

---

## Validation Results

- [x] bash -n ×4 builder scripts, JS parse, structural greps, lint:md,
      CRLF scan: PASS
- [x] Live deploy verified (packages + files on the guest disk)
- [x] Boot proof through the unmodified launcher: PASS (2026-09-14)
- [x] Runtime pacman -S signature-verified install: PASS (2026-09-14)
- [x] Rendered wallpaper/panel capture + programmatic color check: PASS
- [ ] Titlebar-dot rendered proof: OWED (portal defect characterized in
      FID-2026-0913-001's 2026-09-14 evidence section)

---

## Lessons / Handoff

- The keyring lesson generalizes: anything the BUILDER installs from
  outside the image needs a first-boot equivalent for things the image
  itself must own at runtime.
- Portal registration is a boot-ordering contract: backend before host
  portal, and the 6.7 unit rename breaks any config that references the
  old name.
- The identity tree still needs its atomic commit (G1–G9 staging plan
  owed); SCOPE.md carries the current session's open out-of-scope items.
