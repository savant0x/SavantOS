# SignPath Foundation Application — SavantOS

Prepared 2026-09-11. Submit at https://signpath.org/ (Apply). Everything
below is ready to paste; fields marked ACTION need the operator.

## Why SavantOS qualifies

- **License:** Apache-2.0, OSI-approved, no commercial dual-licensing
  (`LICENSE`). Guest image components remain GPL/BSD etc. from Arch and the
  Omarchy desktop — all open, none proprietary to us.
- **Maintained:** active repository, CI on every PR, weekly lock-refresh
  automation, governance under the ECHO protocol.
- **Released:** v0.0.1 published 2026-09-11 with full provenance assets
  (build-spec.json, guest-manifest.json, provenance.json, packages.lock.txt,
  signed SHA256SUMS) — the release trail demonstrates binaries built from
  the public source.
- **Documented:** README describes functionality, install, and uninstall;
  in-app uninstall via Apps & features, Settings, and `-uninstall`.
- **No malware / no hacking tools:** a hypervisor launcher for the user's
  own machine; enables Windows Hypervisor Platform with an elevated helper
  and documents it.
- **Sign your own binaries only:** only `SavantOS.exe` (built by the
  Release workflow from this repo) will be submitted for signing. The guest
  image, kernel, initramfs, and WINQ-EMU runtime are NOT Authenticode-signed
  by us; they ride the project's Ed25519-signed SHA256SUMS digest chain
  verified by the launcher at install/update time. Upstream-forked guest
  components are covered by that digest chain, not by the Foundation
  certificate — consistent with the "unsigned upstream binaries inside
  signed packages" allowance.

## Fork disclosure (address proactively in the application)

SavantOS is a hard fork of omacom/try-omarchy-windows (itself built on the
Omarchy desktop and the WINQ-EMU QEMU fork). Per the Foundation's fork
clause: we do not sign upstream binaries; provenance is documented in
NOTICE.md and the CHANGELOG divider; the guest-build/ patch series (45
numbered patches against a pinned upstream builder commit) and the
runtime-build/ source locks are public, so every non-upstream byte is
reviewable and every release records what was built.

## What signing covers

| Artifact | Protection |
| --- | --- |
| SavantOS.exe | Authenticode (SignPath Foundation cert) |
| Guest image, runtime, all release assets | Ed25519-signed SHA256SUMS, digest pinned in the launcher source |
| Update manifests (update.json / update-v2.json) | Ed25519 signatures, public key pinned in app/update.go |

## Repository-side prerequisites before integration

1. ACTION — Submit the application (operator, via signpath.org Apply).
2. Add a public "Code signing policy" section to README.md (draft below).
   Publish it only after Foundation approval.
3. On approval: create a SignPath.io OSS subscription, link the Trusted
   Build System GitHub.com project, install the SignPath GitHub App on the
   repository, define the artifact configuration (ZIP-rooted
   `<zip-file> -> <file path="SavantOS.exe"/>` with version-info metadata
   restrictions; ProductName "SavantOS", ProductVersion = release tag, a
   `version` user parameter the workflow already passes), then set four
   values: secret SIGNPATH_API_TOKEN and vars SIGNPATH_ORGANIZATION_ID,
   SIGNPATH_PROJECT_SLUG, SIGNPATH_SIGNING_POLICY_SLUG. The workflow is
   pre-wired: `phase=publish` with `signing=signpath` uploads the unsigned
   launcher, submits via signpath/github-action-submit-signing-request@v2
   (pinned c92b9587), promotes the signed exe back, and the existing
   Authenticode verification + Ed25519 feed signing run unchanged. OSS
   constraint honored: the publish job runs on GitHub-hosted windows-2025.

## Draft: Code signing policy (for README.md after approval)

> ## Code signing policy
>
> Free code signing provided by SignPath.io, certificate by SignPath
> Foundation.
>
> - Committers and reviewers: [Members team](LINK)
> - Approvers: [Owners](https://github.com/savant0x) (repository owner)
> - Privacy policy: This program will not transfer any information to other
>   networked systems unless specifically requested by the user or the
>   person installing or operating it. (The launcher contacts
>   github.com/savant0x/SavantOS solely to download and verify updates;
>   crash diagnostics are generated locally and only leave the machine if
>   the user sends them.)
> - Every release is signed only after a manual approval step in the
>   Release workflow.
