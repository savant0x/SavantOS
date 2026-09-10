# Agenda

Operator-visible working agenda. Kept under 50 lines; the Scribe refreshes it
at session end.

## Now

- FID-2026-0910-001 — SavantOS rebrand and governance scaffold (status:
  fixed; identity sweep commits landing).

## Next

- First SavantOS guest image build via the Release workflow (required before
  first-run download can succeed — launcher pins savant0x v0.0.1).
- Move the new Ed25519 update-signing private key to GitHub release secrets
  (`SAVANTOS_UPDATE_SIGNING_KEY`) when publishing.
- Create savant0x/SavantOS on GitHub and push the completed lineage.

## Waiting on operator

- Quality-limits reconciliation: canonical go.md overrides (350/50/120) vs
  `protocol.config.yaml` quality block (600/60/120 advisory).
- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).