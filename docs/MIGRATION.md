# Moving a SavantOS setup to a real Omarchy install

SavantOS is disposable by design: deleting `%LOCALAPPDATA%\SavantOS` is
the uninstall. If the trial wins you over, `savantos-export` carries the
parts worth keeping to a bare-metal Omarchy install.

## Export inside Omarchy

Open a terminal (SUPER+RETURN) and run:

```bash
savantos-export
```

It writes `savantos-export-<date>.tar.gz` to the shared Windows folder when
SavantOS was started with `-share`, otherwise to your home folder. Pass a
directory to choose another place. The archive contains:

- `home/`: an allowlist of Omarchy, Hyprland, terminal, bar, notification,
  input, and other desktop configuration; `~/.local/share/omarchy`;
  `~/.local/bin`; and shell dotfiles (`.bashrc`, `.zshrc`, `.gitconfig`, and
  friends).
- `theme`: the name of the theme you had selected.
- `packages/repo.txt` and `packages/aur.txt`: packages you added on top of the
  factory image, split by where they come from.
- `restore.sh` and `manifest.json`.

Left out on purpose: unlisted application config, `~/.ssh`, `~/.gnupg`,
password managers, browser profiles, and caches. Those either may hold secrets
you should move yourself or are rebuilt on the new machine. The allowlist
avoids common credential files under `~/.config`, but the archive is still
your data. Review it before sharing it with anyone.

## Restore on the real install

Copy the archive over (USB stick, the shared folder, `scp` through the SSH
preset), then as the user who should receive the configuration:

```bash
tar -xzf savantos-export-<date>.tar.gz
cd savantos-export-<date>
./restore.sh
```

The script backs up anything it replaces under
`~/.savantos-restore-backup/<time>`, installs the repository packages with
pacman and the AUR packages with yay, and selects your theme. Log out and back
in afterwards so Hyprland and the shell pick up the restored configuration.

Packages that no longer exist, or themes you installed from a third-party
repository, are reported at the end rather than stopping the restore. Review
`packages/*.txt` if something is missing.
