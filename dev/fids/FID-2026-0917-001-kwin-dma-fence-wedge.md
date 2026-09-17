# FID: KWin dma-fence wedge — any server-decorated window freezes the desktop

**Filename:** `FID-2026-0917-001-kwin-dma-fence-wedge.md`
**ID:** FID-2026-0917-001
**Severity:** critical (desktop dies; every Qt app unusable)
**Status:** investigation-of-record (bisect done; fix candidates queued)
**Created:** 2026-09-17
**Parent:** FID-2026-0912-002 (Phase 2 desktop); relates to
FID-2026-0916-001 (cursor incidents, now reinterpreted)

## Symptom (operator, reproduced on demand)

Opening Kate (or any Qt GUI app) freezes the desktop: taskbar and mouse
stop updating; the screen looks dead but processes stay alive. Chromium,
the GTK portal dialog *content*, and SDL windows render fine until a
**server-decorated** window maps. Recovery requires a session restart
(reboot); killing the app does NOT unwedge.

## Root cause (measured, not guessed)

KWin's main/render thread ends up parked in **`dma_fence_default_wait`**
(live per-thread wchan of a wedged kwin_wayland) — a GPU fence that the
virtio-gpu host path never signals. Everything downstream (scene swaps,
software cursor, input focus processing) freezes with it. The DBus thread
keeps answering `Peer.Ping`, which made early "compositor is alive"
verdicts wrong; real calls (`supportInformation`) time out (rc=124).

## Reinterpretation of the day's incident chain

- The **first** wedge was the 12:20 boot "Cursor folder dialog froze":
  that GTK dialog carries a server-drawn titlebar (traffic lights), so it
  is an SSD window — same trigger as Kate.
- The `-host-cursor` boot (16:48): `show-cursor=on` really did kill
  host→guest pointer delivery at the kernel (0 evdev bytes; QMP injection
  arrives) — a separate, real SDL bug. But the "GTK dialog ignored OK and
  Enter" on that boot was *also* the wedge: keyboard events reached the
  kernel, yet a frozen KWin never processed focus/dialog behavior.
- The 16:21 boot's "clicking freezes everything": my SSH-launched Kate at
  16:29 likely wedged that boot minutes before the report.
- Earlier attributions now retracted: theme leftovers (Tela), QML
  decoration bugs, and the SW-cursor flag are ALL exonerated by the
  bisect below.

## Bisect evidence (all on build-2026-0916 fresh disk, GPU mode)

| arm | decoration | SW cursor | app | verdict |
|-----|------------|-----------|-----|---------|
| A   | savant-traffic-lights (our QML) | on | kate | WEDGE (rc0→rc124) |
| B   | plastik (KWin in-tree QML) | on | kate | WEDGE |
| C   | Breeze (C++ plugin) | on | kate | WEDGE |
| D1  | (invalid — env omissions, app never started) | | | discarded |
| D2  | traffic-lights | **off** | kate | WEDGE |
| E   | CSD kate (`QT_WAYLAND_DISABLE_WINDOWDECORATION=1`) | off | kate | WEDGE |

Conclusions: decoration provider irrelevant (A=B=C), SW cursor flag
irrelevant (A vs D2), even decoration *objects* irrelevant (E). The
common factor is the window map itself under the
`virtio-vga-gl,venus=on` + `sdl,gl=on` GPU stack. kcalc/kwrite wedge the
same way (both found running on wedged boots). Kate `--version` probes
are blind to all of this (no window) — only windowed tests count.

Probe discipline errors the loop caught (recorded so they never recur):

1. `Peer.Ping` used as a liveness check — answered by the DBus thread of
   a dead render loop. Liveness = `supportInformation` under a timeout,
   rc-captured.
2. Recovery attempts via a script in `/tmp` — tmpfs wipes each cycle;
   two silent no-op poweroffs wasted cycles and poisoned one arm.
   Fix: persistent `~/bin-poweroff.sh` + verify QEMU pid is gone + verify
   fresh kwin PID before probing.
3. Partial env sourcing for app launches — an app that never starts
   looks like a healthy "no change". Always verify `pgrep -c app > 0`
   after launch.

## Fix candidates (ordered by information gain)

- **G: `KWIN_DRM_NO_DIRECT_SCANOUT=1`** — direct scanout waits on scanout
  fences; decorated/SSD windows are the classic scanout candidates. A
  one-line drop-in if it holds. TEST FIRST on GPU mode.
- **E1: CPU mode boot (`sdl,gl=off`) + Kate** — removes the whole host
  virgl path. Decisive split: GL-path vs not.
- **E2: `venus=off`** (virgl capset path) — isolates Venus vs base virgl.
- **Version delta audit** — compare KWin/Mesa/kernel between the old
  (working, pre-0916) rootfs and the new one; a KWin 6.7.4/kernel-zen
  virtio fence regression is plausible. The dev3 disk still holds the
  old userspace for diffing.
- **Upstream fallback:** if a delta pin is ugly, ship
  `KWIN_DRM_NO_DIRECT_SCANOUT=1` (or venus-off) in the skeleton and track
  the upstream fix.

## Perfection loop on this FID's plan

1. **Symptom coverage:** the FID must explain ALL of today's reports
   (Cursor dialog freeze, Kate freeze, "click hides taskbar+mouse") with
   one mechanism — it does (SSD windows) plus the separate SDL input bug
   for the 16:48 boot. Nothing left dangling.
2. **Probe validity:** every verdict in the table used rc-captured real
   DBus calls on verified-fresh sessions with app-start verification.
   D1 is marked invalid rather than silently kept. Ping-only checks are
   banned in the probe script.
3. **YAGNI:** no launcher changes, no image rebuilds until a candidate
   PROVES clean on the exact shipping stack (GPU mode + Kate + kcalc).
   The fix must be one skeleton drop-in or one package pin, nothing else.
4. **Reversibility:** every guest-side experiment is a config line or
   drop-in that is removable; the final fix lands in the image skeleton
   with the incident writeup inline.
5. **Falsifiability:** if G and E1 both come back "wedge", the hypothesis
   space moves to the host side (WHPX fence delivery) and E2 +
   version-delta audit become the path; the FID is updated, not the
   narrative.

## Open items

- Run G, then E1 (then E2 if needed); record verdicts in the table.
- Pick the minimal durable fix; land it in the skeleton + live VM.
- Retire `KWIN_FORCE_SW_CURSOR` guidance from FID-2026-0916-001 if the
  cursor-visibility problem needs a different answer after the wedge is
  fixed (re-test visibility on a healthy compositor).
- Upstream tracking once the trigger is pinned to a component.
