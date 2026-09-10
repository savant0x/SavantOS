# Lessons Learned — SavantOS

Running record of traps, empirical findings, and process lessons. Append-only;
each entry dated. Technical traps specific to QEMU/WHPX live in
`docs/FINDINGS.md` — this file is for engineering-process lessons.

## Format

- **YYYY-MM-DD — area:** lesson in one or two sentences. Evidence or command
  when useful.

## Entries

- 2026-09-10 — governance: the canonical savant-code
  `coding-standards/go.md` is byte-copied, not adapted; repo-specific Go
  contracts live in `AGENTS.md`/`protocol.config.yaml`, never edited into the
  canonical file.
- 2026-09-10 — process: doc changes verify with `markdownlint`
  (lint:md), not typecheck; the Go gates never exercise root-level
  markdown. Run both gates after mixed change sets.
- 2026-09-10 — harness: the `basher` agent executes terminal commands that
  require GREEN/AUDIT/SELF-CORRECT phase; transition before spawning it for
  mutation commands.
- 2026-09-10 — FIDs: a session crash mid-Phase-A left the FID's continuation
  notes stale (claimed "no .git" while the baseline commit had already
  landed). Always re-verify disk ground truth on resume before executing a
  recorded plan.