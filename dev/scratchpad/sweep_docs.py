#!/usr/bin/env python3
"""Docs identity sweep (FID-2026-0910-001).

Docs are prose: bare "Omarchy" references to the guest's Omarchy-based desktop,
upstream tools (omarchy-update), and upstream paths are FACTS and stay, exactly
like guest-build/README.md. Only OUR product identity renames:

  - Try Omarchy / TryOmarchy (product, exe, data dir, example paths)
  - our Start-menu shortcut names (Start Omarchy -> Start SavantOS)
  - the launcher VM (the Omarchy VM / Shut down Omarchy -> SavantOS forms)
  - savantos-export tooling and its archive/backup naming
  - launch-omarchy*.ps1 (files renamed in the scripts commit)
  - savantos-reboot-notify unit name
  - "the Omacom candidate" -> "the release candidate" (release process is ours)

docs/FINDINGS.md gets a provenance banner afterwards; upstream facts inside it
(the try-omarchy build system, jorge-huxley builder) are shielded here.
docs/SAVANT-VERSIONING.md is excluded (its lineage line is intentional).
"""
import glob
import sys

SHIELD = [
    b"the try-omarchy build system",  # upstream builder provenance (FINDINGS)
    b"jorge-huxley/try-omarchy-win",  # upstream builder
]
TOKENS = [
    (b"Try Omarchy", b"SavantOS"),
    (b"TryOmarchy", b"SavantOS"),
    (b"try-omarchy-reboot-notify", b"savantos-reboot-notify"),
    (b"try-omarchy-export", b"savantos-export"),
    (b"omarchy-export-", b"savantos-export-"),
    (b".omarchy-restore-backup", b".savantos-restore-backup"),
    (b"launch-omarchy-gpu", b"launch-savantos-gpu"),
    (b"launch-omarchy", b"launch-savantos"),
    (b"Start Omarchy", b"Start SavantOS"),
    (b"Shut down Omarchy", b"Shut down SavantOS"),
    (b"the Omarchy VM", b"the SavantOS VM"),
    (b"the Omacom candidate", b"the release candidate"),
    (b"OmarchyRestored", b"SavantOSRestored"),
    (b"omarchy.zip", b"savantos.zip"),
]
FILES = (
    [p for p in glob.glob("docs/*.md") if not p.endswith("SAVANT-VERSIONING.md")]
    + ["runtime-build/README.md"]
)


def sweep(data):
    marks = [bytes([0, i]) for i in range(len(SHIELD))]
    for token, mark in zip(SHIELD, marks):
        data = data.replace(token, mark)
    for old, new in TOKENS:
        data = data.replace(old, new)
    for token, mark in zip(SHIELD, marks):
        data = data.replace(mark, token)
    return data


def main():
    apply = "--apply" in sys.argv
    for path in sorted(set(FILES)):
        with open(path, "rb") as f:
            src = f.read()
        out = sweep(src)
        if out != src:
            print(f"changed: {path}")
            if apply:
                with open(path, "wb") as f:
                    f.write(out)
    if not apply:
        print("dry run complete")


if __name__ == "__main__":
    main()
