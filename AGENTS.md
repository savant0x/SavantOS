# SavantOS — Contributor & Agent Guide

SavantOS is the sovereign agentic OS host for Windows: a signed,
self-updating Go launcher that runs a Linux desktop guest under QEMU/WHPX.

> **All engineering work is governed by the ECHO Protocol ([ECHO.md](ECHO.md)).**
> Read it 0-EOF before touching anything. Changes below the complexity
> threshold go through Hybrid Mode (direct write + immediate verification);
> complex work goes through the FID Perfection Loop.

## Key Technologies

- **Go 1.27** launcher (`app/`, module `github.com/savant0x/SavantOS/app`)
- **QEMU/WHPX** virtualization — GPU path via WINQ-EMU (Venus/virgl), CPU
  fallback via llvmpipe
- **PowerShell 5.1+** host tooling (`scripts/`)
- **Python 3** release tooling (`scripts/release/`, `runtime-build/`)
- **Arch-based guest** built from pinned upstream + 44 patches (`guest-build/`)
- **Ed25519 signed updates** with SHA256-authenticated manifests

## Repo Map

| Path | Purpose |
| ---- | ------- |
| `app/` | Launcher source; tests are colocated `*_test.go` |
| `app/cmd/sign-update/` | Update-manifest signing tool |
| `app/testdata/` | Embedded fixtures (SHA256SUMS) |
| `guest-build/` | Guest-image patch series + source/runtime locks |
| `runtime-build/` | Source-locked QEMU runtime build |
| `scripts/` | Host tooling (bootstrap, vmtest harness, release pipeline, guest overlay) |
| `assets/favicon/` | Brand assets — source of truth for `app/icon.ico` |
| `docs/` | Documentation; `FINDINGS.md` = technical history (provenance banner) |
| `dev/` | FIDs, session summaries, lessons, scratchpad |
| `templates/` | FID + session-summary templates |

## Validation (the gates)

```bash
cd app
go build ./...                    # zero errors
go vet -unsafeptr=false ./...     # zero warnings (win32 interop contract)
go test ./...                     # zero failures
gofmt -l .                        # empty output
```

Plain `go vet ./...` intentionally flags `unsafe.Pointer` usage in win32
callback/COM interop — that is contractual (see `.github/workflows/ci.yml`);
the `-unsafeptr=false` gate matches upstream CI. Windows-specific tests
(`*_windows_test.go`) only run on Windows hosts.

Release tooling gates: `python3 -m py_compile scripts/release/*.py`,
`bash -n runtime-build/*.sh`, `scripts/release/build-guest.sh --contract-only`.

## Conventions

- **Naming**: exported Go identifiers need doc comments; errors are wrapped
  with `%w`; no `_` discards of `error` returns; constants over magic strings.
- **Windows interop**: `//go:build windows` files may use `unsafe.Pointer`
  through `uintptr` per the win32 contract — keep it inside `*_windows.go`.
- **Host↔guest words**: kernel-cmdline flags are `savantos.*`; guest service
  names are `savantos-*`. Host and guest sides must change together.
- **Versioning**: Savant Versioning (`docs/SAVANT-VERSIONING.md`); bumping
  `currentVersion` requires regenerating `rsrc_windows_amd64.syso`
  (`versioninfo_test.go` enforces sync).
- **Secrets**: `.env*` gitignored; signing keys live outside the repo
  (`~/.savantos-keys/`); never print key material or tokens into logs.
- **Commits**: `type(scope): description` — atomic, one coherent change per
  commit; FID reference in the body when a FID drove the change.

## Docs

- [ECHO.md](ECHO.md) — the 15 Laws + Perfection Loop + FID lifecycle
- [ARCHITECTURE.md](ARCHITECTURE.md) — components, host↔guest contract, update trust chain, WHPX traps
- [protocol.config.yaml](protocol.config.yaml) — gates, paths, quality policy
- [coding-standards/go.md](coding-standards/go.md) — Go style rules
- [docs/SAVANT-VERSIONING.md](docs/SAVANT-VERSIONING.md) — version scheme
- [docs/FINDINGS.md](docs/FINDINGS.md) — technical history; read before touching QEMU/WHPX code
- [NOTICE.md](NOTICE.md) — lineage attribution (Apache-2.0 §4(d))