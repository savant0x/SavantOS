# Agenda

Operator-visible working agenda. Kept under 50 lines; the Scribe refreshes it
at session end.

## Now

- Submit the SignPath Foundation application (`dev/signpath-application.md`
  has the eligibility mapping and fork disclosure; review takes days–weeks).
  On approval: register project `savantos` / policy `release-signing`,
  install the SignPath GitHub App, set `SIGNPATH_API_TOKEN` +
  the three `SIGNPATH_*` vars, paste the Code signing policy into README,
  and publish the next release with `signing=signpath`.

## Next

- Optional hardening: branch protection on main (no force-push, PR +
  approval, CODEOWNERS on `.signpath/`), then uncomment the staged
  branch_rulesets rules in `.signpath/policies/savantos/release-signing.yml`.
- Next release exercise: prepare → pin → publish cycle on a real tag with
  the executed playbook (exec-bit and CRLF gates now in the tree).

## Waiting on operator

- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).
