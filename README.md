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

## Personal Bootstrap Values

Per-user bootstraps read local personal values from repo-root `.env`. That file
is ignored by Git. Copy [`.env.example`](.env.example) to `.env`, or let
`./bootstrap.sh --user` or `./bootstrap.sh --user-light` prompt for missing
values and create it.

The required values are:
- `DOTFILES_GIT_NAME`
- `DOTFILES_GIT_EMAIL`
- `DOTFILES_GTK_DOWNLOADS_DIR`
- `DOTFILES_GTK_PROJECTS_DIR`

After Stow runs, the user bootstraps generate marked local files at
`~/.gitconfig` and `~/.config/gtk-3.0/bookmarks` from those values. Existing
unmanaged files are backed up under `~/.dotfiles-bootstrap-backup/<timestamp>/`,
or rejected when `--no-backup` is set. `bootstrap-root.sh` does not read `.env`.

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
- installs the Chrome dark-blue theme policy
- optionally installs LightDM packages from [`packages/pacman-lightdm.txt`](packages/pacman-lightdm.txt), the dark blue GTK greeter theme, and the wallpaper sync units

`bootstrap-user.sh`:
- prompts for missing values in `.env`
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- generates local `~/.gitconfig` and GTK bookmarks from `.env`
- bootstraps `yay` if needed
- installs AUR packages from [`packages/aur.txt`](packages/aur.txt)
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer
- deploys the Chrome launcher and checks for the dark-blue theme policy
- applies the custom XKB map immediately

`bootstrap-user-light.sh`:
- prompts for missing values in `.env`
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- generates local `~/.gitconfig` and GTK bookmarks from `.env`
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer when the user systemd manager is available
- deploys the Chrome launcher and checks for the dark-blue theme policy
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

## Custom i3 Shortcuts

`$mod` is `Mod4`, usually the Super/Windows key. `$mod+Space` is reserved for
keyboard layout switching through the custom XKB setup.

### App Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+Enter` / `$mod+Keypad Enter` | Launch terminal (like Windows Terminal or Command Prompt) |
| `$mod+d` | Open Rofi application launcher (like Start menu search) |
| `$mod+Shift+/` | Open Rofi shortcut cheat sheet |
| `$mod+Shift+e` | Open Nemo file manager (like Windows File Explorer) |
| `$mod+n` | Open Mousepad (like Windows Notepad) |
| `$mod+Shift+s` | Start Flameshot screenshot selection (like Snipping Tool) |
| `Ctrl+Shift+l` | Lock the screen with Betterlockscreen |
| `$mod+c` | Launch Chrome through the dotfiles wrapper |
| `$mod+g` | Launch Steam |
| `$mod+t` | Launch Telegram |
| `$mod+Shift+v` | Toggle VPN control |
| `$mod+Alt+v` | Open PulseAudio volume control (like Volume Mixer) |
| `$mod+Alt+b` | Open Blueman manager (like Bluetooth settings) |
| `$mod+Shift+t` | Launch Element |
| `$mod+p` | Launch Positron (like an RStudio or VS Code-style data IDE) |
| `$mod+Shift+d` | Launch Drawing (like Windows Paint) |
| `$mod+Alt+r` | Launch RStudio |

### Polybar Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+Shift+c` | Open the Polybar calendar popup |
| `$mod+Shift+p` | Open the Polybar power menu |

### i3 Action Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+1` through `$mod+0` | Switch to workspace 1 through 10 |
| `$mod+Shift+1` through `$mod+Shift+0` | Move focused window to workspace 1 through 10 |
| `$mod+j/k/l/;` or `$mod+arrow keys` | Move focus left/down/up/right |
| `$mod+Shift+j/k/l/;` or `$mod+Shift+arrow keys` | Move the focused window left/down/up/right |
| `$mod+f` | Toggle fullscreen |
| `$mod+r` | Enter resize mode |
| resize mode: `j/k/l/;` or arrow keys | Resize the focused window |
| resize mode: `Enter`, `Escape`, or `$mod+r` | Return to normal mode |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Raise or lower volume by 5% |
| `XF86AudioMute` | Toggle audio mute |
| `$mod+Shift+r` | Restart i3 |
| `$mod+Shift+q` | Close the focused window |
| `$mod+h` / `$mod+v` | Split next container vertically or horizontally |
| `$mod+s` / `$mod+w` / `$mod+e` | Use stacking, tabbed, or split layout |
| `$mod+Shift+Space` | Toggle floating mode |
| `$mod+a` | Focus parent container |
