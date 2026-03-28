# Dotfiles Bootstrap

This repo is organized as GNU Stow packages and a small bootstrap flow for fresh Arch installs.

Managed packages currently used for the desktop:
- `home`
- `i3`
- `polybar`
- `wallpapers`
- `xkb`

## Fresh Install

Run these from a newly installed Arch system:

```bash
sudo pacman -S --needed git
git clone /path/to/your/repo ~/dotfiles
cd ~/dotfiles
sudo ./bootstrap-root.sh --enable-networkmanager --with-lightdm
./bootstrap-user.sh
```

If you want unattended package installs:

```bash
sudo ./bootstrap-root.sh --noconfirm --enable-networkmanager --with-lightdm
./bootstrap-user.sh --noconfirm
```

## What The Scripts Do

`bootstrap-root.sh`:
- installs official packages from [`packages/pacman.txt`](packages/pacman.txt)
- sets the X11 keyboard baseline to `us,ru` with `Alt+Shift`
- enables linger for the target user when possible
- optionally enables `NetworkManager`
- optionally installs the LightDM wallpaper sync units

`bootstrap-user.sh`:
- pulls Git LFS assets when `git-lfs` is installed
- stows `home`, `i3`, `polybar`, `wallpapers`, and `xkb`
- bootstraps `yay` if needed
- installs AUR packages from [`packages/aur.txt`](packages/aur.txt)
- enables the wallpaper timer
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
- [`packages/aur.txt`](packages/aur.txt)
