# Research reconciliation — Gemini Deep Research report vs the pivot plan

**Date:** 2026-09-12
**Input:** "SavantOS Architecture Research Brief" (Gemini Deep Research, user-run, from
`dev/gemini-deep-research-prompt.md`)
**Status:** reconciled — operator rulings pending where marked

Every report recommendation was sorted into **ADOPT** (changes the plan), **ADAPT**
(adopt with modifications), **ALREADY-SOLVED** (report assumed wrongly about our current
design), or **REJECT** (with reasons). Two load-bearing claims were verified live before
ruling; the verification results are inline.

---

## Headline verifications (done live before writing this)

1. **KWin agent control plane — CONFIRMED in our own guest.** On Plasma/KWin 6.7.5 under
   our exact WHPX/virtio stack, `busctl` shows `/org/kde/KWin/EIS/RemoteDesktop`,
   `/org/kde/KWin/EIS/InputCapture`, `org.kde.KWin.ScreenShot2`, and the accessibility
   manager (`org.freedesktop.a11y.Manager`) all present. The report's core claim — that
   Plasma uniquely enables silent, zero-prompt agent input injection plus deterministic
   semantic UI reading — is true on the version we would pin. The agent-in-OS requirement
   has a real control plane on our chosen base.
2. **The report's #1 red-team claim (state destruction) — PREMISE FALSE.** It assumes a
   full rootfs A/B swap destroys `/home`, SSH keys, browser profiles, agent memory. Our
   host already keeps a **persistent data disk** (`vm/disk.raw`, see `app/backup.go`)
   separate from the swapped `rootfs.ext4` payload; user state and agent state live on the
   data disk and survive every update and rollback (and our dev VM's live `/home`
   mutations have survived repeated reboots all week — same mechanism). The OS-swap model
   is exactly the "decoupled storage strategy" the report demands; it just didn't know we
   have it.

## ADOPT (report changes the plan)

| Item | What | Where it lands |
|---|---|---|
| mkosi + systemd-repart | Declarative, rootless-CI, reproducible raw-image builder replacing hand-rolled pacstrap scripts; native `SOURCE_DATE_EPOCH` + fixed UUID seeds; dual-build digest-compare CI gate | Builder repo (Phase 1) |
| linux-zen | BORE scheduler for interactive latency under virtualization | Builder kernel package |
| Kiosk `[$i]` immutable keys | System-wide `/etc/xdg` defaults with targeted immutability, replacing the skel-fragments/catch-up dance for desktop layout; survives updates, user-overridable per-key | Plasma profile (Phase 2) |
| casync + systemd-sysupdate | Content-defined-chunk delta updates (target <100 MB), orchestrated by the guest | Update pipeline (Phase 4) |
| Aurorae traffic-lights | SVG decoration engine for glowing min/max/close — the native mechanism for the identity | Theming (Phase 2) |
| Electron decoration/a11y flags | `WaylandWindowDecorations` for SSD title bars; `AccessibilityObjectModel` so Electron apps expose their DOM to AT-SPI2 | Plasma profile env |
| Trademark stripping stage | Automated purge of Arch marks + `os-release` rewrite + "derived from" labeling | Builder pipeline |
| Clipboard sanitization | Agent context builder treats bridged clipboard as hostile input | Agent safety design |
| Crash telemetry bridge | coredump/logs forwarded host-side so VM destruction never eats evidence | Builder + launcher |
| Metered-connection pause | Host queries Windows network state; pauses update downloads on metered links | Launcher feature |
| Agent/compositor-crash resilience | `Restart=always` + state checkpoints so KWin crash doesn't kill agent intent | Agent daemon design |
| AVX2 probe fallback | Launcher parses CPU flags; no AVX2 → guest told to disable local VLM path | Launcher probe |
| Cursor yielding | evdev monitor suspends agent input when the human moves the mouse; amber "yielding" state | Agent control plane |
| First-run elevation | DISM one-time UAC flow if WHPX feature is absent (verify current launcher behavior first) | Launcher |

## ADAPT (adopt with modifications)

- **KWin EIS as agent input path — ADOPT, with the report's own fallback.** Verified
  present on 6.7.5. Accept the private-API risk with the mandated mitigation: the agent's
  input layer is an adapter — probe EIS first, degrade to the standard
  `org.freedesktop.portal.RemoteDesktop` (one-time user prompt) if absent — and pin the
  kwin package in the builder.
- **AT-SPI2-first, vision-fallback — ADOPT as the agent's cardinal rule.** The graveyard
  section (Operator folded into ChatGPT; pure-vision coordinate latency) supports it, and
  our live probe shows the a11y bus is active.
- **x86-64-v3 + Hyper-V enlightenments — TEST, don't assume.** The report wants
  `-cpu x86-64-v3,hv_*...`; our launcher deliberately uses `-cpu host` (or a hardened
  qemu64 set) with a comment trail of WHPX panics we survived. Bench x86-64-v3+enlightenments
  in the dev VM; only displace `-cpu host` if it wins on our hardware.
- **Venus/llvmpipe fallback — ADOPT the aggressive host probe.** Largely already exists
  (the launcher's GPU/CPU render paths); extend the probe to explicit Vulkan 1.3 detection
  and pass a "disable heavy compositing" flag when falling back.
- **Frozen upstream snapshot — LIGHT version.** Full self-hosted Arch mirror is overkill
  for this scale; adopt snapshot *pinning* (fixed mirror timestamp recorded in the builder
  lock, advanced only after CI green). Same supply-chain protection, zero infrastructure.
- **casync HTTP requirements — VERIFY EARLY.** casync needs byte-range support from the
  release host; confirm GitHub Releases asset serving behavior in Phase 1 before committing
  the update design, with zstd-split fallback.
- **90-day outline — adopt as workstream order inside the pivot FID** (boot pipeline →
  desktop+state → agent control plane → factory/trust), with days treated as pacing, not
  commitments. The ordering logic (de-risk control plane before aesthetics) is right.

## ALREADY-SOLVED (report unaware of our design)

- **State decoupling / "A/B state destruction fallacy"** — persistent data disk already
  exists; see verification #2. The surviving *enhancement* is **virtiofs for host-backed
  folders** (faster than our virtio-9p share) — a performance upgrade, not a rescue, and
  the share's bridging semantics must be preserved.
- **Direct kernel boot + minimal initramfs + masked boot blockers** — already how the
  launcher boots the guest.
- **Full-image atomic swap with digest pinning** — already the update model; the report
  confirms ostree/bootc/Nix layering would be redundant (matches our own Q3 answer).

## REJECT (with reasons)

- **"Acquire an EV certificate immediately."** SignPath Foundation route is in flight and
  covers this need at zero cost; EV is the fallback if the Foundation declines, not a
  parallel purchase today. Revisit on evidence (SmartScreen reality), not anticipation.
- **WarpBuild paid KVM runners now.** Real need, wrong time — add when boot tests exist;
  the current Docker contract gate already covers patch/image logic without booting.
- **"Local LLM inference is naive" framing.** Agree with the conclusion (2B VLM only,
  niced, bounded cores, AT-SPI2 primary) — that *is* our design; the report argued with a
  strawman. The adoptable residue is the explicit CPU-budget cap (≤2 cores, lowest
  priority) in the agent daemon.

## Operator rulings needed (ECHO Law 2)

1. **Adopt the ADOPT table + ADAPT items into the pivot FID as binding design decisions.**
2. **Builder: mkosi + systemd-repart, linux-zen kernel, snapshot-pinned Arch base.**
3. **Agent control plane: KWin EIS primary with portal fallback, AT-SPI2-first interaction,
   vision only as bounded fallback.**
4. **Safety law: tiered approvals, un-hideable audit overlay, kill switch severing libei,
   agent confined to dedicated unprivileged identity — no destructive act without
   out-of-band human approval.**
5. **REJECT list accepted as-is** (EV-cert and WarpBuild deferred on evidence; mirror
   infrastructure downgraded to snapshot pinning).
