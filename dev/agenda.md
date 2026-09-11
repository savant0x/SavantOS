# Agenda

Operator-visible working agenda. Kept under 50 lines; the Scribe refreshes it
at session end.

## Now

- First SavantOS guest image build via the Release workflow (required before
  first-run download can succeed — the launcher pins savant0x v0.0.1 and the
  placeholder manifest is fail-closed by design).

## Next

- Load the Ed25519 update-signing private key
  (`/c/Users/spenc/dev/.savantos-keys/savantos-update-signing-key.b64`) into
  the GitHub release environment secret `SAVANTOS_UPDATE_SIGNING_KEY`
  before the Release workflow runs.
- Tag v0.0.1 when the Release workflow publishes the factory image.

## Waiting on operator

- Whether to retain the two dropped SavantOS-specific Go rules in
  `AGENTS.md` (`filepath.Join` path building; test-fixture skip-or-fail
  messaging).
