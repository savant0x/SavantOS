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

## Verdict matrix (COMPLETE)

| arm | stack | SW cursor | app | verdict |
|-----|-------|-----------|-----|---------|
| A   | GPU venus=on, traffic-lights | on | kate | WEDGE |
| B   | GPU venus=on, plastik | on | kate | WEDGE |
| C   | GPU venus=on, Breeze C++ | on | kate | WEDGE |
| D1  | (invalid — env omissions) | | | discarded |
| D2  | GPU venus=on, traffic-lights | off | kate | WEDGE |
| E   | GPU venus=on, kate as CSD | off | kate | WEDGE |
| G   | GPU venus=on, KWIN_DRM_NO_DIRECT_SCANOUT=1 | off | kate+kcalc | WEDGE (wchan: dma_fence_default_wait) |
| E1  | **CPU mode (llvmpipe, sdl gl=off)** | off | kate+kcalc | **CLEAN (rc=0 everywhere, main thread idle-polling)** |
| E2  | **GPU venus=off (base virgl capset)** | off | kate | WEDGE (same fence) |

**Final attribution:** the host-side virgl loop (virgl renderer process
feeding SDL-GL on Windows/WHPX) fails to signal a fence KWin legitimately
waits on when the first server-decorated window maps. Guest-side flags,
decorations, and Venus itself are all exonerated. The old pre-0916 image
worked on the same stack — the delta is the guest userspace (newer
KWin/Mesa issuing the fence-using submission the old stack never made),
not the QEMU/runtime bits, which did not change.

**Immediate mitigation (operator-facing):** run `-render cpu` (llvmpipe)
— verified clean with Kate + kcalc on the shipping disk. GPU mode stays
blocked until the fence path is fixed or the guest stack is pinned.

## Fix candidates (updated by verdicts)

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

## Pointer-visibility follow-up (CPU mode, 2026-09-17 late)

On the clean CPU boot the operator reported "any click on the desktop
kills my pointer" — the CPU-mode twin of the original visibility bug:
`show-cursor=off` trusts the guest cursor surface, and the click-path
surface update doesn't reach the SDL window here either. Fix applied:
`KWIN_FORCE_SW_CURSOR=1` drop-in restored (its exoneration from the
wedge stands — arm D2 wedged without it; Kate+kcalc verified healthy
WITH it on CPU mode).

Measurement honesty: the synthetic host-click rig produced two false
negatives (foreground held by another app; SetForegroundWindow steal
failed even via AttachThreadInput), so "0 evdev bytes" readings from the
rig are NOT evidence about the guest. The only valid input verdicts
remain: QMP injection arrives (kernel-level), and the 17:25 physical-
context capture (8,712 bytes) plus operator reports. Physical operator
verification is the accept test for the cursor fix.

Current shipped state: `-render cpu` + `KWIN_FORCE_SW_CURSOR=1`.
Fallback lever if the pointer still dies on click: `-host-cursor` ON
CPU MODE (its input-death was only ever proven on GPU mode; untested
here) — arm F was interrupted before testing that combination.

## Open items

- ~~Run G, then E1 (then E2 if needed)~~ DONE — see verdict matrix.
- **Launcher guard (next implementation):** the render probe / boot path
  must either default to CPU for this runtime+guest combination or warn
  loudly on GPU boot that Qt/SSD apps will wedge the compositor. GPU is
  the launcher's proud default — shipping it in this state is shipping a
  desktop that dies on the first text-editor click.
- Root-cause the host fence (which fence, which submission): capture the
  fence ctx/seqno from the guest (`/sys/kernel/debug/dma_buf/bufinfo`,
  virtio-gpu debugfs) at wedge time, and instrument host virgl (Sandbox
  virglrenderer log) if needed.
- Version-delta audit old-rootfs vs new (dev3 disk holds the old
  userspace) — identify the exact KWin/Mesa change that introduced the
  fence-using submission.
- Re-test cursor visibility (FID-2026-0916-001) once GPU returns; CPU
  mode's `sdl,gl=off` path needs its own cursor-visibility check.
- Upstream: QEMU virgl / virglrenderer fence-signal issue on Windows
  hosts, with the bisect table as the report body.
