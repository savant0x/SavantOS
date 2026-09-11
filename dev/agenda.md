# Agenda

Operator-visible working agenda. Kept under 50 lines; the Scribe refreshes it
at session end.

## Now

- Publish the SavantOS lineage: create the `savant0x/SavantOS` GitHub
  repository (private), push `main` (seven commits, FID-2026-0910-001
  complete and archived).

## Next

- First SavantOS guest image build via the Release workflow (required before
  first-run download can succeed — the launcher pins savant0x v0.0.1 and the
  placeholder manifest is fail-closed by design).
- Move the Ed25519 update-signing private key
  (`/c/Users/spenc/dev/.savantos-keys/savantos-update-signing-key.b64`) into
  the GitHub release environment secret `SAVANTOS_UPDATE_SIGNING_KEY`.
- Tag v0.0.1 when the Release workflow publishes the factory image.

## Waiting on operator

- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).
