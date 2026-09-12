# SignPath Activation Runbook — execute on Foundation approval

Prerequisite: the approval email from SignPath Foundation. Everything else
is prepared: workflow wired (`signing=signpath` in release.yml), policy file
at `.signpath/policies/savantos/release-signing.yml`, branch rulesets live.
Slugs used throughout MUST match that file path and the submission text.

## 1. SignPath.io account and organization access

1. Create/claim the SignPath.io account for the operator (SSO or email).
2. Enable MFA on the SignPath account immediately (Foundation rule).
3. The approval email grants your user a role in the SignPath Foundation
   organization. Sign in and switch to that organization.

## 2. Register the project and signing policy

In the Foundation organization:

1. Create project with slug exactly `savantos`.
2. Create signing policy with slug exactly `release-signing` on that
   project (name it "Release signing"). If the Foundation's onboarding
   pre-creates slugs that differ, STOP and rename the repo-side file
   `.signpath/policies/savantos/release-signing.yml` to match, then update
   the repo variables in step 5 accordingly.
3. Policy settings: require manual approval for each signing request;
   assign the operator as Approver (and Submitter).
4. Trusted Build System: link the predefined **GitHub.com** build system to
   the project (the connector verifies that signing requests originate
   from this repository's GitHub Actions runs and that all jobs ran on
   GitHub-hosted runners — our publish job is windows-2025).

## 3. Install the SignPath GitHub App

Install "SignPath" (GitHub App) on savant0x/SavantOS, repository access
granted. Without it, the connector cannot verify workflow origin and
signing requests are rejected.

## 4. Artifact configuration

Create an artifact configuration on the project (slug `release`, or set
`artifact-configuration-slug` in the workflow step if you name it
differently):

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <parameters>
    <parameter name="version" required="true" />
  </parameters>
  <zip-file>
    <pe-file path="SavantOS.exe"
             product-name="SavantOS"
             product-version="${version}">
      <authenticode-sign description="SavantOS launcher"
                         description-url="https://github.com/savant0x/SavantOS" />
    </pe-file>
  </zip-file>
</artifact-configuration>
```

Notes:

- `<zip-file>` root because the workflow uploads the exe with
  actions/upload-artifact (which wraps it in a ZIP).
- The `product-name`/`product-version` restrictions enforce the
  Foundation's metadata rule: signing fails unless the exe's version
  resource says ProductName=SavantOS and ProductVersion equals the
  release tag parameter.
- Verify at config time which PE value SignPath compares (string
  ProductVersion vs numeric FixedFileVersion). app/versioninfo.json
  carries ProductVersion "v0.0.1" — if SignPath reads the numeric value,
  set the restriction to the numeric form of the tag instead.

## 5. GitHub values

```bash
# Secret (token from SignPath.io profile → API tokens; needs Submitter
# permission on the project/policy):
set -a; source .env.local; set +a
printf '%s' '<SIGNPATH-API-TOKEN>' | gh secret set SIGNPATH_API_TOKEN \
  --repo savant0x/SavantOS --env release

# Vars:
gh api -X PATCH repos/savant0x/SavantOS \
  -f description='Sovereign agentic OS host for Windows' # ( unrelated )
gh variable set SIGNPATH_ORGANIZATION_ID   --repo savant0x/SavantOS --body '<org-guid from SignPath org settings>'
gh variable set SIGNPATH_PROJECT_SLUG      --repo savant0x/SavantOS --body 'savantos'
gh variable set SIGNPATH_SIGNING_POLICY_SLUG --repo savant0x/SavantOS --body 'release-signing'
```

(The workflow references `${{ vars.* }}` and `${{ secrets.SIGNPATH_API_TOKEN }}`
by exactly these names.)

## 6. Release-gate change: versioninfo.json must match the tag

Because the artifact configuration enforces ProductVersion == tag, every
release now bumps `app/versioninfo.json` (FileVersion/ProductVersion
fields) in the pin commit. Add this to the release checklist — a missed
bump fails at signing time, which is the desired gate.

## 7. Test signing run (full pipeline, low blast radius)

Use a preview tag: release-order.py will NOT promote a preview over the
stable v0.0.1, and the workflow marks it prerelease — public, but never
"Latest".

1. `gh workflow run release.yml -f phase=prepare -f release_tag=v0.0.2-preview`
2. When green: download SHA256SUMS from the draft, land the pin commit
   (fixture + defaultSumsSHA256 + versioninfo.json bump) **via PR** —
   direct pushes to main are gone.
3. `gh workflow run release.yml -f phase=publish -f release_tag=v0.0.2-preview -f signing=signpath`
4. Watch the run: the SignPath step creates a signing request that waits
   (`wait-for-completion-timeout-in-seconds: 3600`).
5. Approve the request in SignPath.io (Signing Requests → the pending
   request → Approve). This is the manual-approval control promised in
   the code signing policy.
6. The run resumes: promotes the signed exe, verifies Authenticode,
   signs the Ed25519 feeds, uploads, publishes.

## 8. Post-run verification (two independent methods)

```powershell
# Method 1: signature validity + Foundation subject
$sig = Get-AuthenticodeSignature .\SavantOS.exe
$sig.Status; $sig.SignerCertificate.Subject   # expect Valid, CN=SignPath Foundation

# Method 2: digest equality between the published feed and the signed exe
(Invoke-RestMethod https://github.com/savant0x/SavantOS/releases/download/v0.0.2-preview/update-v2.json).launcher.sha256
(Get-FileHash .\SavantOS.exe -Algorithm SHA256).Hash.ToLowerInvariant()
```

Both must agree. Then verify sha256sum -c on the checksum asset and the
prerelease marking on the release page.

## 9. Go stable

Merge the README "Code signing policy" section (draft in
dev/signpath-application.md) via PR, drop the SmartScreen warning note
from the Install section, and run the next stable release with
`signing=signpath` end-to-end. Update dev/signpath-submission.md's
"commitment" wording to "live".

## Failure modes worth knowing

- Signing request rejected with origin error → GitHub App not installed,
  workflow re-run (disallow_reruns blocks re-runs; use a fresh dispatch),
  or a non-GitHub-hosted runner joined the job graph.
- Metadata mismatch → versioninfo.json not bumped to the tag (step 6).
- Timeout after 1 h → nobody approved in the UI; approve, then re-dispatch
  (the failed run's request stays in the audit trail).
- Foundation slug differences → rename repo policy file + re-point the two
  slug variables; never widen the policy to "make it work".
