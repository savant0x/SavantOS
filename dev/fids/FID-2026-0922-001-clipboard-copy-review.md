# FID: Clipboard copy system review (host ↔ guest)

**Filename:** `FID-2026-0922-001-clipboard-copy-review.md`
**ID:** FID-2026-0922-001
**Severity:** medium (directly blocks the operator's key-provisioning workflow)
**Status:** verified — review complete on the running payload (transport
verified in every reachable cell), two real defects fixed in-tree (guest
image frames, per-item observability), and the 2026-09-22 dual-build shipped
the fixed guest script with its assemble probe green (see "Build
verification"); not reproduced as reported (see "Reproducibility")
**Created:** 2026-09-22
**Parent:** FID-2026-0917-002 (the provisioning bridge this review was
triggered around), FID-2026-0914-002 (factory criteria: runtime `pacman -S`
was the sanctioned in-guest install path used for the test tooling)

## Request

Operator report (2026-09-22): "it's impossible to copy the OpenRouter key
from my desktop to the VM; also when I copy it from Kate in the IDE, it
still does not copy — we need to review the copy system." This FID is the
review: architecture grounding, a live verification matrix on the running
dev VM, the defects found, and the fixes.

## Architecture as shipped (grounding)

- Host side (`app/clipboard_bridge.go`, Windows launcher):
  - push listener `127.0.0.1:4448` (guest → host, one line per change),
    pull listener `127.0.0.1:4449` (host → guest, one persistent
    connection, one line per change);
  - `pollHost()` ticks every 400 ms and sends the host clipboard only when
    the Windows clipboard sequence number changed;
  - a frame is `base64(UTF-8 text)` or `"png:" + base64(PNG)`;
  - loop prevention is a single `lastSeen` key on the host and a
    `last_content` sha on the guest, plus echo suppression via the
    sequence number.
- Guest side (`scripts/guest/clipboard-bridge.sh`, identical skeleton copy
  at `guest-image/skeletons/usr/local/bin/clipboard-bridge`, enabled by
  `/usr/lib/systemd/user/savantos-clipboard.service`):
  - `socat` pull loop (reconnects every 2 s), `wl-paste --watch … --push`
    for guest → host, `flock`-serialized state in
    `$XDG_RUNTIME_DIR/savantos-clipboard/`.
- The guest daemon first shipped with the 2026-09-18 payload; the running
  dev VM (fresh-booted 2026-09-21 12:10 host time) carries it.

## Verification matrix (live, running dev VM, 2026-09-22)

Test method: QMP `input-send-event` driven real clicks/keys into real app
windows (`dev/scratchpad/qmp-input.py`), verified by saved file content,
`wl-paste`/`xclip` reads inside the guest, and `Get-Clipboard` on Windows.

| Cell | Result | Evidence |
| --- | --- | --- |
| host → guest text | works | `Set-Clipboard SVTEST-H2G-A` → `wl-paste` = `SVTEST-H2G-A`; `incoming` file updated |
| guest → host text (Wayland) | works | `wl-copy SVTEST-G2H-B` → Windows clipboard = `SVTEST-G2H-B` |
| paste into Kate (Wayland, `libqwayland.so`) | works | host sentinel → QMP Ctrl+V → Ctrl+S → `/tmp/svclip.txt` = sentinel |
| copy from Kate (Wayland) | works | typed `katemark` → Ctrl+A/Ctrl+C → `wl-paste` = `katemark`, Windows clipboard = `katemark` |
| copy from Kate (forced X11, `QT_QPA_PLATFORM=xcb`, focused window) | works | typed `xmark` → `wl-paste` = `xmark`, `xclip -o` = `xmark`, Windows clipboard = `xmark` |
| paste into Kate (forced X11) | works | host sentinel `SVTEST-H2G-X11P` → Ctrl+V/Ctrl+S → file = sentinel |
| paste into Cursor (Electron/X11, 1000×800 X11 window) | works | host sentinel → Ctrl+V/Ctrl+S → `/tmp/svclip6.txt` = sentinel |
| copy from Cursor (Electron/X11) | works | typed `cmark` → Ctrl+C → `wl-paste` = `cmark`, Windows clipboard = `cmark` |
| clipboard survives owner death | works | killing the clipboard-owning Kate left the Wayland clipboard intact (Plasma Klipper takes over) |

Correction of an intermediate false positive: an `xclip` copy made with **no
X11 window focused** does not appear on the Wayland clipboard. That is
Xwayland's documented pending-selection behavior (the X11 selection is
withheld from Wayland until an X11 window has focus), not a bridge defect —
with a real focused window (both Kate-xcb and Cursor) the same path works.

## Reproducibility of the operator's report

**Not reproduced.** The report's transport-level claim contradicts the live
evidence: at 12:07 host time (≈2 minutes before this review started) the
operator's own copy on Windows — `C:\Users\spenc\dev\savant-code\CHANGELOG.md`
— reached the guest clipboard through the bridge (`incoming` file + guest
`wl-paste` both showed it). Every app-level cell above then worked.

Ranked hypotheses for what the operator experienced (diagnostics in the
ladder below):

1. The attempt occurred on the pre-2026-09-18 guest rootfs, where the guest
   bridge daemon did not exist yet (both directions dead by construction).
2. The paste target consumed the keystroke as a literal, not a paste:
   Konsole ignores `Ctrl+V` (paste is `Ctrl+Shift+V`) and TUIs generally
   need `Shift+Insert`/`Ctrl+Shift+V`. The bridge cannot fix a paste that is
   never issued; the guest clipboard demonstrably held the key.
3. The sanctioned route was not used: the launcher's `-provision-key
   PROVIDER:KEY` (FID-2026-0917-002) sets the sentinel, writes
   `~/.savant-code/credentials.json` (0600) and scrubs the clipboard — no
   manual copy/paste needed at all.

Diagnostic ladder if it recurs (now cheap, given fix 2 below):

1. Launcher log: `clipboard: sent …` / `clipboard: received …` lines prove
   whether the item crossed; `clipboard: guest connected` proves liveness.
2. Guest: `wl-paste` (current clipboard), `systemctl --user is-active
   savantos-clipboard.service`, `pgrep -a wl-paste`.
3. Paste target: try a Wayland-native app (Kate), then the terminal via
   `Ctrl+Shift+V`, then a fresh boot to rule out a stale guest rootfs.

## Defects found by the review (fixed in-tree)

### D1 — host → guest image frames were silently dropped

The host has always been able to send images (`clipboardGetItem` prefers
PNG, converts DIB otherwise; frames are `png:`-prefixed). The guest's pull
loop ran `base64 -d` over the **whole line**, so the `png:` prefix made
decoding fail and the frame was discarded with no state change and no log —
silent, asymmetric (guest → host images would have decoded fine on the
host).

Fix: the pull loop now detects the `png:` prefix and dispatches to a new
`--receive-image` mode (PNG signature check, 16 MiB cap mirroring
`maxClipboardImageBytes`, `wl-copy --type image/png`), while text keeps the
existing path. An assemble content probe (`--receive-image` present in the
shipped script) pins it.

Live verification (dev VM, dev-disk experiment — fixed script installed to
`/usr/local/bin/clipboard-bridge`, service restarted):

- before: 33×17 PNG on the Windows clipboard → guest types stayed
  `text/plain …`, `wl-paste --type image/png` = 0 bytes (silent drop);
- after: guest types = `image/png`, payload = 100 bytes, signature
  `89504e470d0a1a0a`, IHDR 33×17 (exact match);
- regression: text still crosses both ways after the change
  (`Set-Clipboard` → `wl-paste`; `wl-copy` → Windows clipboard).

### D2 — no per-item observability

The only clipboard log lines were connection and failure events, so a "copy
doesn't work" report had no trace to read. Fix: the launcher now logs one
line per item that actually crosses (`clipboard: sent text to guest (N
bytes)` / `clipboard: received text from guest (N bytes)`), giving the next
occurrence a 10-second diagnosis (see ladder).

## Build verification (2026-09-22 dual-build)

The fixed guest script and its assemble probe shipped in the image build
run of 2026-09-22 (`guest-image/out/build-2026-09-22.log`), completed under
the build watchdog after two engine interruptions:

- probe green in **both** assemblies — the content assertion line includes
  `clipboard-image`, twice, once per assembly:
  `assemble: content assertion passed (… /unit-RuntimeDirectory/clipboard-image)`
- zero `lacks --receive-image` failure lines in the whole log
- dual-build determinism verdict green: all six contract digests matched
  across assemblies A and B, `GATE GREEN — payload in …/out/contract`
- `SHA256SUMS` digest for `-sums-sha256`:
  `3ef6350649ef86daa9cd19502f90353be59a5b00689948a9c7c580d449937263`

The published payload (`guest-image/out/contract/`) therefore carries the
fixed `clipboard-bridge` with `--receive-image`; fresh boots get the image
copy path without any dev-disk experiment.

## Deferred (criterion-gated, not built)

- Guest → host image push: the host decodes `png:` frames, but the guest
  only watches `--type text`. Symmetric capability, no observed need; build
  only if an image-copy case is reported.
- X11-only client copying with no X11 window focused (Xwayland withholds
  the selection). An X11-side poll watcher would close it; build only if a
  real app is observed doing this (none so far — every real app copies with
  its own window focused).
- Running Cursor under native Wayland (`ELECTRON_OZONE_PLATFORM_HINT` did
  not change its platform; it opened as Xwayland). X11 is verified working,
  so no change is forced.

## Evidence / artifacts

- `dev/scratchpad/qmp-input.py` (new in-tree with this review): QMP input
  helper used for every GUI cell above.
- Guest tooling installed for the review via the factory criterion
  (runtime `pacman -S`): `xclip`, `xorg-xlsclients`, `xorg-xwininfo`,
  `xdotool` — dev-disk only, not part of the image.
