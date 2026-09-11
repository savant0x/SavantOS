#!/usr/bin/env python3
"""Host identity sweep phase 2 — FID-2026-0910-001.

Completes the host sweep:
  1. fixes the phase-1 env-var mangle (TRYOMARCHY_* compounds fell through
     to the bare OMARCHY rule and became TRYSAVANTOS_*; the env family is
     SAVANTOS_*),
  2. fully sweeps the three files phase 1 skipped for manual URL review —
     the omacom repo URLs repoint at savant0x/SavantOS,
  3. rebrands the remaining bare product-name strings
     (Omarchy -> SavantOS, omarchy -> savantos).

Safety contract: token map runs longest-first, so URL and compound tokens
are consumed before any bare rule can mangle them (TRYOMARCHY before
OMARCHY — the former contains the latter). A pre-flight guard aborts on
tryomarchy.com (old product site, no agreed replacement — ask the
operator instead of guessing). A post-replacement guard aborts before
writing if any identity token or marchy substring would survive. In apply
mode the disk is re-scanned after writing to prove the writes landed.
app/manifest.go stays excluded (keys-commit territory).
"""
import sys
import glob

PREFLIGHT_ABORT = [b'tryomarchy.com']
TOKENS = [
    (b'TRYSAVANTOS_', b'SAVANTOS_'),
    (b'https://github.com/omacom/try-omarchy-windows/issues',
     b'https://github.com/savant0x/SavantOS/issues'),
    (b'https://github.com/omacom/try-omarchy-windows',
     b'https://github.com/savant0x/SavantOS'),
    (b'try-omarchy-reboot-notify', b'savantos-reboot-notify'),
    (b'try-omarchy', b'savantos'),
    (b'tryomarchy', b'savantos'),
    (b'TryOmarchy', b'SavantOS'),
    (b'Try Omarchy', b'SavantOS'),
    (b'TRYOMARCHY', b'SAVANTOS'),
    (b'OmarchyRestored', b'SavantOSRestored'),
    (b'Omarchy', b'SavantOS'),
    (b'omarchy', b'savantos'),
    (b'OMARCHY', b'SAVANTOS'),
]
EXCLUDE = {'app/manifest.go'}
FORBIDDEN_AFTER = [b'TryOmarchy', b'tryomarchy', b'try-omarchy', b'TRYOMARCHY',
                   b'Omarchy', b'omarchy', b'OMARCHY', b'marchy']


def sweep(apply):
    files = [p for p in glob.glob('app/**/*.go', recursive=True)
             if p.replace('\\', '/') not in EXCLUDE]
    for path in sorted(files):
        with open(path, 'rb') as f:
            src = f.read()
        for token in PREFLIGHT_ABORT:
            if token in src:
                print(f'ABORT: {token.decode()} in {path} has no agreed replacement')
                sys.exit(1)
    changed = 0
    swept = {}
    for path in sorted(files):
        with open(path, 'rb') as f:
            src = f.read()
        out = src
        notes = []
        for old, new in TOKENS:
            n = out.count(old)
            if n:
                out = out.replace(old, new)
                notes.append(f'    {old.decode()} -> {new.decode()} x{n}')
        for token in FORBIDDEN_AFTER:
            if token in out:
                print(f'ABORT: {token.decode()!r} would survive the sweep in {path}')
                sys.exit(1)
        if out != src:
            changed += 1
            print(f'{path}:')
            for note in notes:
                print(note)
            swept[path] = out
            if apply:
                with open(path, 'wb') as f:
                    f.write(out)
    print(f'\nfiles changed: {changed}')
    for path, content in swept.items():
        for i, line in enumerate(content.splitlines(), 1):
            if b'marchy' in line.lower():
                print(f'LEFTOVER {path}:{i}: {line.strip()[:110]!r}')
                sys.exit(1)
    if apply:
        for path in sorted(files):
            with open(path, 'rb') as f:
                if b'marchy' in f.read().lower():
                    print(f'ABORT: marchy still on disk in {path}')
                    sys.exit(1)
        print('verified: zero marchy tokens remain in app/')
    else:
        print('dry-run clean: sweep would leave zero marchy tokens in app/')


if __name__ == '__main__':
    sweep('--apply' in sys.argv)