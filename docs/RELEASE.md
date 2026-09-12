# Release playbook

The operator's cycle for shipping a SavantOS release:
**prepare → pin → test → publish**, one tag end to end.

> **Claims block — re-verify before editing this file.** Every fact below was
> grep-verified against the tree on 2026-09-11. If you change the workflow,
> re-run these and update this block or leave it broken on purpose:
>
> ```bash
> grep -n "inputs.phase" .github/workflows/release.yml   # lines 48, 132, 214
> grep -n "SAVANTOS_UPDATE_SIGNING_KEY" .github/workflows/release.yml  # 143, 226
> grep -n 'currentVersion' app/update.go                 # line 19
> grep -n "signing:" .github/workflows/release.yml       # workflow_dispatch input
> ```

The release workflow (`.github/workflows/release.yml`, name: `Release`) has
three phases selected by the `phase` input: `prepare` (line 48),
`signing-check` (line 132), and `publish` (line 214). It is dispatched with
`phase`, `release_tag`, and `signing` inputs — `signing` selects the
Authenticode path for the launcher; the Ed25519-signed update feeds are
produced in every mode.

## Prerequisites (one-time)

- `SAVANTOS_UPDATE_SIGNING_KEY` secret in the `release` GitHub environment:
  base64 PKCS#8 Ed25519 private key paired with `updatePublicKeyHex`
  (`app/update.go:29`). Set from the operator machine's key directory; never
  stored in the repo.
- SignPath activation (future): see `dev/signpath-activation-runbook.md` for
  the post-approval checklist — secret `SIGNPATH_API_TOKEN`, vars
  `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`,
  `SIGNPATH_SIGNING_POLICY_SLUG`, their GitHub App, and the artifact
  configuration. The `signing=signpath` path is already wired in the workflow
  and fails fast without those values.
- The Azure Trusted Signing values are **not configured** (no Azure account).
  Do not dispatch `signing=azure`.

## Branch rules that shape every release

`main` is protected by one ruleset: force-pushes and deletion are banned with
zero bypass actors. Direct pushes to `main` are the normal flow (operator
directive, 2026-09-12); CI runs the full check suite (Launcher, Windows
launcher, Guest contract) on every push to `main`, and a push is not done
until those checks are green. Consequences for the release cycle:

- The **pin commit travels by direct push** after checks are green.
- A release commit that fails gates is fixed by a **new commit and a fresh
  dispatch** — no re-running a stale build (matches the SignPath policy's
  `disallow_reruns: true` in `.signpath/policies/savantos/release-signing.yml`).

## Phase 1 — prepare (build the draft)

Dispatch from `main` at the commit you intend to ship, after the CHANGELOG
section for the new version exists in `main` and `main`'s checks are green:

```bash
gh workflow run release.yml --ref main \
  -f phase=prepare -f release_tag=vX.Y.Z -f signing=none
```

`prepare` (~1–2 hours) applies the locked guest patches, builds the guest
image and WINQ-EMU runtime from their lock files, boots the instant account
headlessly as a smoke test, and uploads everything to a **draft** release. A
failed prepare is diagnostic gold: it catches lock drift or contract breakage
before you ever see it. If the guest package lock drifted, run the
`Refresh guest lock` workflow, merge its PR, and re-dispatch.

## Phase 2 — pin (commit the manifest)

The publish phase **refuses to run** against the placeholder manifest, so the
pin must land first:

1. Download the draft's `SHA256SUMS` into `app/testdata/SHA256SUMS.vX.Y.Z`.
2. Update `defaultSumsSHA256` and the release base in `app/manifest.go` to the
   real digest.
3. Verify and land by PR:

   ```bash
   python scripts/release/validate-pin.py vX.Y.Z
   cd app && go build ./... && go vet -unsafeptr=false ./... && \
     go test ./... && gofmt -l . && cd ..
   git checkout -b release/pin-vX.Y.Z
   git add app/manifest.go app/testdata/SHA256SUMS.vX.Y.Z
   git commit -m "feat(release): pin vX.Y.Z manifest digest"
   git push -u origin release/pin-vX.Y.Z
   gh pr create --fill && gh pr merge --squash --admin
   ```

## Phase 3 — test the draft on physical Windows

Draft assets need authentication; the launcher downloads anonymously. Do not
point the launcher at the draft URL. Serve the assets locally instead:

1. Download every draft asset to one folder
   (`gh release download vX.Y.Z --dir candidate-assets` with an
   authenticated `gh`, or a logged-in browser).
2. From that folder serve loopback: `python -m http.server 18080 --bind 127.0.0.1`.
3. Use a **copied data directory** — never the only copy of a real guest:

   ```powershell
   .\SavantOS.exe `
     -dir C:\SavantOSCandidate `
     -release http://127.0.0.1:18080 `
     -sums-sha256 SHA256SUMS_DIGEST `
     -runtime-release http://127.0.0.1:18080 `
     -runtime-sums-sha256 SHA256SUMS_DIGEST `
     -no-update
   ```

4. Confirm boot, reboot, poweroff, and that a second launch does not repeat
   provisioning. For the rollback check, kill the first boot before userspace
   readiness, start again, and confirm the payload re-downloads cleanly.
5. GPU, idle CPU, audio, input, resize, and fullscreen checks per
   `docs/RUNTIME-VALIDATION.md`. Keep the release draft until they pass.

## Phase 4 — publish

```bash
gh workflow run release.yml --ref main \
  -f phase=publish -f release_tag=vX.Y.Z -f signing=none
```

`publish` (~10–15 min) re-validates the draft against the source pin, runs
launcher tests, builds the optimized launcher, applies the chosen Authenticode
path (or none), signs the update metadata with the Ed25519 key, uploads, and
publishes. After it goes green, verify independently — outside the pipeline:

```bash
curl -sLO https://github.com/savant0x/SavantOS/releases/latest/download/SavantOS.exe
curl -sLO https://github.com/savant0x/SavantOS/releases/latest/download/SavantOS.exe.sha256
sha256sum -c SavantOS.exe.sha256   # and spot-check the digest manually once
gh release view vX.Y.Z --json isDraft,isPrerelease,publishedAt
```

If any public check fails, the release is defective: fix forward with a patch
release (v0.0.x+1). Do not re-run publish on the same tag.

## Choosing `signing`

| Input | When | Requirements |
| ----- | ---- | ------------ |
| `none` | Now — the shipped default | None. Ed25519 update feeds still sign. Users see SmartScreen once on *downloaded* copies; locally built copies never do. |
| `signpath` | After Foundation approval | `SIGNPATH_*` secret + 3 vars, their GitHub App, artifact configuration (runbook: `dev/signpath-activation-runbook.md`). Waiting on a human approver — up to the 1-hour timeout. |
| `azure` | Only if an Azure Trusted Signing account is ever created | Six `AZURE_*` values on the `release` environment. **Currently unconfigured — do not dispatch.** |

## Update-feed notes

Each release carries `update.json` and `update-v2.json` (identical pair,
signed with the Ed25519 key — see the "Prepare current and legacy update
feeds" step in `release.yml`). The launcher verifies manifests against the
pinned `updatePublicKeyHex`, accepts only newer supported versions from the
expected repository URL, and stages updates atomically with rollback. The
bridge-preview transition scheme described in the superseded upstream release
doc was **not carried into this workflow**; stable-transition design will be
(re)documented here if/when that work lands.
