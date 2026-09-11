#!/usr/bin/env python3
"""Guest-patch identity sweep (FID-2026-0910-001).

Uniform byte sweep over ALL line classes (context lines of later patches
quote our added content, so scoping to '+' lines would desync the series).

Order matters:
  1. CRED_0005 (trial creds are ours; bare-omarchy shield would eat them)
  2. PATH_SHIELD — upstream-owned paths/artifacts that CONTAIN try-omarchy;
     shielded first so our try-omarchy tokens cannot touch them (git am must
     keep applying against the pinned jorge-huxley builder tree)
  3. TOKENS — our identity renames, longest/most-specific first
     (try-omarchy-export before omarchy-export, so the tool name does not
     mangle into try-savantos-export)
  4. BARE_SHIELD — remaining bare omarchy/Omarchy/OMARCHY are upstream-owned
     (package names, OMARCHY_* env, "real Omarchy install", omarchy.qemu=1,
     Omarchy version pins); shielded and passed through byte-exact
"""
import glob
import sys

PATH_SHIELD = [
    b"usr/share/try-omarchy",
    b"usr/local/lib/try-omarchy",
    b"90-try-omarchy.conf",
    b"99-try-omarchy.conf",
    b"try-omarchy-guest-work",
    b"try-omarchy-guest-artifacts",
]
BARE_SHIELD = [
    b"omarchy",
    b"Omarchy",
    b"OMARCHY",
]
TOKENS = [
    # Upstream issue reference in 0033's commit message: provenance kept,
    # identity-neutral wording.
    (b"omacom/try-omarchy-windows#32", b"upstream issue 32"),
    (b"Try Omarchy Release", b"SavantOS Release"),
    (b"TRYOMARCHY", b"SAVANTOS"),
    (b"TryOmarchy", b"SavantOS"),
    (b"Try Omarchy", b"SavantOS"),
    (b"TRY_OMARCHY_", b"TRY_SAVANTOS_"),
    (b"try-omarchy-reboot-notify", b"savantos-reboot-notify"),
    (b"try-omarchy-export", b"savantos-export"),
    (b"omarchy-export", b"savantos-export"),
    (b".omarchy-restore-backup", b".savantos-restore-backup"),
    (b"try-omarchy-", b"savantos-"),
    (b"tryomarchy.", b"savantos."),
    (b"tryomarchy-", b"savantos-"),
    (b"tryomarchy", b"savantos"),
    (b"try-omarchy", b"savantos"),
]
CRED_0005 = [
    (b'username=omarchy', b'username=savant'),
    (b'"$username" omarchy | chpasswd', b'"$username" savant | chpasswd'),
    (b"omarchy    Password: omarchy", b"savant    Password: savant"),
    (b"Trial login: omarchy", b"Trial login: savant"),
]


def sweep(data, creds):
    # Credentials first: bare omarchy is shielded below, and the trial
    # username/password are ours (patch 0005 + host provision_mode.go).
    if creds:
        for old, new in CRED_0005:
            data = data.replace(old, new)
    # Upstream paths that embed try-omarchy must survive our tokens below.
    path_marks = [bytes([0, i]) for i in range(len(PATH_SHIELD))]
    for token, mark in zip(PATH_SHIELD, path_marks):
        data = data.replace(token, mark)
    # Our identity renames (unshielded text only).
    for old, new in TOKENS:
        data = data.replace(old, new)
    # Everything still containing bare omarchy is upstream-owned: pass
    # through byte-exact so git am keeps applying.
    bare_marks = [bytes([0, 100 + i]) for i in range(len(BARE_SHIELD))]
    for token, mark in zip(BARE_SHIELD, bare_marks):
        data = data.replace(token, mark)
    for token, mark in reversed(list(zip(BARE_SHIELD, bare_marks))):
        data = data.replace(mark, token)
    for token, mark in reversed(list(zip(PATH_SHIELD, path_marks))):
        data = data.replace(mark, token)
    return data


def main():
    apply = "--apply" in sys.argv
    for path in sorted(glob.glob("guest-build/*.patch")):
        with open(path, "rb") as f:
            src = f.read()
        out = sweep(src, "0005-" in path)
        if out != src:
            print(f"changed: {path}")
            if apply:
                with open(path, "wb") as f:
                    f.write(out)
    if not apply:
        print("dry run complete")


if __name__ == "__main__":
    main()
