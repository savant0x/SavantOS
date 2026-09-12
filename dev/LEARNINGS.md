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
- 2026-09-10 — toolchain: the docs gate is repo-local (`bun run lint:md`;
  markdownlint-cli 0.49.1 via bun, config byte-copied from savant-code).
  Every ignore-list entry carries a date and reason; the README exemption
  dies when its rebrand rewrite lints clean.
- 2026-09-10 — config edits: a one-line YAML insertion lost its 2-space
  indent and silently re-keyed the mapping; the `python3 -c yaml.safe_load`
  parse caught it. Parse config files after every edit to them — eyeballs
  miss indentation.
- 2026-09-10 — governance: quality limits are targets, not descriptions —
  when a canonical standard and a repo config disagree, align the config to
  the standard and grandfather inherited debt in a dated comment, rather
  than loosening limits to match legacy code. Decision evidence (2026-09-10):
  66/73 non-test Go files already ≤350 lines; only inherited upstream files
  exceed.
- 2026-09-11 — release: executables committed from Windows lose the exec
  bit (the zip baseline had none; Windows has none), and every Linux-runner
  invocation of a tracked `.sh`/`.py` then dies with exit 126 — first
  `build-guest.sh` in the Release workflow, then `validate-pin.py` in CI.
  Remedy: `git update-index --chmod=+x` (content-free mode commit). After
  any Windows-side import, audit `git ls-files -s | grep 100644` for
  scripts.
- 2026-09-11 — release: Windows toolchains emit CRLF at every boundary, and
  it bit three times in one day — `prepare-assets.sh` consumed a python3
  pipe with `\r\n` (digest field corrupted; fixed with `tr -d '\r'`), a
  test fixture wrote via text mode (pin `newline='\n'`), and PowerShell
  `Set-Content` published `SavantOS.exe.sha256` with CRLF, breaking
  `sha256sum -c` everywhere off-Windows (the checksum tool looked for a
  file named `SavantOS.exe\r`; fixed with `[IO.File]::WriteAllText` +
  `` `n ``). Rule: any artifact consumed by non-Windows tooling pins LF
  explicitly.
- 2026-09-11 — CI: GitHub forbids Actions creating pull requests by
  default; the refresh-guest-lock weekly cron pushes its branch but the
  `gh pr create` step fails until the repo's workflow permissions allow
  it. Enabled 2026-09-11; that day's lock PR went out under the operator
  token instead.