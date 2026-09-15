# FID: Desktop experience pass — clock redesign, wallpaper v3, icons, app preload (Chromium), notepad, customization directions

**Filename:** `FID-2026-0915-006-desktop-experience.md`
**ID:** FID-2026-0915-006
**Severity:** medium (product-facing quality; no contract impact)
**Status:** loop-converged, implementation authorized at automation level 3
**Created:** 2026-09-15
**Operator directive (2026-09-15, verbatim intent):** the date under the
clock is badly designed and needs a redesign; the wallpaper needs a
rebuild; preload apps with Chrome as the major one; better icons if
possible (icon packs), a notepad, and other Linux customization ideas.
**Parent:** FID-2026-0912-002 (Phase 2 desktop) — this is its experience
refinement pass; **master plan:** FID-2026-0915-001 as additive track T5.

---

## Scope of record (five work items + one ideas ledger)

### D1. Clock/date redesign

**Finding.** The panel clock is stock `org.kde.plasma.digitalclock` with
`showDate=true`; Plasma renders the date as a second line under the time
using the long locale format (`09/15/2026`) — wide, redundant, and
visually disconnected from the traffic-light identity.

**Design of record (Pass 1, config-level):** custom compact date format —
`dateFormat=custom`, `customDateFormat=ddd d MMM` (e.g. "Mon 15 Sep"),
keeping 12h/no-seconds. Small, locale-honest, and the panel stops
looking like a default install.

**Design considered, deferred (Pass 2):** a bespoke Savant clock plasmoid
(horizontal time·date with the traffic-light dot as the colon separator)
as part of the identity QML layer — real design work, its own FID, not a
config line. Filed as the natural successor; do not attempt inside this
pass.

### D2. Wallpaper v3 (rebuild)

**Finding.** The shipped wallpaper is the v2 traffic-lights render
(three orbs on a dark field). It reads as a placeholder: composition is
centered-static, no depth, and the light variant lags the dark one.

**Design of record:** rebuild via the existing deterministic generator
(`dev/scratchpad/gen-wallpapers.py`, numpy + Pillow, host-side, freshness
gated): v3 composition = off-center light source with a soft horizon
glow, vignette instead of flat field, the three dots arranged as a
diagonal constellation rather than a centered row, subtle film grain
(fixed seed — determinism preserved), same filename/paths so the layout
js and assembly probes are untouched; regenerate both `savant` (dark)
and `savant-light` variants at 2560×1440 + 1920×1080.

**Hard constraint:** determinism gates stay green — fixed seed, fixed
epoch handled by assemble.sh as today; the build's host-side freshness
gate verifies PNGs are newer than the generator.

### D3. Icons — verification-gated upgrade

**Finding.** Identity ships Papirus-Dark (solid choice, but the ask is
"better if possible" and the Savant look is macOS-adjacent traffic
lights).

**Design of record:** **only** themes verifiably present on the pinned
2026-08-11 snapshot may enter `mkosi.conf` (project law: every package
verified on the snapshot before listing). Candidates to verify, in
order: `colloid-icon-theme` (extra; Colloid-Dark matches the flat
Kvantum engine well), stay-on-Papirus as the explicit fallback. Papirus
variants (ePapirus/Nord) also snapshot-present but are a lateral move,
not an upgrade. Decision is made by the snapshot file-list check, not
taste, and the swap lands with `defaults` (`Theme=`) + kcminputrc-free
(one line) + assemble probe update.

### D4. App preload — Chromium (the "Chrome" ask)

**Finding.** The desktop ships no browser. Chrome proper is AUR-only
(unverifiable on the pinned snapshot, violates the project's trust
chain); **Chromium is in Arch extra at every recent snapshot** and is
the same engine.

**Design of record:** add `chromium` to mkosi Packages (snapshot-verify
first), and set it as `favorites`/default-browser hints in the layout
where trivial. Honesty note filed: this is *shipping* an app, not
*preloading* it into RAM (a `preload`-style daemon is a Phase 3+ idea —
see D6). Image size impact ~450 MB installed, fits the 6 GiB factory
image.

### D5. Notepad

**Finding.** Kate is shipped (powerful, heavy); the ask is a quick
notepad. **Design of record:** `featherpad` (Qt6, light, snapshot-verify
before listing) — matches the Qt identity, starts instantly, and does
not drag Xfce/GTK deps the way mousepad would.

### D6. Ideas ledger (surfaced, not committed)

- **Preload daemon** (goaded-style RAM prefetch of frequent apps) —
  Phase 3+; interacts with the agent control plane's resource story.
- **Bespoke clock plasmoid** (D1 Pass 2), Savant widgets for the
  systemtray, traffic-light notifications.
- **Konsole profile as default shell experience** (already themed);
  Yakuake-style drop-down.
- **GTK app theming already covered** (kde-gtk-config ships);
  flatpak theming only if flatpaks ever ship.

## Verification

- Config items (D1): layout js change + in-guest screenshot showing the
  redesigned clock; assemble probe for the layout file already exists.
- D2: regenerated PNGs land in skeletons; build freshness gate green;
  identity FID screenshot refreshed.
- D3/D4/D5: snapshot file-list check output pasted into this FID before
  the packages are listed; boot-verified in the next image build.
- All: dual-build determinism gate green on the final state.

### Snapshot verification transcript (2026-09-15, gate of record)

Source: `extra.db` fetched from
`https://archive.archlinux.org/repos/2026/08/11/extra/os/x86_64/extra.db`
(8,774,630 B, HTTP 200) — the authoritative package list of the pin.

- **chromium** — `chromium-151.0.7922.108-1` present → **D4 GREEN**.
  Deps (gtk3, nss, libpulse, hicolor-icon-theme, …) all in the pin's
  extra/core; no AUR, no unverified source.
- **featherpad** — `featherpad-1.6.3-1` present → **D5 GREEN**. Deps:
  `hicolor-icon-theme`, `hunspell`, `qt6-svg` (qt6-svg-6.11.1-1
  confirmed present; already ships in the image anyway).
- **colloid-icon-theme** — **ABSENT** from the pin (grep of the full db
  returns nothing) → per the FID's own law, **D3 resolves to the
  explicit fallback: Papirus-Dark stays**. Recorded as a gated no-op,
  not a silent skip. (Re-check on any future snapshot bump; Papirus
  20260801-1 confirmed present.)

## Verification Gates

- gate: build/vet/test/fmt per protocol.config.yaml
- gate: snapshot-verification transcript for every new package
- gate: dual-build gate green on the tree that ships D1–D5

## Perfection Loop

### Loop 1 — Reconciliation + honesty pass (2026-09-15)

- **RED:** "Add google-chrome" — rejected: AUR-only, unverifiable
  against the pinned snapshot, breaks the trust chain. Chromium is the
  engine-honest substitute; recorded as such, not silently substituted.
- **RED:** "Swap icons because new is better" — the loop forced the
  snapshot-verification gate: only what the pinned snapshot provably
  ships may enter; if Colloid is absent, Papirus stays and the FID says
  so. No taste-based package enters the factory.
- **RED:** "Redesign the clock with a custom plasmoid now" — deferred to
  its own FID (Pass 2): a new plasmoid touches the identity layer,
  needs its own design/demo cycle; the config-level compact date ships
  the visible improvement this pass.
- **RED:** "Rebuild the wallpaper freehand" — the generator stays the
  only path (determinism + freshness gate); v3 is a composition change
  inside the generator, not a new pipeline.
- **ADVERSARIAL:** "Bigger image = slower provisioning." Chromium adds
  ~450 MB to a 6 GiB image on a local loopback provision (~20 s
  measured); acceptable. Named, not ignored.
- **CHANGE DELTA:** n/a (new FID; no prior claim replaced).
- **Convergence declared:** D1–D5 implementable at automation level 3
  (operator pre-authorized by the request + L3 instruction); D6
  recorded without commitment.
