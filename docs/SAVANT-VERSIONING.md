# Savant Versioning

**Current release:** SavantOS `0.0.1`.

SavantOS does **not** use SemVer. It uses **Savant Versioning** — a base-10
iteration counter with epistemic resets, matching the convention used across
the Savant ecosystem (see NOTICE.md for lineage).

## Rules

- Versions start at `0.0.1`, not `1.0.0`.
- The last digit counts iterations: `0.0.1` → `0.0.2` → ... → `0.0.10`.
- After 10 iterations, bump the middle digit: `0.0.10` → `0.1.0`.
- A **paradigm break** (fundamentally different architecture/thinking) resets
  the entire count to `0.0.1` — even if the underlying ideas are mature.

## Why

Industry SemVer is calibrated for teams that ship slowly. At Savant's dev
velocity, SemVer would move `1.0.0` → `5.0.0` in a week — signaling "massive
changes" when it's just normal iteration speed. The number becomes noise.

Savant Versioning makes the version string a **humility meter**: `0.0.3`
means "three iterations into the current foundation, still proving the base"
— not "beta."

The reset discipline is the moat: most teams carry a version number forward
through a rewrite (pretending continuity). Savant resets because a paradigm
break is a *new beginning*, not a continuation.

## SavantOS application

- SavantOS is a hard fork of Try Omarchy for Windows (v0.0.14-preview
  upstream at the fork point). The fork is a paradigm break for this
  codebase's identity and direction, so the lineage restarts at `v0.0.1`.
- `app/update.go` `currentVersion` and `app/versioninfo.rc` carry the
  launcher version; `versioninfo_test.go` enforces they stay in sync with
  the compiled resource object.
- Pre-release tags (`-preview`) follow the release pattern in
  `app/update.go` (`releaseVersionPattern`); the SavantOS lineage may use
  them for its own pre-releases but inherits none from upstream.

*This is a Spencer-authored convention, not an industry standard.*