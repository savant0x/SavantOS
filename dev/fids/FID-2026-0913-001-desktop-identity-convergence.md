# FID: Desktop identity convergence — single Windows-class panel, QML traffic-lights decoration, de-2000 theming

**Filename:** `FID-2026-0913-001-desktop-identity-convergence.md`
**ID:** FID-2026-0913-001
**Severity:** high
**Status:** fixed — landed `bd2e62f` (decoration + L&F + theming,
including the 2026-09-15 hover-glyph primitive fix); rendered proof
superseded by the pixel measurement recorded in the Resolution section
**Created:** 2026-09-13

---

## Summary

Operator's live-VM screenshots (2026-09-13) show the Phase-2 Plasma desktop
failing four accepted identity requirements simultaneously:

1. **Two taskbars** — the factory panel plus a second panel stuck in
   **edit mode** ("+ Add Widgets…" visible), the top bar using the stock KDE
   start icon (`start-here-kde`) instead of the Savant traffic-lights mark.
2. **Window decorations are not traffic lights** — titlebars render the
   Breeze monochrome left-aligned button set, not the Savant three-dot
   identity (green/amber/red, top-right).
3. **Clock is 24-hour** — accepted spec is a Windows-like 12-hour clock.
4. **"Built in 2000" look** — stock Breeze widget styling and the flat-teal
   default icon set on Dolphin/folders; no icon theme or widget-style layer
   was ever shipped, so every non-chrome surface reads generic/aged.

## Root cause analysis (evidence-based)

| Symptom | Root cause | Evidence |
| --- | --- | --- |
| Two panels | `finalize.sh` writes a hand-rolled `appletsrc` **and** the L&F layout script also creates a panel; Plasma merges both sources | Operator screenshots (two bars); live `appletsrc` contained multiple containments |
| Edit-mode band | The second panel was created `lastScreen=-1`/no-height earlier and re-created in edit mode by a config-restore race | "+ Add Widgets…" band in screenshots; prior session's live fixes fixed only the then-current config |
| Monochrome left buttons | Aurorae SVG decoration path never painted its buttons (KSvg FrameSvg contract mismatch), and the day-one plan's "native Breeze colored buttons" premise **does not hold** on KWin 6.7 (breeze exposes only `AnimationDurationFactor`) | Session probes: aurorae frame rendered, dots never did; breeze kconfig read back one key only |
| 24h clock | Digital clock widget default (`TimeFormat=24h`) never overridden | Screenshot shows "17:57" |
| 2000s look | No icon theme, no widget style, default Breeze color scheme only partially applied | Teal folders; stock widgets in Konsole/Dolphin |

**Decisive discovery (this session, verified in-guest):** Plasma 6 ships the
**QML KDecoration bridge**. KPackage QML themes at
`/usr/share/kwin/decorations/<id>/` load with
`kwinrc [org.kde.kdecoration2] Library=org.kde.kwin.aurorae, Theme=<id>` —
proven live with the in-tree `kwin4_decoration_qml_plastik` package
(supportInformation: `Plugin: org.kde.kwin.aurorae`, zero lookup errors;
window-diff screenshot shows the QML titlebar + plastik glyphs rendering).
This is the modern, cache-free path the Aurorae SVG fight kept missing.

## Approved direction (operator, this session)

All four green-lit: (1) QML `savant-traffic-lights` decoration — dots
**top-right**, true red `#ff2d55` (not pink), soft glow; (2) `kvantum` +
`papirus-icon-theme` packages, Savant-palette Kvantum config, Papirus icons —
kills the "2000s" surfaces; (3) single panel — keep the working bigger bar,
delete the duplicate at the **builder source** (hand-rolled `appletsrc` in
`finalize.sh` removed as a panel source; L&F layout script becomes the single
source of truth); (4) 12-hour clock. Full build-out, no v1/v2 phasing
(operator law).

## Implementation contract

- **Live first, then bake.** Every fix proven in the running guest
  (screenshot-diff verification) before touching the builder.
- **Decoration:** KPackage `savant-traffic-lights` with
  `contents/ui/main.qml` + `SavantButton.qml` modeled on the plastik
  skeleton (`Decoration` root, `installTitleItem(titleBar)`,
  `DecorationOptions` display-order rows, dots min→max→close left→right on
  the right edge). 36px flat `#0b0b11` bar, hairline `#1c1c26`, dots
  `#39ff14`/`#ff9500`/`#ff2d55`, hover glyphs, pressed dim.
- **Panel:** one operation through the supported Plasma scripting API
  (`/PlasmaShell evaluateScript`): remove all panels except the kept one,
  fix height 48, `savant-start` icon, 12h `TimeFormat`. Builder: L&F layout
  script is the only panel source.
- **Theming:** `kvantum` + `papirus-icon-theme` from the pinned snapshot
  (both confirmed present in Arch extra), `kdeglobals`
  `widgetStyle=kvantum` + `IconsTheme=Papirus-Dark`, Savant Kvantum theme.
- **Verification gates:** journal (no QML/decoration errors),
  supportInformation plugin line, window-diff screenshot showing ONE bar +
  dots top-right + 12h clock; builder: dual-build digest gate + boot proof
  through the unmodified launcher.

## Non-goals / recorded deferrals

- Light-mode variants of the Kvantum scheme: deferred with operator approval
  implied by scope (dark appliance identity first); revisit on demand.
- Aurorae SVG theme files: retired (dead path; removed from skeletons).

## Status log

- 2026-09-13: created after operator FID request; root causes pinned to
  tool-verified evidence; live-fix phase beginning.
- 2026-09-14 (late session): builder bake complete + gated (bash -n green on
  all four scripts, lint:md clean, CRLF scan clean). Session-discovered
  fixes beyond the four items: SavantButton.qml on the DecorationButton
  framework idiom (verified against the in-tree plastik reference — the
  MouseArea + `requestToggleMaximization(mouse.button)` form threw
  "Insufficient arguments" on Qt 6.7, implicit signal-parameter injection
  removed); layout script on the supported `currentConfigGroup`/
  `writeConfig` mechanism (the `addWidget` config-object form is silently
  dropped — the stock-KDE-start-icon root cause) as the single panel source
  (remove-all + build-one 48px, savant-start icon, `use24hFormat=12h`,
  wallpaper via the full ["Wallpaper","org.kde.image","General"] group);
  defaults on kvantum + Papirus-Dark + buttons top-right (empty left,
  ButtonsOnRight=IAX); Kvantum Savant variant (config-only, documented
  inheritance) + per-user selector + savant-start.svg moved into skeletons;
  finalize.sh (hand-rolled appletsrc RETIRED as a panel source;
  $BUILDROOT-inside-chroot bugs fixed — unbound under set -u; icon-theme.cache
  determinism cleanup against the pacman gtk-update-icon-cache hook);
  mkosi.conf += kvantum + papirus-icon-theme (snapshot-confirmed); assemble.sh
  content probes extended; identity-apply.sh rewritten (widget style/icons
  re-assert after the L&F apply drops them; buttons top-right; Kvantum
  selection guard); identity.service After=plasma-plasmashell.service (the
  config-restore race); gen-aurorae.py retired (dead path).
- 2026-09-14 (late session): live deployment partially verified — kvantum
  1.1.8-1 + papirus-icon-theme 20260801-1 installed in the guest from the
  pinned 2026-08-11 snapshot (both downloaded from it — the mkosi.conf
  listing is snapshot-confirmed). BUILDER GAP discovered: the first-party
  builder installs packages from OUTSIDE the image, so the runtime pacman
  keyring was never initialized — runtime `pacman -S` fails signature
  verification (fixed live with pacman-key --init/--populate; the keyring
  cannot ship — random content breaks the dual-build digest gate; needs an
  operator decision: dev-loop prerequisite doc or a first-boot keyring
  unit). All identity files deployed to the guest and verified on disk.
  RENDERED verification (dots top-right, one 48px panel, 12h clock in a
  screenshot) is PENDING: the dev guest's Plasma session was wedged
  (plasmashell never registered on DBus — hang predating this session,
  ~18:29, from the prior session's live mutations; survived fresh-config
  and full-SDDM-restart recovery attempts), and the operator killed the VM
  at session end. The next boot exercises the fixed first-login flow
  (deployed files + packages persist on the writable disk). Boot proof
  through the unmodified launcher still owed.

## Perfection Loop

### Loop 1 — Full pass (2026-09-13/14, the session that baked the fixes)

- **RED:** The four operator failures + the root-cause table (tool-verified
  evidence above), plus session-discovered defects: the SavantButton
  "Insufficient arguments" click error (Qt 6.7 removed implicit
  signal-parameter injection), the addWidget config-object silent drop (the
  stock-KDE-start-icon root cause), $BUILDROOT-inside-chroot bugs, the
  appletsrc/L&F config-restore race, the icon-cache determinism surface,
  and the pacman-keyring builder gap.
- **GREEN:** The bake (10 items — see Status log).
- **AUDIT:** bash -n ×4, JS parse, structural greps, lint:md, CRLF scan;
  live deploy verified (packages installed from the pinned snapshot, files
  on the guest disk).
- **ADVERSARIAL:** "The rendered proof never happened" — named exit
  criterion (next-boot first-login flow + boot proof through the unmodified
  launcher); "the keyring gap" — assigned to FID-2026-0914-002.
- **CHANGE DELTA:** ~45% (bake + status log across the session).
- **Convergence:** NOT declared — status stays `fixed` (rendered proof +
  boot proof owed; both are named exit criteria above).

## Boot + runtime evidence (2026-09-14, next-boot exercise)

Boot through the UNMODIFIED launcher (dev build of clean `app/` at `717bb15`),
data dir `~/savantos-phase1`, payload re-verified against the F7 local release
base (`guest-image/out/`, receipt digests re-hashed ALL MATCH; no re-download):

- **System:** `systemctl is-system-running` → `running`; `systemctl is-active
  sddm` → `active`; kernel `7.1.7-zen1-1-zen` (linux-zen 7.1.7.zen1-1);
  launcher log `guest userspace announced ready` (F4 readiness) ~12 s after
  launch; graceful shutdown via QMP `system_powerdown` → QEMU `POWERDOWN`
  event observed (note: the guest then ignores ACPI poweroff — logind
  HandlePowerKey=ignore suspected; recorded as a builder question).
- **Session:** plasmashell `--no-respawn` + kwin_wayland alive;
  `pgrep` evidence recorded; `plasma-xdg-desktop-portal-kde` fails to
  register ("Connection already associated with an application ID") —
  spectacle screenshots hang (portal dead end, see defect below).
- **Identity config (live, in the running session):** `kwinrc`
  `[org.kde.kdecoration2] Library=org.kde.kwin.aurorae,
  Theme=savant-traffic-lights, ButtonsOnRight=IAX` (empty left);
  `kdeglobals LookAndFeelPackage=savant.desktop`; panel count in live
  appletsrc = **1**; clock `use24hFormat=12h`; kvantum 1.1.8-1,
  papirus-icon-theme 20260801-1 installed in-guest (matches the Status log
  versions); kded6 journal shows the QML decoration module loading.
- **Rendered (PARTIAL):** host-side targeted window capture
  (`scripts/capture-window.ps1`, PrintWindow PW_RENDERFULLCONTENT) →
  `~/savantos-share/proof-rendered-20260914.png` (2560×1369): dominant
  colors are the `#050508` Savant background family; wallpaper traffic
  lights present as green→amber→red glow blobs (upper-right, left→right
  order verified programmatically); single dark bottom band = the panel.
- **Rendered (STILL OWED):** the window-diff proof of the DECORATION dots
  on a real titlebar. Blocked this session by two named defects:
  1. **Portal/spectacle dead end** — spectacle `-b -n -o` hangs (>90 s);
     `xdg-desktop-portal-kde` 6.7 renamed its unit to
     `plasma-xdg-desktop-portal-kde.service` (the expected
     `xdg-desktop-portal-kde.service` does not exist), the backend fails
     host-portal registration, and start operations time out. QEMU
     `screendump` returns `"no surface"` on the virtio-gpu blob path
     (already documented in docs/DEVELOPING.md).
  2. **PrintWindow cached frame** — a second capture after opening Konsole
     returned a pixel-identical image (diff bbox None), so the
     screenshot-diff method cannot observe new windows until a working
     capture path exists (portal fix or a QMP-framebuffer alternative).
- **Also observed (defect, out of scope here):** KWin `supportInformation`
  DBus call returns NoReply while org.kde.KWin is registered on the
  session bus.

**Conclusion:** boot proof + config-level identity proof RECORDED; status
stays `fixed` — the titlebar dot rendered proof remains the single owed
evidence item, now with its blockers precisely characterized (portal unit
rename + registration ordering; no working screenshot path on the GL path).

## Resolution (2026-09-15, first boot of the Sep-15 built image)

- **The owed rendered proof is superseded by better evidence:** spectacle
  `-a -b -n -o` **works on the new image** (the portal dead end above was
  specific to the old disk's half-updated portal state; on a clean
  6.7.4-2 install the renamed `plasma-xdg-desktop-portal-kde` backend
  registers and captures fine). `~/savantos-share/active-window.png`
  (760×667) shows Konsole with the three traffic-light dots on the
  titlebar, captured by the guest's own screenshot tool.
- **NEW DEFECT found and FIXED during that proof — hover glyphs off-center
  (operator report):** the hover marks were `Text` glyphs (× − □ ❐)
  centered by font box, and symbol-font metrics sat asymmetrically inside
  their boxes, so one dot's mark read off-center on all four sides.
  **Fix (repo skeleton,
  `savant-traffic-lights/contents/ui/SavantButton.qml`):** marks are now
  anchored QML primitives — × = two ±45° bars, − = one bar, □ = outline
  square, ❐ = two offset squares with a dot-colored front face — centered
  by construction, font-independent. Verified pixel-precise on the live
  desktop (always-visible test theme → spectacle capture → connected-
  component measurement): glyph centroids within **≤0.5 px** of dot center
  on both axes for all three dots (identical small bias = even-stroke
  rounding, not drift); KWin journal shows zero QML errors. Deployed file
  sha256 `da1de12b…` == repo file. Durable in the next image build; the
  running dev guest already carries it.
- **Also unblocked this boot:** KWin `supportInformation` responds (the
  NoReply above did not reproduce), enabling live theme verification
  (`Theme: savant-traffic-lights` restored after the experiment).