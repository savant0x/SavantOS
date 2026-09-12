# SignPath Foundation — Application Submission (paste-ready)

Prepared 2026-09-11 from `dev/signpath-application.md`. Apply via
https://signpath.io/solutions/open-source-community → Apply. Fields are
grouped so each block can be pasted into the corresponding form input; if
the form has fewer fields, paste in order — the text is written to stand
alone.

---

## Project name

SavantOS

## Repository URL

https://github.com/savant0x/SavantOS

## Project description

SavantOS is a sovereign, open-source Windows host application that runs a
complete Arch Linux desktop (the Omarchy desktop environment — Hyprland,
waybar, themes) in a managed QEMU virtual machine on the Windows Hypervisor
Platform, with GPU acceleration passed through from the host GPU. The user
downloads one small launcher (`SavantOS.exe`, ~8 MB, Go), picks a data
folder, and the launcher downloads, SHA256-verifies, and boots a
factory-built guest image in a window on their desktop — no partitions, no
dual boot, fully uninstallable from Windows Apps & features.

The launcher self-updates through Ed25519-signed update manifests whose
public key is pinned in the launcher's source; every release is built
reproducibly by the repository's own GitHub Actions release pipeline
(containerized, package-locked, pinned upstream revisions), and each release
publishes its build spec, guest manifest, package lock, and provenance
records as release assets.

## What should be signed

Only our own build artifact: `SavantOS.exe`, the Windows launcher produced
by the release workflow in this repository from this source tree.

The Linux guest image, kernel, initramfs, and the WINQ-EMU runtime are
*not* submitted for Authenticode signing. They are covered by a separate
integrity chain: an authenticated `SHA256SUMS` manifest whose digest is
pinned in the launcher's source and whose installation is verified before
use. This keeps the Foundation certificate scoped to binaries built
entirely from our reviewed source, consistent with the Foundation's rule
that upstream software is not signed under our name.

## License

Apache-2.0 (https://github.com/savant0x/SavantOS/blob/main/LICENSE), an
OSI-approved license, with no commercial dual-licensing. Third-party
components keep their own open licenses, documented in `NOTICE.md` and the
release provenance assets.

## Eligibility conditions

- **No malware / no hacking tools:** the application is a virtual-machine
  launcher for the user's own machine. It enables Windows' own Hypervisor
  Platform feature with an explicit permission prompt; it opens no inbound
  network services unless the user explicitly requests loopback-only port
  forwards.
- **Maintained:** active development with CI on every pull request, a
  weekly automated dependency-lock refresh workflow, governance documents
  (`AGENTS.md`), and a tracked engineering history (`CHANGELOG.md`,
  `docs/`, archived FID records).
- **Released:** first release v0.0.1 published 2026-09-11 at
  https://github.com/savant0x/SavantOS/releases/latest — produced by the
  public release workflow, with build-spec, package lock, and provenance
  assets attached.
- **Documented:** the README describes functionality, install and
  uninstall steps, settings, and limitations
  (https://github.com/savant0x/SavantOS#install); uninstall is available
  from the app's Settings, Windows Apps & features, and the command line.
- **No proprietary code:** all components are open source (Arch packages,
  Omarchy desktop, QEMU/WINQ-EMU forks, and SavantOS's own Apache-2.0
  code).

## Team and roles

Solo-maintainer project. GitHub owner: savant0x
(https://github.com/savant0x).

- **Authors / Committers:** savant0x (repository owner, sole committer)
- **Reviewers:** savant0x (all changes land through pull request — branch
  rulesets on `main` require a PR with one approval and CODEOWNERS review,
  and ban force pushes outright; as a solo maintainer the owner merges
  via the repository admin override rather than self-approving)
- **Approvers:** savant0x (the single person who approves each release
  signing request)

Multi-factor authentication is enabled on the GitHub account, and will be
enabled on the SignPath account. (ACTION before submitting: confirm MFA is
on at github.com/settings/security — SignPath's code of conduct requires
MFA on both.) As the project grows, the reviewer and
approver roles are intended to be split onto additional maintainers.

## Upstream / fork disclosure

SavantOS is a hard fork of omacom/try-omarchy-windows
(https://github.com/omacom/try-omarchy-windows, v0.0.14-preview), which
itself builds on the Omarchy desktop by Basecamp, the macOS try-omarchy
architecture, the x86_64 guest builder by jorge-huxley, and the WINQ-EMU
QEMU fork by cmspam. The fork is fully disclosed and visible:

- `NOTICE.md` and the README's "Provenance and credits" section name every
  upstream project with links;
- the release history inherited from upstream is preserved verbatim in
  `CHANGELOG.md` below a divider;
- the guest image is produced by 45 numbered patches applied to a pinned
  upstream builder commit, all public in `guest-build/`, so every non-
  upstream byte is reviewable;
- we do not sign any upstream-built binary. Only `SavantOS.exe`, built
  from this repository's reviewed source by this repository's workflow,
  is submitted for signing; the forked guest components are distributed
  with their own SHA256 digest verification as described above.

## Code signing policy (commitment)

Upon approval we will publish a "Code signing policy" section on the
repository home page and release pages containing the required statement —
"Free code signing provided by SignPath.io, certificate by SignPath
Foundation" — along with the team roles above and the privacy statement
below. Draft already prepared. Every signing request will be approved
manually by the approver; no automatic signing.

## Privacy policy

This program will not transfer any information to other networked systems
unless specifically requested by the user or the person installing or
operating it. The launcher contacts github.com/savant0x/SavantOS solely to
download and verify updates and release assets; crash diagnostics are
generated locally and leave the machine only if the user sends them.

## Contact

Repository owner: https://github.com/savant0x
(Preferred contact: GitHub issue or the email on the GitHub profile.)
