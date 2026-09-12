# SavantOS foundation review — research brief for Gemini Deep Research

You are a senior systems-research analyst. I am the maintainer of SavantOS. I need deep,
citation-backed research to validate or correct a major foundation decision we just made:
discarding our current Linux guest desktop (an Omarchy/Hyprland derivative) and rebuilding the
guest from scratch as a first-party, agent-first desktop operating system. Your job is to
pressure-test that decision, recommend the exact starting stack, and surface anything that makes
the build smoother, faster, safer, or smarter. Red-team us — I want "where this plan is wrong"
as an explicit deliverable, not politeness.

## 1. The product

SavantOS is a complete Linux desktop operating system for Windows users, delivered as a single
signed Windows executable ("the launcher") that boots the OS in a local virtual machine — no
VMware/VirtualBox installation, no dual-boot, no Linux expertise required. Think "a full desktop
OS that installs like an app": sandboxed away from Windows, atomically updatable, and deletable
without a trace.

The defining product requirement — the core of this brief:

> A Savant AI agent is embedded in the OS as a first-class peer of the human user, with the same
> capabilities the user has: it can see the screen, move the mouse and type, open and control
> applications, run shell commands, read and write files, install packages, and use the network —
> side by side with the user in one desktop session. The agent is not a chat sidebar bolted onto
> apps; it is an OS-level actor. The OS exists to make that safe, observable, and revocable.

The wider ecosystem (all first-party, all mine):

- **Savant Code** — our desktop coding-agent product. Its design language ("traffic lights": a
  near-black field with glowing green/amber/red status dots) is the visual identity the OS desktop
  must match natively.
- **Savant Core** — the main agent runtime, written in Rust. It ships inside the guest OS and acts
  on the desktop with user-equivalent capabilities.
- **SavantOS** — the OS that embeds the above natively at the image level, not as downloads users
  fetch afterwards.

## 2. Current architecture (what exists and works today)

Host side (Windows) — this layer is decided and stays:

- **Go launcher**, one signed exe. Sizes guest RAM to the machine with a startup "memory ladder";
  boots QEMU (q35, accel=whpx, -cpu host) with virtio-vga-gl + Venus Vulkan when the host GPU
  allows, virtio-gpu + llvmpipe otherwise; owns the VM window (SDL), tray icon, and a close-guard
  so the window X performs a graceful OS shutdown instead of hard-killing a running system;
  virtio-net with host port forwards (SSH), virtio-9p shared folder, clipboard bridge, QMP control
  socket; direct kernel boot (vmlinuz + initramfs, root= by label).
- **Atomic updates**: download new rootfs.ext4 (zstd) + kernel, verify digests against a signed
  manifest, swap on next boot. No in-place package upgrades of the running OS.
- **Distribution**: GitHub Releases today (launcher, rootfs, kernel, initramfs, manifests,
  signatures). SignPath Foundation application pending for Authenticode signing.

Guest side (Linux) — the layer being replaced:

- Today: an Arch-based rootfs built by applying a 48-patch git-am train onto a pinned upstream
  "Omarchy for Windows" builder repo; Omarchy (Hyprland tiling desktop) plus our theme, waybar
  taskbar, and integration services. We are deleting this: the tiling paradigm (no title bars, no
  minimize, no desktop icons, hidden power controls) is wrong for a mainstream desktop, and the
  upstream-fork dependency blocks rebranding and full control.

The **Savant integration set** (first-party code extracted from those patches; must survive the
rebuild): first-boot provisioning and welcome flow; instant-trial mode with zero-fill-on-exit and
trial-to-real export; clipboard bridge; sshd requested per boot; shared-folder linking; host
locale sync; factory update notice and reboot-notify units; catch-up revision migrations for
existing installs; backup/restore; the factory-overlay pipeline; and the builder verify/contract
test suite (51 unit tests plus a full contract gate in CI).

Facts already proven on the target stack (you may rely on these):

- Plasma 6.7.5 + KWin 6.7.5 install from the Arch repos and run on this exact stack: kwin_wayland
  ran on the existing virtio-gpu/venus QEMU build under WHPX (verified live in our dev VM).
- Dev VM budget: 5.8 GiB RAM total (4.6 GiB available with Plasma installed), 24 GiB disk with
  17 GiB free.
- Factory floor: 4 GiB guest RAM minimum (8 typical), images roughly 1.5–2 GiB compressed.

## 3. The decision to pressure-test

We are rebuilding the guest as a first-party OS: our own builder repo pinned to a plain Arch
bootstrap (no upstream desktop fork), our own builder scripts, Plasma as the desktop, the
traffic-lights identity as native Plasma theming, the Savant integration set ported over, and the
Savant agent wired into the session from first boot. The host/hypervisor/launcher layer stays
exactly as described above. One build style rule: **we build out fully — do not give staged
"v1/v2/MVP" scoping advice. We want the complete architecture and an execution order, not a
feature-stripped first slice.**

Answer every numbered question explicitly. Where a question is genuinely unsettled in the
ecosystem, say so and give us the decision rule to use rather than a hedge.

### A. Base distro and image builder

- **Q1.** Best base distro for a from-scratch, full-image, rolling desktop OS that we assemble
  ourselves: evaluate Arch, Fedora (Atomic/toolbox ecosystem), openSUSE (Aeon/Kalpa), NixOS,
  Debian testing, and any notable 2025–2026 entrant. Criteria: package freshness for Plasma 6 and
  agent toolchains (Rust); ability to build a complete reproducible image in CI; ecosystem/package
  breadth; trademark and redistribution posture for a rebranded OS shipping their repositories
  (Arch's policies specifically — what do EndeavourOS, Garuda, and Archcraft actually do?);
  image size; and our existing Arch-based tooling investment. Recommend one, name the runner-up,
  and state the deciding criteria.
- **Q2.** Builder tooling: our factory is currently shell scripts plus git-am patches assembling a
  rootfs. For a first-party build, evaluate mkosi (systemd), mkarchiso, osbuild, and plain
  pacstrap-plus-scripts. Which produces reproducible, CI-friendly, signed raw ext4 rootfs images
  consumed by QEMU direct-kernel boot (not a live ISO)?
- **Q3.** Do immutable/atomic layering systems (ostree/bootc, Nix profiles, ABRoot-style) add any
  value given we already ship atomic full-image A/B swaps with digest pinning — or is that
  redundant machinery for our update model?
- **Q4.** Kernel choice under WHPX: linux vs linux-lts vs linux-zen for desktop responsiveness in
  a VM, plus any WHPX-specific kernel notes (timer, irqchip, PSR) we should know about.

### B. Desktop environment

- **Q5.** Plasma 6 under virtio-gpu/venus on Windows QEMU/WHPX: known 2025–2026 issues and
  compositor tuning; and an honest comparison against GNOME (current), COSMIC (Rust — potential
  synergy with Savant Core), and XFCE/X11 on: Windows-like defaults (taskbar, start menu, tray),
  theming depth (see Q6), RAM/CPU in a 4–8 GiB VM, Wayland support for agent input injection and
  screen reading (see Q8), and fractional scaling. We lean Plasma — confirm or overturn with
  evidence.
- **Q6.** Traffic-lights theming: on the recommended DE, name the exact mechanisms to get
  Windows-like title bars with minimize/maximize/close rendered as our glowing green/amber/red
  dots — KDE color schemes, Aurorae window decorations, Kvantum/Lightly, GTK equivalents — and be
  explicit about the limits per toolkit (Qt, GTK4/libadwaita, Electron; server-side vs
  client-side decorations).
- **Q7.** Shipping a curated-but-hackable default desktop: the best mechanism to pre-seed
  panel/start-menu layouts, file associations, and defaults for all users at build time and on
  update (skel vs /etc/xdg vs distro kiosk/customization tooling), surviving updates without
  stomping user choices — how do the KDE-based spins and immutable distros handle this in 2026?

### C. The agent in the OS — the most important section

- **Q8.** The control plane: for a Wayland session (Plasma), what is the current best-practice
  stack for a background agent to (a) inject input with the user's authority, (b) read the screen
  at both pixel and semantic level, and (c) enumerate and activate windows? Evaluate libei plus
  xdg-desktop-portal RemoteDesktop/Screenshot (maturity in 2026, KWin support), ydotool/uinput,
  wlr protocols, and AT-SPI2 accessibility trees for semantic UI understanding of Qt, GTK, and
  Electron apps, with OCR as fallback. What combination gives user-equivalent capability while
  keeping a permission model?
- **Q9.** Safety architecture for an agent with user-equivalent powers in a single-user desktop
  OS: survey how leading products gate computer use (Anthropic computer use, OpenAI Operator /
  agent mode, Windows Copilot Vision/actions, Apple Intelligence, any Linux attempts), then
  recommend: approval modes, an audit/activity log UI, an instant revoke/kill switch, on-screen
  agent-activity indication conventions, and what should be technically impossible (e.g., the
  agent modifying its own permission state).
- **Q10.** Side-by-side cohabitation UX: patterns for an always-available agent on a Plasma
  desktop — panel applet, dedicated containment, floating overlay, KRunner integration, dock —
  with prior art from Copilot-style sidebars and KDE/GNOME AI experiments. Also: how should a
  Rust agent daemon expose itself to the desktop (D-Bus services, portal backends) so any UI can
  drive it?
- **Q11.** Prior art and the graveyard: what actually exists in 2026 for agent-first or AI-native
  Linux desktops (distros, DE integrations, startups), what shipped versus vaporware, and the
  sharpest lessons from each success or failure we should internalize.
- **Q12.** Realistic local-AI budget: in-guest (4–8 GiB RAM, no GPU passthrough, virtio-gpu or
  llvmpipe), what local inference is feasible for OS features (small UI-grounding or OCR models,
  embeddings, wake phrases) versus what must stay cloud (Savant Core's main reasoning via APIs)?
  Give concrete model classes and RAM costs.
- **Q13.** Agent–user shared world: a shared user account gives shared files, clipboard, and
  processes. What else is needed for true peer capability — shared browser profile? keyring and
  secret-access policy? terminal presence conventions? How should "the agent opened a terminal"
  be made visible rather than spooky?

### D. Host/hypervisor — sanity-check only; we are keeping WHPX + QEMU + virtio

- **Q14.** 2025–2026 WHPX status: recent Windows 11 changes affecting Windows Hypervisor
  Platform (memory handling, processor features, WSL2/Hyper-V coexistence, nested
  virtualization), QEMU-on-WHPX known issues for desktop latency, and virtio-gpu Venus maturity
  on Windows QEMU builds. Flag something only if a materially better option preserves the
  zero-install, single-exe UX; otherwise confirm and tune.
- **Q15.** First-run privilege model: enabling virtualization features needs elevation. How do
  shipped products (Docker Desktop, Podman Desktop, Multipass) handle the enable-features and
  admin-elevation dance at install/first-run in 2026, and which pattern should we adopt for the
  smoothest first minute?
- **Q16.** Boot-to-desktop latency: with direct kernel boot and zstd rootfs, what is realistically
  achievable (target under 15 seconds?), and what are the highest-leverage optimizations
  (initramfs size, systemd parallelization, Plasma cold-start tuning, virtio-gpu init)?

### E. Delivery, updates, trust

- **Q17.** Delta updates for ~2 GiB rootfs images: evaluate zchunk, casync, xdelta3, and
  container-registry layer-split approaches for digest-pinned A/B swap; recommend one compatible
  with our signed-manifest model, targeting typical updates under 100 MB.
- **Q18.** Windows trust chain for an exe that boots a VM: beyond the pending SignPath Foundation
  route, what is the 2026 checklist for SmartScreen reputation, EV vs OV vs Foundation signing,
  winget/MSIX distribution for VM-based products, and known Defender false-positive patterns we
  should pre-empt?

### F. Development and CI

- **Q19.** CI for image builds and boot tests: caching strategies for pacman and package builds on
  GitHub Actions, and the fastest honest way to smoke-boot a built image per commit when hosted
  runners lack nested virtualization (KVM-capable runners in 2026? how slow is TCG boot of a
  desktop? alternatives: initramfs-level tests, headless kwin/Hyprland test suites?).
- **Q20.** Reproducibility verification: standard practice for proving two independent builds
  produce identical artifacts (SOURCE_DATE_EPOCH, mkosi --reproducible, pacman determinism
  issues); what does a credible "rebuild twice, compare digests" gate look like for a
  signed-manifest pipeline like ours?

### G. Open challenges — answer freely

- **Q21.** Given everything above: what are we over-engineering, what is missing, and what would
  you do differently in our position? Context: agent-first desktop OS for Windows users; a
  team of one maintainer working with AI agents; ecosystem is Rust for compute, Go for the host.
- **Q22.** Name the single highest-risk dependency in this entire plan and the mitigation we
  should start building now.
- **Q23.** Ask yourself: what are the up to five most important questions we failed to ask — and
  answer each briefly.

## 4. Required output format

1. **Executive summary** (≤500 words): your verdict on the pivot and the one-page recommended
   stack.
2. **Per-question answers**: for each Q, a short answer; a decision table where applicable
   (options × criteria, with citations); your recommendation with confidence level
   (high/medium/low).
3. **Recommended starting stack**: one table — layer → choice → why → key risk.
4. **Red-team section**: "Where this plan is wrong or naive" — at least five substantive
   challenges, each with a better alternative.
5. **Enhancement backlog**: top 10 improvements ranked by impact ÷ effort; one line each, then a
   paragraph on the top three.
6. **Risk register**: top technical, legal, supply-chain, and UX risks with mitigations.
7. **Build order**: a 90-day execution outline for the rebuild — workstream-ordered, showing what
   to prove first and how to de-risk the agent integration early. Not feature-staged; we build
   fully.
8. **Full source list.**

## 5. Ground rules

- Cite primary sources (official documentation, kernel/QEMU/KDE/Arch/freedesktop project docs,
  project repositories) over blog posts; include links.
- Prefer 2025–2026 information and explicitly note anything that changed recently (libei
  maturity, Venus status, WHPX changes in recent Windows builds, KDE AI initiatives).
- Be concrete: exact package names, config mechanisms, API and protocol names — not generic
  advice.
- No marketing framing; if something is hype, say so.
