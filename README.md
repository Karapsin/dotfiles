# Dotfiles Bootstrap

This repo is organized as GNU Stow packages and a small bootstrap flow for fresh Arch installs.

Managed Stow packages are listed in [`packages/stow.txt`](packages/stow.txt).

## Fresh Install

Run these from a newly installed Arch system:

```bash
sudo pacman -S --needed git
git clone /path/to/your/repo ~/dotfiles
cd ~/dotfiles
sudo ./bootstrap.sh --root --enable-networkmanager --with-lightdm
./bootstrap.sh --user
```

If you want unattended package installs:

```bash
sudo ./bootstrap.sh --root --noconfirm --enable-networkmanager --with-lightdm
./bootstrap.sh --user --noconfirm
```

## New User On An Existing Machine

Use the light user bootstrap when the machine already has the system packages,
services, and desktop baseline from `bootstrap-root.sh`, and you only want to
apply this repo for another local user:

```bash
git clone /path/to/your/repo ~/dotfiles
cd ~/dotfiles
./bootstrap.sh --user-light
```

It does not install pacman or AUR packages. Existing target files, such as a
fresh user's default `~/.bashrc`, are moved into
`~/.dotfiles-bootstrap-backup/<timestamp>/` before Stow runs.

For per-user system integration on the configured machine:

```bash
./bootstrap.sh --user-light --enable-linger --enable-login-wallpaper
```

## What The Scripts Do

`bootstrap.sh` dispatches to exactly one mode and forwards the remaining
arguments unchanged:
- `--root` runs `bootstrap-root.sh`
- `--user` runs `bootstrap-user.sh`
- `--user-light` runs `bootstrap-user-light.sh`

The direct scripts remain valid entrypoints for compatibility.

`bootstrap-root.sh`:
- installs official packages from [`packages/pacman.txt`](packages/pacman.txt)
- sets the X11 keyboard baseline to `us,ru` with `Win+Space`
- enables linger for the target user when possible
- optionally enables `NetworkManager`
- optionally installs LightDM packages from [`packages/pacman-lightdm.txt`](packages/pacman-lightdm.txt), the dark blue GTK greeter theme, and the wallpaper sync units

`bootstrap-user.sh`:
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- bootstraps `yay` if needed
- installs AUR packages from [`packages/aur.txt`](packages/aur.txt)
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer
- applies the custom XKB map immediately

`bootstrap-user-light.sh`:
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer when the user systemd manager is available
- optionally enables linger and the LightDM wallpaper sync timer for the user
- applies the custom XKB map immediately

## Secrets And Machine-Specific State

Do not put these in the repo:
- `~/.ssh`
- `~/.gnupg`
- `~/.config/gh/hosts.yml`
- browser profiles
- auth tokens, cookies, app sessions

Those should be restored separately after bootstrap.

## Adjusting The Package Set

Edit these manifests to match the machine you want to rebuild:
- [`packages/pacman.txt`](packages/pacman.txt)
- [`packages/pacman-lightdm.txt`](packages/pacman-lightdm.txt)
- [`packages/aur.txt`](packages/aur.txt)
- [`packages/stow.txt`](packages/stow.txt)

## Validation

Run the non-mutating validation script before committing bootstrap changes:

```bash
./scripts/check_dotfiles.sh
```
