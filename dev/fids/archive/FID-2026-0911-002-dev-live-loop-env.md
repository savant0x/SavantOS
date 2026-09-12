# FID: Dev live-loop environment — seeded data dir, shared folder, launch script

**Filename:** `FID-2026-0911-002-dev-live-loop-env.md`
**ID:** FID-2026-0911-002
**Severity:** low
**Status:** closed
**Created:** 2026-09-11 21:25
**YAGNI-Compliance:** Pending

---

## Summary

The operator asked for a ready-to-use developer environment enabling live
iteration on SavantOS: a dedicated `savantos-dev` data directory, a shared
folder, and a launch script wiring the `-ssh`/`-share` live loop. The
launcher already supports every needed primitive (`-ssh`, `-share`,
`-instant`, `-no-update`, `-dir`); this FID composes them into one
`scripts/dev/dev-vm.sh` entry point plus seed tooling, so a developer goes
from clean machine to ssh-able, shared-folder VM in one command.

## Environment

- **OS:** Windows 11 Pro, Git Bash (MSYS2)
- **Language/Runtime:** bash script driving the Go launcher (`app/`), plus the
  repo's `sparsetool` Go utility for sparse-preserving data-dir seeding
- **Tool Versions:** OpenSSH `/usr/bin/ssh`, `go` for optional sparsetool build
- **Commit/State:** `main` @ `6b33108`, clean tree

## Detailed Description

### Problem

The live dev loop exists as capability but not as workflow: a developer must
hand-assemble flags, know the seed-copy trick for skipping the 1.7 GB payload
download, know the `savant` trial username for SSH, and remember which ports
the QMP/agent planes use. Nothing in `scripts/` composes this today (vmtest
harness targets a *nested Windows VM in CI-like conditions*, not a host-side
dev loop).

### Expected Behavior

One command (or three explicit subcommands) provides:

1. `init` — create `C:\savantos-dev\` data dir and `C:\savantos-share\`
   folder with seed content; seed the data dir from an existing install
   (sparse copy, ~seconds) or fall back to letting the launcher download the
   factory payload on first boot.
2. `boot` — launch a locally built dev launcher against the dev dir with
   `-share`, `-ssh 2222`, `-instant`, `-no-update`; wait for readiness; print
   the ssh command.
3. `shell` — ssh into the running guest (`savant@127.0.0.1 -p 2222`).

### Root Cause

Capability/workflow gap, not a defect: the flags exist (`main.go:131–158`) but
no composition layer was ever written for host-side development.

### Evidence

```text
$ grep -n 'flag\.' app/main.go | head -40   (recon 2026-09-11 21:20)
131: -dir, 133: -share, 145: -instant, 148: -forward (repeatable),
149: -ssh <port> (forwards to guest sshd, starts sshd, authorizes
     ~/.ssh/id_*.pub via -ssh-key default), 159: -no-update

$ ls /c/Users/spenc/Downloads/savantos-e2e/data/
SavantOS.exe guest/ runtime/ provision-mode settings.json ... (12 GiB actual,
31 GiB apparent; rootfs.ext4 6442450944 bytes sparse; provision-mode=instant)

$ which ssh; ls ~/.ssh/*.pub
/usr/bin/ssh   /c/Users/spenc/.ssh/id_ed25519.pub

$ netstat -an | grep -E ':(2222|4450|4451) '   → clean, no conflicts

$ scripts/vmtest/README.md — harness targets nested-Virtualization Windows VM
(scripts/winps.sh needs a Linux-side SSH client to a dockur/windows container);
NOT a host dev loop. sparsetool: `extract ZIP DEST | copy SRC DST | hash DIR`
(main.go:206).
```

## Impact Assessment

### Affected Components

- New: `scripts/dev/dev-vm.sh` (the composition layer)
- New: `scripts/dev/README.md` (usage)
- Seed content: `C:\savantos-share\` (outside repo, created on demand)
- Optional dev data dir: `C:\savantos-dev\` (outside repo)

### Risk Level

- [ ] Critical
- [ ] High
- [ ] Medium
- [x] Low — additive developer tooling; zero product-code changes; all state
      lives outside the repo and outside any real install

## Proposed Solution

### Approach

Compose existing primitives in a bash script following repo script
conventions (LF endings, no CRLF; pass gates). Seeding uses `sparsetool copy`
built on demand (`go build` in `scripts/vmtest/sparsetool`) from the e2e
install when present; otherwise first `boot` downloads the factory payload
against the pinned digest (one-time ~1.7 GB).

### Steps

1. Write `scripts/dev/dev-vm.sh` with subcommands `init|boot|shell|stop|help`
   and a `--seed-from DIR` option; all flags overridable by env
   (`SAVANTOS_DEV_DIR`, `SAVANTOS_DEV_SHARE`, `SAVANTOS_DEV_PORT`). Status:
   **implemented** (`scripts/dev/dev-vm.sh`).
2. Write `scripts/dev/README.md`. Status: **implemented**
   (`scripts/dev/README.md`).
3. `init`: create share folder with a `hello.sh` smoke script; create dev
   dir; seed from `--seed-from` (default: the e2e install if it exists) via
   `sparsetool copy`; mark seeded receipt. Status: **implemented and
   executed** — share created; dev dir seeded **12 GiB in 22 s**, zero
   downloads. First attempt hit a real bug: sparsetool is its own Go module,
   so building it via the repo-root module fails (`cannot find main
   module`); fixed by building from inside the sparsetool directory.
4. Live verification on the operator machine — Status: **PASSED**
   (2026-09-11 21:25–21:27, launcher pid 20552, dev VM left running for the
   operator):

   ```text
   [boot] QMP 127.0.0.1:4450 LISTENING; agent connected (2);
          "guest userspace announced ready" (vm/shell.log 21:25:34);
          winkey QMP connected on 4446; clipboard guest connected
   [ssh port 2222] reachable ~15 s after launch
   host->guest:  echo ... > savantos-share/host-note.txt
                 dev-vm.sh shell cat /mnt/host/host-note.txt
                 → "hello from windows dev host 2026-09-11T21:26:37-04:00"
   guest:        uname -a → Linux savantos 7.2.4-arch1-2; whoami → savant
   guest->host:  dev-vm.sh shell bash /mnt/host/hello.sh
                 → from-guest.txt on Windows: "dev share works: savantos
                   2026-09-11T21:27:23-04:00"
   ```

   One correction during verification: the smoke script used `hostname`,
   absent in the minimal guest — replaced with `uname -n` (generator + live
   copy), re-run clean.
5. Land via PR-only main; CHANGELOG entry; FID close+archive PR. Status:
   **pending** (in flight).

### Verification

- Script passes `bash -n` and shellcheck if available (not gated).
- Live loop: ssh round-trip succeeds; file written to `/mnt/host` from guest
  appears in `C:\savantos-share\` on Windows (and vice versa).
- `git ls-files` shows LF endings (`.gitattributes` already enforces); repo
  gates: lint:md for README, no Go changes (Go gates N/A).

## Verification Gates

Executed 2026-09-11 on branch `dev/live-loop-env`:

```text
$ bash -n scripts/dev/dev-vm.sh   → exit 0
$ bash scripts/dev/dev-vm.sh help → usage prints
$ file scripts/dev/dev-vm.sh      → "Bourne-Again shell script ... executable" (LF)
$ bun run lint:md                 → markdownlint . (exit 0)
Live-loop gates: step-4 transcript above (ssh + share, both directions).
Go gates (app/): N/A — zero Go files touched. (The sparsetool invocation
fix changed only how the script invokes the existing tool — no source change.)
```

## Perfection Loop

### Loop 1 — RED

- **RED:** (a) no composition layer for the host-side dev loop; (b) trap
  identified: seeding must be *sparse-aware* — plain `cp -r` of a 6 GiB
  sparse ext4 materializes 6 GiB and would burn 6+ GB per dev dir; (c) trap:
  the share folder default in the e2e settings.json is the user's real
  `C:\Users\spenc\SavantOS Shared` — the dev env must not touch that;
  (d) trap: Git Bash paths (`/c/...`) must convert to Windows paths for
  launcher flags; (e) `boot` must wait for readiness (QMP 4450 listening +
  userspace-ready marker) before printing the ssh hint, or devs ssh into a
  half-booted guest.
- **GREEN:** design addresses all: sparsetool for (b), dedicated
  `C:\savantos-share` for (c), `cygpath -w` for (d), readiness poll for (e).
- **AUDIT:** evidence above from flag dump, settings.json read, sparsetool
  usage string, port probe.
- **ADVERSARIAL:** "Another dev-machine path layout breaks the script."
  Answered: everything overridable via env vars; no hardcoded `spenc` paths
  in the script (defaults derived from `$USERPROFILE`).
- **CHANGE DELTA:** ~25%.

### Missed Questions

1. **Why seed from the e2e install instead of fresh download?** Fresh costs
   1.7 GB download + decompress; seed costs a sparse copy (~seconds, 12 GiB
   actual → mostly shared extents? No — sparsetool copy writes a new sparse
   file: 12 GiB actual is paid once per dev dir, but zero re-download and
   zero decompress CPU). Seeding wins on time; disk is the trade (125 GiB
   free — fine).
2. **Does copying the data dir copy state the launcher will reject?**
   Receipts (`install-state.json`) match the on-disk files byte-for-byte
   after a faithful copy, so verification passes locally (proven earlier
   today: the launcher accepts existing payload without re-download).
3. **Username for ssh?** Trial/instant account is `savant` (provision-mode
   file confirms `instant`).
4. **Why not also wire QMP helpers?** YAGNI: vmtest's `qmp.ps1` already works
   against host-launched QEMU (port 4450); documenting beats duplicating.
   Referenced in README instead.
5. **Windows Defender / firewall on port 2222?** Loopback-bound listener;
   Windows does not prompt for loopback. Note in README.
6. **`stop` semantics?** Graceful: prefer the tray/window close by the human;
   `stop` offers QMP `system_powerdown` via the vmtest helper if present, else
   prints instructions. Keeps script dependency-light.

### Implementation Evidence (REQUIRED for `closed`)

- [x] **Commit SHA:** `3018843` (squash-merge of PR #8 on main; branch commit
      `545c2a0`)
- [x] **File:line ranges:** scripts/dev/dev-vm.sh (whole file, 5 subcommands);
      scripts/dev/README.md (whole file)
- [x] **Gate output:** pasted in Verification Gates
- [x] **Reproducibility:** `bash scripts/dev/dev-vm.sh help` prints usage on
      any machine with the repo checked out
- [x] **Step statuses:** 1–4 **implemented** (4 with pasted live evidence);
      5 pending merge

### Code Verification Evidence

- [x] Files exist post-implementation (scripts/dev/dev-vm.sh, README.md)
- [x] Implementation matches the Proposed Solution
- [x] Gates pass with pasted tool output (Verification Gates)
- [x] Production call-graph evidence: N/A (script calls launcher binary; no
      Go wiring changed)
- [x] FID status reflects actual implementation state (fixed; closes at
      archive)

### Loop 2 — Independent audit and self-correction

- **RED:** None new — design re-checked against every trap in Loop 1.
- **GREEN:** n/a.
- **AUDIT:** Re-read settings.json share default confirms trap (c) is real
  (`"share": "C:\\Users\\spenc\\SavantOS Shared"`) — dev script will pass
  `-share` explicitly on every launch, never relying on settings.
- **ADVERSARIAL:** "Seeding copies the e2e install's render-probe (GPU state)
  and settings — is that wanted?" Answered: acceptable for dev (same
  machine), and `boot` passes `-share`/`-ssh` explicitly each time so
  settings drift cannot silently change dev behavior. Dev dir is disposable.
- **CHANGE DELTA:** ~8% (additive answers only).

### Loop 3 — Final convergence

- **RED:** Residual: sparsetool must be built before `init` uses it (go
  toolchain present on dev machines by definition of this repo — acceptable).
- **GREEN:** n/a.
- **AUDIT:** Two consecutive passes with no substantive change; converged
  within `protocol.config.yaml` thresholds.
- **ADVERSARIAL:** Verdict: design is honest about its one external dependency
  (seed source) and degrades gracefully (fresh download fallback). Approved
  to proceed to implementation upon operator approval.
- **CHANGE DELTA:** 0%.

## Resolution

- **Closed Date:** 2026-09-11 21:40
- **Fix Description:** `scripts/dev/dev-vm.sh` + `README.md` landed
  (`3018843`): init (sparse seed)/boot (live-log dev launcher + share +
  ssh)/shell/stop composition, everything outside the repo and outside any
  real install. Live-verified end to end on the operator machine; the dev VM
  was left running for operator use.
- **Tests Added:** No automated tests (host-side tooling needing a booted
  guest; verification transcript in this FID serves as the evidence record).
- **Verification Evidence:** lint:md exit 0; bash -n clean; PR #8 required
  checks all pass; live loop: ssh cat round-trip + guest→host file landing
  (timestamps in Implementation Evidence).
- **Archived:** 2026-09-11 21:40 (moved to `dev/fids/archive/`; CHANGELOG
  Unreleased entry appended)

## Lessons Learned

1. Sparse-file awareness is not optional when duplicating VM disks on
   Windows: naive copies cost 6 GiB and minutes; `sparsetool copy` costs
   seconds. Reusable beyond dev tooling (backup/restore paths already know
   this — the tool exists precisely because the launcher's restore path
   needs it).
2. Composition scripts must convert between Git Bash and Windows path
   spaces (`cygpath -w`) at every launcher-boundary — a recurring Windows
   tax this repo keeps paying.
3. Dev environments must never share state with real installs: dedicated
   data dir AND explicit `-share` override on every launch, because the
   launcher persists settings (the e2e install already mutated the user's
   default share path).
