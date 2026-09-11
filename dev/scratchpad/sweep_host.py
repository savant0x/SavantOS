#!/usr/bin/env python3
"""Host identity sweep for FID-2026-0910-001 — app/ Go sources only.

Token map follows the FID's sweep order-safety section, longest-first so
compounds consume before fragments. app/manifest.go is EXCLUDED: its
trust-anchor pins (release URL, digest, embed) are repointed in the keys
commit, not the identity sweep. Files flagged MANUAL (tryomarchy.com,
try-omarchy-windows leftovers) are listed and skipped entirely so nothing
is silently mistranslated. Bytes mode throughout — no newline churn.
"""
import sys
import glob

TOKENS = [
    (b'TRYOMARCHY_SHORTCUT', b'SAVANTOS_SHORTCUT'),
    (b'launch-omarchy-gpu', b'launch-savantos-gpu'),
    (b'launch-omarchy', b'launch-savantos'),
    (b'start-omarchy', b'start-savantos'),
    (b'boot-omarchy-test', b'boot-savantos-test'),
    (b'try-omarchy-reboot-notify', b'savantos-reboot-notify'),
    (b'try-omarchy-export', b'savantos-export'),
    (b'try-omarchy', b'savantos'),
    (b'tryomarchy.', b'savantos.'),
    (b'Run Omarchy', b'Run SavantOS'),
    (b'Try Omarchy', b'SavantOS'),
    (b'TryOmarchy', b'SavantOS'),
    (b'tryomarchy', b'savantos'),
    (b'OMARCHY', b'SAVANTOS'),
    (b'Trial account: omarchy', b'Trial account: savant'),
    (b'Password: omarchy', b'Password: savant'),
    (b'omarchy / omarchy', b'savant / savant'),
]

MANUAL_FLAGS = [b'tryomarchy.com', b'try-omarchy-windows']
EXCLUDE = {'app/manifest.go'}


def sweep(apply):
    files = [p for p in glob.glob('app/**/*.go', recursive=True)
             if p.replace('\\', '/') not in EXCLUDE]
    changed = 0
    leftovers = []
    for path in sorted(files):
        with open(path, 'rb') as f:
            src = f.read()
        manual = [flag for flag in MANUAL_FLAGS if flag in src]
        if manual:
            for i, line in enumerate(src.splitlines(), 1):
                for flag in manual:
                    if flag in line:
                        print(f'MANUAL {path}:{i}: {line.strip()[:100]!r}')
            continue
        out = src
        notes = []
        for old, new in TOKENS:
            n = out.count(old)
            if n:
                out = out.replace(old, new)
                notes.append(f'    {old.decode()} -> {new.decode()} x{n}')
        if out != src:
            changed += 1
            print(f'{path}:')
            for note in notes:
                print(note)
            for i, line in enumerate(out.splitlines(), 1):
                if b'marchy' in line.lower():
                    leftovers.append(f'{path}:{i}: {line.strip()[:100]!r}')
            if apply:
                with open(path, 'wb') as f:
                    f.write(out)
    print(f'\nfiles changed: {changed}')
    if leftovers:
        print('REMAINING omarchy-mention lines (decide each):')
        for line in leftovers:
            print(f'  {line}')
    else:
        print('no omarchy mentions remain in swept files')


if __name__ == '__main__':
    sweep('--apply' in sys.argv)