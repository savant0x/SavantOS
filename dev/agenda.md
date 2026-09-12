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

- Hardening done 2026-09-11: branch rulesets active on main (no
  force-push/deletion, no bypass; PR + 1 approval + CODEOWNERS + required
  checks, maintainer bypass in pull_request mode). SignPath policy
  branch_rulesets uncommented to match — direct pushes to main are gone;
  everything lands by PR now.
- Next release exercise: prepare → pin → publish cycle on a real tag with
  the executed playbook (exec-bit and CRLF gates now in the tree).

## Waiting on operator

- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).
