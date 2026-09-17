# FID: Launcher hardening — refuse foreign-dir payload updates; make pre-boot silence impossible

**Filename:** `FID-2026-0916-001-launcher-hardening.md`
**ID:** FID-2026-0916-001
**Severity:** high (data-integrity guard for the production install + the
0915-002 silent-exit evidence family gets its forward fix)
**Status:** converged (loop 3) — implementation approved at automation level 3
**Created:** 2026-09-16
**Parent:** FID-2026-0915-002 (launcher defect family); master plan
FID-2026-0915-001 as additive work under T3/T4 hardening.
**Operator directive (2026-09-16, verbatim intent):** file and design the
launcher-hardening FID: refuse release updates of data dirs the launcher
didn't provision, and investigate the silent pre-boot stall from the
0915-002 evidence family.

---

## Problem statement

Two defects, both demonstrated live on 2026-09-16:

1. **Foreign-dir payload update.** A launcher run with developer payload
   overrides (`-release http://127.0.0.1:8765 -sums-sha256 abf7c5c1…`)
   and *no* `-dir` resolved its data directory through the user's
   data-location pointer to `C:\savantos` — the production install —
   silently downloaded and replaced the production payload with the dev
   image, then booted it. The user's writable disk was retained
   (`prepareDisk` never replaces an existing disk), so no data was lost,
   but a dev smoke test was one flag away from provisioning arbitrary
   bytes into the install the operator actually uses.
2. **Silent pre-boot stall.** The same day, a launcher run against a
   fully provisioned dev data dir (`C:\Users\spenc\savantos-dev3`)
   stalled before boot: process alive, no QEMU, last log line
   `runtime archive unchanged in v0.0.1; kept the installed runtime`,
   then nothing for 3+ minutes until it was killed. A second launch of
   the *same* binary, same dir, two minutes later booted instantly.

## Evidence (recorded before design, per loop discipline)

### E1 — the incident transcript (foreign-dir update)

- 11:36: stray launcher started (PID 47828) with overrides, no `-dir`.
  It did not sit at the chooser: it resolved via the pointer
  (`loadDataLocationPointer`, `app/data_location.go:63`) straight to
  `C:\savantos`.
- 11:36–11:37: production `guest/` payload replaced — `install-state.json`
  now cites release `http://127.0.0.1:8765` and manifest digest
  `abf7c5c1…`; payload files stamped 11:36. `runtime/`, `vm/` refreshed;
  `SavantOS.exe` copied into the install root (12,487,680 B).
- 11:37: it booted the production VM (GPU attempt, ready at 11:37:21).
- 11:41: my dev3 launch FATALed with `port 4445 in use` — the collision
  that revealed the whole thing.

### E2 — precedence facts (`app/data_location.go:33-58`)

Resolution precedence is: explicit `-dir` wins → pointer file wins →
default. The pointer is trusted blindly; `ensureGuest` treats any
existing `install-state.json` as authorization to download and replace
the payload. Nothing in the code distinguishes "a run the operator
aimed at this dir" from "a run that landed here by pointer".

### E3 — the override flags are the trust escalation

The flags that made the incident dangerous were the overrides: a
**local HTTP release URL** and a **digest pin** chosen by the caller.
A normal production run (default authenticated release URL) following
the pointer is the *intended* update path. The escalation is
"non-default release/digest" + "dir not explicitly named".

### E4 — the A/B for the stall

| Run | Flags | Dir state | Outcome |
|-----|-------|-----------|---------|
| 12:03 direct | no `-dir`, no `-no-update` | provisioned, idle | stalled ≥3 min, zero logs after runtime line, alive |
| 12:0x `dev-vm.sh` | `-dir`, `-no-update` (script line 125) | identical | boot logs immediately, QEMU up, SSH in cycle 1 |

`dev-vm.sh` passes `-dir` **and** `-no-update`; the stalled run had
neither. Both differ, so this A/B isolates the *family* (pre-boot
blocking between the runtime line and QEMU spawn), not the single flag.

### E5 — static bounds on stall mechanisms (`app/update_windows.go:20-49`)

The update-check metadata client is bounded: dial 4 s, TLS 4 s, header
4 s, total 10 s, and its failure path `logf`s and continues. So the
naive "manifest fetch hung forever" is excluded **statically** — if the
update fetch was the blocker, it blocked *below* these bounds (unlogged
code, a modal host, or scheduler starvation), which is exactly why a
staged reproduction with heartbeats is required rather than a
mechanism claim.

Note: the 11:36 stray run *also* ran with the update check enabled
against the default URL and proceeded past it — the branch can complete
on this machine, further weakening the naive story.

### E6 — stall hypothesis ledger (ranked)

- **H1 (leading):** an unlogged blocking call in the update-check branch
  or between the last `logf` and QEMU spawn (e.g. environment-dependent
  dial outside the bounded client, a wait on the hidden UI, shell-hook
  stall). The A/B and the empty-log window are consistent; only runtime
  capture can pin it.
- **H2 (strong):** a modal dialog with no interactive host. Pre-boot has
  at least two dialog-capable steps (share validation `infoBox`,
  `chooseProvisionMode` at `app/launcher_windows.go:140`); launched with
  `-WindowStyle Hidden`, a message box can wait forever with the splash
  up and no logs.
- **H3 (moderate):** first-execution interference on the freshly copied
  launcher binary in dev3 (AV/Defender scan), partially starved; the
  identical-binary instant boot 2 minutes later fits scan-once caching.
  Partially weakened by the run having logged three lines before
  stalling.
- **H4 (weak, kept for completeness):** proxy/network-stack stall below
  the bounded client's assumptions (e.g. environment proxy injection
  `http.ProxyFromEnvironment` resolving unexpectedly).

## Scope of record (two hardening items, five mechanisms)

### H1. Foreign-dir payload-update protection

- **D1 — override anchoring (the core refusal, fail-closed).**
  Non-default `-release` and/or `-sums-sha256` (and `-runtime-*`
  equivalents) are *developer payload overrides*. A run carrying
  overrides may only update a data dir it was explicitly pointed at:
  - overrides + dir resolved via **pointer** → **hard refuse** before
    any download, with an error naming the resolved dir and the remedy
    (`use -dir`). This single rule would have prevented the incident.
  - overrides + explicit `-dir` → allowed only if the dir carries the
    dev anchor (D1b) **or** the dir has no install yet; otherwise
    refuse.
  - no overrides → behavior unchanged (production pointer updates keep
    working; zero operator friction on the normal path).
- **D1b — dev anchor.** `dev-vm.sh init` (and any dev tooling that
  provisions) writes `dev-anchor.json` (schema'd, tiny) into the data
  dir. Presence = "this dir is dev tooling territory; overrides are
  legitimate here". Production installs never carry it, so production
  stays protected even against an operator who passes `-dir C:\savantos`
  with overrides by hand — that combination now refuses.
- **D1c — provenance in install-state.** At provision time record
  `provisionedBy` (launcher version) and `channel` (`production`/`dev`)
  in `install-state.json`; log both at startup. Observability only —
  no enforcement burden, keeps incident forensics one `cat` away.

### H2. Making pre-boot silence impossible

- **D2 — startup heartbeat + phase logs.** Every phase transition
  between `SavantOS starting` and QEMU spawn emits a `logf` phase line
  (settings → share validation → update check (with outcome) → WHP →
  provision mode → runtime → render decision → guest ensure). New
  watchdog goroutine: no phase progress for 90 s pre-QEMU → log a
  heartbeat warning naming the current phase and the wall-clock since
  the last transition; at 5 min, log the blocked-dialog hint for the
  phase. Never auto-kills (a provision mid-download is destructive);
  the goal is that silence *says something*.
- **D3 — headless mode (explicit flag, no auto-detect).** `-headless`
  (set by dev tooling/automation; auto-detection is a heuristics soup
  and is cut by the loop): all modal `infoBox`/chooser/confirm calls
  take their non-interactive default and log the choice (share
  validation failure → skip share + log; provision mode → standard
  default; any dialog that has no safe default → `fatal` with the
  phase, which the heartbeat makes attributable). The 0915-002 family
  gains its first *attributable* evidence channel.
- **D4 — splash-visible progress.** The splash status line mirrors the
  phase name (it already exists for "Starting SavantOS..." and update
  statuses), so even a GUI run shows where it is; heartbeat warnings
  surface there too.

## Perfection loop

### Loop 1 — challenge the framing

- *"The pointer file is the villain."* No — pointer-following is the
  intended, tested production path (E2). The escalation is overrides on
  an unanchored dir (E3). D1 targets the escalation, not the feature.
- *"Guard the dir with an ownership/provenance ACL."* Overbuild: new
  trust infrastructure, key management, edge cases on every legal path.
  D1's two-file rule (anchor + explicit -dir) covers the demonstrated
  accident class with zero new crypto. YAGNI-cut.
- *"Warn-but-proceed when overrides hit a foreign dir."* Half-measure;
  the operator is not watching, which is the whole problem. Refuse.
- *"Auto-detect headless from window-station state."* Heuristics soup
  with false negatives in exactly the broken cases. Explicit flag;
  automation already knows it is automation. Cut.
- *"Heartbeat should kill a wedged launcher."* A kill mid-provision or
  mid-download can corrupt more than it saves. Visibility, not force.
- *"Also gate on digest-mismatch warnings (D1c as enforcement)."*
  Collapsed into the refusal message; a warning nobody reads is the
  same hole with extra steps. Cut.

### Loop 2 — ordering / risk

- D1 (refusal) is a startup-time flag check + error path: hours, no
  risk to the normal path. D1b is one small file written by
  `dev-vm.sh init`. D1c trivial. D2 is bounded logf work at known
  phase sites. D3 is the largest item (dialog-site audit across the
  pre-boot path; call sites are grep-enumerable: `infoBox`/chooser/
  confirm in `main.go`, `setup.go`, `launcher_windows.go`).
- Sequence: **D1 + D1c → D1b → D2 → D3 → D4**. Each is independently
  shippable; D1 lands protection immediately.

### Loop 3 — convergence

- Every recorded incident fact (E1–E4) maps to a mechanism: pointer
  landing (D1), silent replacement (D1c), silent stall (D2/D3/D4),
  unattributable hangs (D2).
- Every mechanism maps to a gate (below). No mechanism lacks a gate;
  no gate lacks a mechanism.
- The normal user path (no overrides) is byte-for-byte unchanged —
  the guard only fires on the flags that constitute escalation.

## Operator decision points

1. **D1 refusal style.** Hard refuse (recommended: automation has no
   one to answer a dialog; a clear error is honest) vs. interactive
   confirm when a desktop session exists. *Chosen: hard refuse; a
   confirm path can be added later without breaking the contract.*
2. **D1b anchor carrier.** Separate `dev-anchor.json` (recommended)
   vs. a field in `provision-mode`/settings. Separate file survives
   settings rewrites and is trivially grep-able in the guard.
3. **D3 scope.** Pre-boot dialogs only (minimum for the incident) vs.
   all modal call sites (one consistent discipline). *Chosen: all
   modal call sites; partial discipline is where silent hangs hide.*

## Verification gates

- **G1:** unit tests for the D1 guard table: overrides+pointer → refuse;
  overrides+`-dir` unanchored existing install → refuse;
  overrides+`-dir` anchored → proceed; overrides+fresh dir → proceed;
  no overrides → identical behavior (all pre-existing tests stay green).
- **G2:** incident-shape regression: a scripted run with the 11:36 flag
  shape must exit non-zero with the refusal *before any network I/O*.
- **G3:** `dev-vm.sh init` writes the anchor; `dev-vm.sh boot` (which
  passes `-dir` + overrides on release-test runs) continues to work
  end-to-end.
- **G4:** headless smoke: `-headless` boot of a provisioned dev dir
  reaches QEMU with share-skip + provision-default decisions logged.
- **G5:** heartbeat proof: vm/shell.log contains a phase line for every
  pre-boot phase on a normal boot; watchdog warning fires (test hook)
  when a phase is artificially held.
- **G6:** stall family closure: the next live reproduction (if any)
  must produce phase + hint evidence into FID-2026-0915-002 — if it
  cannot, D2's phase set is incomplete and this FID reopens.

## YAGNI compliance

No new trust infrastructure, no crypto, no auto-detection, no auto-kill,
no change to the no-override update path. Every mechanism exists because
a specific recorded incident fact demands it; the loop cut four
candidate mechanisms (Loop 1).

## Resolution

Converged 2026-09-16 (loop 3). Implementation at automation level 3 is
approved; D1+D1c+D1b land first (protection), D2–D4 land as one stall-
visibility pass. Evidence of each gate lands back here as the work
completes.

## Implementation evidence

### D2–D4 stall-visibility pass — landed 2026-09-16 (`be61dc6`)

- **D2 phase logs:** `phaseEnter` at every pre-boot transition (starting,
  settings, share-validation, update-check, whp-check, provision-mode,
  runtime, render-decision, guest-ensure, qemu). Watchdog: warn at 90 s,
  hidden-dialog hint at 5 min, per-level rate limiting, retires at QEMU
  spawn. Never auto-kills (loop-1 cut preserved).
- **D3 headless:** `-headless` flag; `modalChoice`/`modalChoice2` gate the
  UI-object dialogs (first-boot mode → full personal setup, shortcuts →
  none, shared-folder setup → skip, all logged); the first-run data-dir
  chooser has no safe default and refuses headless runs with the remedy
  (`-dir`); the saved-share-failure infoBox is suppressed headless.
- **D4 splash mirror:** every phase and watchdog warning mirrors onto the
  splash status line.
- **Structure:** platform-neutral core (`phase_core.go`, emitter-injected,
  Linux-CI-testable) + windows wiring (`phase.go`). G1's unit suite runs
  in CI on ubuntu (watchdog timing, rate limits, labels, transitions).

### G5 — live boot proof (dev3, dev launcher rebuilt from `be61dc6`)

Normal boot through the launcher, `vm/shell.log` (excerpt):

```text
16:14:33 phase: settings
16:14:33 phase: starting
16:14:33 phase: share-validation
16:14:33 phase: update-check
16:14:33 phase: whp-check
16:14:33 phase: provision-mode
16:14:33 phase: runtime
16:14:34 phase: render-decision
16:14:34 phase: guest-ensure
16:16:18 preboot-watchdog: no phase progress for 1m45s (current phase: guest-ensure) - still working or waiting
16:18:03 preboot-watchdog: no phase progress for 3m30s (current phase: guest-ensure) - still working or waiting
16:20:10 phase: qemu
```

The watchdog fired during this very boot while the payload-verification
step held `guest-ensure` for ~5.5 minutes — the exact silent window that
was the 0915-002 incident signature — and the log now says what it is
doing instead of nothing. Gate G5 satisfied (phase lines for every pre-
boot phase on a normal boot; watchdog fires when a phase is held, proven
by unit tests and this live hold).

### Stage-1 platform-boundary correction — 2026-09-16

The approved completion baseline reproduced Linux-target vet failure at
`phase.go:35:3: undefined: fatal`. Windows launcher build/vet/tests passed
on the same starting tree (HEAD `fd5a888`).

Correction: `phase.go` now declares `//go:build windows`, matching its
existing Windows-wiring contract. Platform-neutral modal helpers reference
`preboot`, so the existing non-Windows test harness now supplies a tracker
using its existing log adapter. The build constraint alone exposed that
second dependency; both parts are required. No production behavior, modal
policy, watchdog timing, or guest operation changed.

Verification after both edits:

```text
Windows app/:
  go build ./...                     exit 0
  go vet -unsafeptr=false ./...      exit 0
  go test ./...                     ok (cached)
  gofmt -l .                        empty output
Linux target (Windows Go, GOOS=linux GOARCH=amd64 CGO_ENABLED=0):
  go vet ./...                      exit 0
  go test -c -o <temporary-test-binary> .  exit 0
WSL Ubuntu, compiled launcher test binary:
  -test.timeout=90s                  PASS
```

Static call-site audit still finds phase transitions in Windows `main.go`
and `headlessRefuse` in `data_location_windows.go`. `modalFatal` remains
without a production caller; this correction does not claim D3 completion.
Native Linux `go test -race ./...` remains outstanding because the WSL
environment has no Go toolchain on PATH. Cross-compilation and non-race
runtime tests are not represented as remote CI/race parity.

### Open from this FID

- G4 headless smoke (live run) — evidence below when collected.
- D1 (foreign-dir override refusal) + D1c (provenance fields) + D1b
  (dev-vm.sh anchor): designed above, **not yet implemented** — next
  work item after this pass.

## Incident 2026-09-17: guest cursor plane invisible under SDL-GL (Plasma)

**Symptom (operator, live):** clicking anything in the VM window made the
mouse pointer disappear and the desktop appear unclickable. Input kept
working (KWin healthy: instant DBus ping, no coredumps, factory theme
config) — only the pointer rendering died.

**Root cause chain:**

1. The launcher boots SDL with `show-cursor=off` (guest-cursor path;
   `qemu.go:140`), trusting the guest to render the pointer.
2. Plasma/KWin 6.7.4 renders the Wayland cursor on the DRM hardware
   cursor plane. Through `virtio-vga-gl` + Venus on WHPX/Windows-SDL-GL,
   that plane's content never reaches the host window on the click path
   (cursor moves between sprites/planes on activation).
3. Result: no host cursor (told off) and no guest cursor (plane dropped)
   = invisible pointer over a fully live desktop.

**Provenance note:** FINDINGS.md documented the SDL cursor fragility in
the Omarchy/Hyprland era (guest cursor rendered in-frame; guest-only path
worked). Plasma changed the mechanism: the cursor moved to a GPU plane,
which the Windows SDL-GL frontend drops. The `-host-cursor` diagnostic
flag (`main.go:150`) already existed for exactly this regression family.

**Immediate fix (live VM):** clean poweroff, relaunch with `-host-cursor`
→ `sdl,gl=on,show-cursor=on`. FINDINGS.md notes the trade (two pointers
can flash during fast motion); acceptable until a real fix lands.

**Proper fix (open):** make the guest render its cursor in-frame so the
guest-only path works under Plasma: `KWIN_DRM` hardware-cursor-plane
disable for virtual GPUs, or QEMU/Venus cursor-plane passthrough fix.
Tracked as a follow-up work item; needs its own probe pass.

**Also ruled out this session:** the four 16:27–16:29 kate coredumps are
the agent's own `kate --version` probes from bare SSH (xcb fatal, fixed
by `xcb-util-cursor` in commit 9c490b1), NOT user-caused; a stalled
`supportInformation` call was a 30s-timeout artifact on emulated CPU,
not a KWin hang (busctl Ping returns instantly).
