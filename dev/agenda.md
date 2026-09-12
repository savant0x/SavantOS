# Agenda

Operator-visible working agenda. Kept under 50 lines; the Scribe refreshes it
at session end.

## Now

- SignPath application package is COMPLETE (2026-09-11): paste-ready
  submission at `dev/signpath-submission.md` (all claims tree-verified;
  the one ACTION — confirm GitHub MFA — is the operator's), eligibility
  mapping + fork disclosure in `dev/signpath-application.md`, workflow
  pre-wired (`signing=signpath`), policy stub active with branch_rulesets
  live. CHECKPOINT: operator submits at
  https://signpath.io/solutions/open-source-community → Apply, then we
  wait out their review (days–weeks).
- On approval: register project `savantos` / policy `release-signing`,
  install the SignPath GitHub App, set `SIGNPATH_API_TOKEN` + the three
  `SIGNPATH_*` vars, paste the Code signing policy into README, and
  publish the next release with `signing=signpath`.

## Next

- Done 2026-09-11: branch rulesets active on main (no force-push/deletion,
  no bypass; PR + 1 approval + CODEOWNERS + required checks). Direct
  pushes to main are gone — everything lands by PR (admin override for
  the solo maintainer's own PRs, no self-approval).
- Next release exercise: prepare → pin → publish cycle on a real tag with
  the executed playbook (exec-bit and CRLF gates now in the tree).

## Waiting on operator

- Submit the SignPath application (checkpoint above) after confirming MFA.
- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).
