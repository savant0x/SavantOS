#!/usr/bin/env python3
"""Host scripts / workflows sweep (FID-2026-0910-001).

Sweeps scripts/, .github/workflows/, and deletes nothing. Env-var family
TRYOMARCHY_* is SAVANTOS_ (matching the swept launcher). Repo URLs repoint
to savant0x/SavantOS. Upstream proper nouns (jorge-huxley builder, basecamp,
omarchy package names, WINQ-EMU) are shielded: they are external pins, not
our identity. vmtest harness paths (C:\\tryomarchy test dirs, host.lan shares)
are operator test-lab conventions, swept to savantos for consistency.

Order matters:
  1. CRED — trial-credential strings are OURS (the swept guest's patch 0005
     creates savant/savant; the smoke harness logs in with them and asserts
     the welcome marker). Scoped to smoke-guest.py; must run before tokens
     so the bare omarchy token cannot turn the login into savantos.
  2. SHIELD — upstream-owned forms (including [omarchy], the upstream pacman
     repo section smoke-guest greps for, and omarchy.qemu=1, upstream's own
     kernel word read by patches 0001/0039/0044).
  3. FIRST tokens — full owner/repo URLs before the bare try-omarchy tokens
     (a bare rename would leave tsouth89/SavantOS).
  4. TOKENS — identity renames, longest/most-specific first.
"""
import glob
import sys

SHIELD = [
    b"jorge-huxley/try-omarchy-win",
    b"basecamp/omarchy",
    b"pkgs.omarchy.org",
    b"omarchy-keyring",
    b"omarchy-nvim",
    b"omarchy-provision",
    b"omarchy-theme",
    b"omarchy-setup",
    b"omarchy-fcitx5",
    b"omarchy.desktop",
    b"omarchy-native-display-sync",
    b"omarchy-hyprland-toggle",
    b"LICENSE.omarchy",
    b"cmspam/winq-emu",
    b"omarchy-windows",  # vmtest container name — lab convention, keep
    b"usr/share/try-omarchy",
    b"usr/local/lib/try-omarchy",
    b"try-omarchy-guest-work",
    b"try-omarchy-guest-artifacts",
    b"omarchy.qemu=1",
    b"90-try-omarchy.conf",
    b"99-try-omarchy.conf",
    b"[omarchy]",  # upstream pacman repo section in /etc/pacman.conf
]
FIRST = [
    (b"omacom/try-omarchy-windows", b"savant0x/SavantOS"),
    (b"tsouth89/try-omarchy-windows", b"savant0x/SavantOS"),
    (b"omacom/omarchy-win", b"savant0x/SavantOS"),
    (b"secrets.UPDATE_SIGNING_KEY", b"secrets.SAVANTOS_UPDATE_SIGNING_KEY"),
]
TOKENS = [
    (b"TRYOMARCHY_", b"SAVANTOS_"),
    (b"TRYOMARCHY", b"SAVANTOS"),
    (b"TryOmarchy", b"SavantOS"),
    (b"Try Omarchy", b"SavantOS"),
    (b"try-omarchy-windows", b"SavantOS"),
    (b"try-omarchy-verifier", b"savantos-verifier"),
    (b"try-omarchy-public", b"savantos-public"),
    (b"try-omarchy-lock-refresh", b"savantos-lock-refresh"),
    (b"try-omarchy-guest-source", b"savantos-guest-source"),
    (b"launch-omarchy-gpu", b"launch-savantos-gpu"),
    (b"launch-omarchy", b"launch-savantos"),
    (b"start-omarchy", b"start-savantos"),
    (b"boot-omarchy-test", b"boot-savantos-test"),
    (b"try-omarchy-", b"savantos-"),
    (b"tryomarchy.", b"savantos."),
    (b"tryomarchy-", b"savantos-"),
    (b"tryomarchy", b"savantos"),
    (b"try-omarchy", b"savantos"),
    (b"omarchy-", b"savantos-"),  # after shield: only OUR savant-facing names remain
    (b"Omarchy", b"SavantOS"),
    (b"omarchy", b"savantos"),
    (b"OMARCHY", b"SAVANTOS"),
]
# Trial-credential contract with the swept guest (patch 0005): the smoke
# harness logs in as savant/savant and the welcome marker's middle field is
# the trial username. The \\n forms are literal backslash-n inside the
# smoke-guest.py source (its own bytes literals).
CRED = [
    (b"omarchy:instant-trial", b"savant:instant-trial"),
    (b"omarchy\\n", b"savant\\n"),
]
# Context lines inside release-notes-adjacent workflow text: keep branded prose out
FILES = (
    glob.glob("scripts/**/*.ps1", recursive=True)
    + glob.glob("scripts/**/*.sh", recursive=True)
    + glob.glob("scripts/**/*.py", recursive=True)
    + glob.glob("scripts/**/*.service", recursive=True)
    + glob.glob("scripts/**/*.md", recursive=True)
    + glob.glob(".github/workflows/*.yml")
)


def sweep(data, creds):
    if creds:
        for old, new in CRED:
            data = data.replace(old, new)
    # FIRST runs BEFORE the shield: the full owner/repo URLs contain the
    # shielded substring omarchy-windows (vmtest container name), which
    # would otherwise be marked and make the FIRST tokens unmatchable.
    for old, new in FIRST:
        data = data.replace(old, new)
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
        out = sweep(src, "smoke-guest" in path)
        if out != src:
            print(f"changed: {path}")
            if apply:
                with open(path, "wb") as f:
                    f.write(out)
    if not apply:
        print("dry run complete")


if __name__ == "__main__":
    main()
