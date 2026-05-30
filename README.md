# Dotfiles Bootstrap

This repo is organized as GNU Stow packages and a small bootstrap flow for fresh Arch installs.

Managed Stow packages are listed in [`packages/stow.txt`](packages/stow.txt).

## Fresh Install

Run these from a newly installed Arch system:

```bash
sudo pacman -S --needed git
git clone /path/to/your/repo ~/dotfiles
cd ~/dotfiles
sudo ./bootstrap.sh --root --enable-networkmanager --with-lightdm --enable-multilib --vulkan-provider auto
./bootstrap.sh --user
```

If you want unattended package installs:

```bash
sudo ./bootstrap.sh --root --noconfirm --enable-networkmanager --with-lightdm --enable-multilib --vulkan-provider auto
./bootstrap.sh --user --noconfirm
```

For a QEMU/libvirt VM, use `--vulkan-provider virtio`. On real hardware, use
`auto`, `nvidia`, `intel`, `amd`, `swrast`, or `none` when you want pacman to
choose from already-installed providers.

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

## Guest User Sync

To keep the local `guest` account on the same managed dotfiles, run:

```bash
sudo ./bootstrap.sh --guest
```

That wrapper runs the light user bootstrap as `guest`, writes guest-local
bootstrap values at `/home/guest/.dotfiles-bootstrap.env`, stows the
packages from [`packages/stow.txt`](packages/stow.txt), and regenerates the
guest UI files. Stowed files remain symlinked into this checkout, so tracked
dotfile edits are shared with the guest account after the first sync. Generated
files and app settings should be refreshed by rerunning the guest sync after
changing shared sizing or bootstrap-managed defaults.

Optional root integration for the guest account:

```bash
sudo ./bootstrap.sh --guest --enable-linger --enable-login-wallpaper
```

For a different local account, pass `--target-user USER`. Guest Git identity
and GTK bookmark paths can be overridden with `--git-name`, `--git-email`,
`--downloads-dir`, and `--projects-dir`.

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
`~/.gitconfig` and `~/.config/gtk-3.0/bookmarks` from those values. They also
render marked UI config files such as GTK CSS, `.Xresources`, Rofi, Dunst,
Alacritty, Picom, and Betterlockscreen from the shared sizing config described
below. Existing
unmanaged files are backed up under `~/.dotfiles-bootstrap-backup/<timestamp>/`,
or rejected when `--no-backup` is set. `bootstrap-root.sh` does not read `.env`.

## UI Size Configuration

Shared UI sizes live in
[`home/.config/dotfiles/ui-sizes.env`](home/.config/dotfiles/ui-sizes.env),
which Stow deploys to `~/.config/dotfiles/ui-sizes.env`. Use that file as the
single entry point for popup geometry, Polybar sizing, Rofi/Dunst/terminal
dimensions, i3 font/resize sizing, GTK CSS dimensions, lock screen geometry,
Drawing wrapper controls, and bootstrap-managed app window defaults.

The values in `ui-sizes.env` are the tuned base values for a `2560x1398`
workspace. During bootstrap, login/session startup, or `update-ui.sh`, the
helpers detect the active workspace size from i3, then `xrandr`, then fall back
to the base size. They resolve concrete app sizes with an area scale:

```text
scale = sqrt((current_width * current_height) / (base_width * base_height))
```

`DOTFILES_UI_SCALE_MIN_PERCENT` and `DOTFILES_UI_SCALE_MAX_PERCENT` clamp that
scale; the defaults are `75` and `180`.

After editing `~/.config/dotfiles/ui-sizes.env`, run:

```bash
~/.config/dotfiles/update-ui.sh
```

Run the same command after moving to a different screen size to re-resolve the
generated values. It regenerates static UI files, merges `.Xresources`, and
refreshes i3, Polybar, Dunst, and Picom. Already-open GTK, Rofi, and Alacritty
windows may still need to be relaunched to pick up regenerated files.

The same scale controls these visible areas:
- i3 font and resize step, shared popup edge and bottom gaps
- PulseAudio and Blueman popup dimensions and tray icon filter thresholds
- Polybar bar, tray, fonts, workspace label padding, keyboard indicator density, and title truncation
- Rofi launcher theme, shortcut cheat sheet, powermenu geometry, and powermenu internal spacing
- Dunst notification dimensions, icon/progress geometry, padding, frame, radius, and font
- GTK 3/4 generated CSS, gsimplecal/custom calendar CSS, and Polybar calendar popup sizing
- Alacritty padding/font, Picom shadow/corner dimensions, Mousepad window/tab defaults, Betterlockscreen/i3lock text and ring geometry, Drawing overlay/tool panel/dialog sizing
- root-managed LightDM greeter font, panel height, card/control spacing, borders, radii, shadows, and avatar padding

Root-managed LightDM files are rendered by `bootstrap-root.sh --with-lightdm`
or `sudo ./scripts/render-root-ui.sh`. They are not rewritten by
`~/.config/dotfiles/update-ui.sh`.

Intentionally fixed values include colors, transparency, animation and timeout
durations, semantic percentages, zero/no-op dimensions, workspace numbers,
keyboard shortcuts, date/time formats, image/content geometry, Drawing angle
values, and the two-column Drawing tool layout.

## What The Scripts Do

`bootstrap.sh` dispatches to exactly one mode and forwards the remaining
arguments unchanged:
- `--root` runs `bootstrap-root.sh`
- `--user` runs `bootstrap-user.sh`
- `--user-light` runs `bootstrap-user-light.sh`
- `--guest` runs `sync-guest-user.sh`

The direct scripts remain valid entrypoints for compatibility.

`bootstrap-root.sh`:
- installs official packages from [`packages/pacman.txt`](packages/pacman.txt)
- optionally enables the Arch `[multilib]` repository for Steam
- installs an explicit Vulkan provider to avoid pacman provider prompts
- sets the X11 keyboard baseline to `us,ru` with `Win+Space`
- enables linger for the target user when possible
- optionally enables `NetworkManager`
- enables Bluetooth service for Blueman when Bluetooth hardware is available
- installs the Chrome dark-blue theme policy
- optionally installs and enables LightDM packages from [`packages/pacman-lightdm.txt`](packages/pacman-lightdm.txt), the dark blue GTK greeter theme, and the wallpaper sync units
- renders LightDM greeter sizing from [`home/.config/dotfiles/ui-sizes.env`](home/.config/dotfiles/ui-sizes.env)

`bootstrap-user.sh`:
- prompts for missing values in `.env`
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- generates local personal files and UI config files
- bootstraps `yay` if needed
- installs AUR packages from [`packages/aur.txt`](packages/aur.txt)
- installs VPN Control from the latest `main` branch of `https://github.com/karapsin/vpn_control_android`
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer
- deploys the Chrome launcher and checks for the dark-blue theme policy
- applies the custom XKB map immediately

`bootstrap-user-light.sh`:
- prompts for missing values in `.env`
- backs up unmanaged target files that would conflict with Stow links
- pulls Git LFS assets when `git-lfs` is installed
- stows packages from [`packages/stow.txt`](packages/stow.txt)
- generates local personal files and UI config files
- verifies executable bits for scripts used by the desktop config
- enables the wallpaper timer when the user systemd manager is available
- deploys the Chrome launcher and checks for the dark-blue theme policy
- optionally enables linger and the LightDM wallpaper sync timer for the user
- applies the custom XKB map immediately

`sync-guest-user.sh`:
- runs the light user bootstrap as the configured guest account
- writes guest-safe bootstrap values under the target user's home directory
- skips Git LFS fetches and immediate XKB application by default
- applies graphical app defaults through a temporary D-Bus session when available
- optionally enables linger and the LightDM wallpaper sync timer for the guest account

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
The `$mod+Shift+/` cheat sheet uses the same grouping order as the tables below.

### App Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+Enter` / `$mod+Keypad Enter` | Launch Alacritty terminal (like Windows Terminal or Command Prompt) |
| `$mod+d` | Open Rofi application launcher (like Start menu search) |
| `$mod+Shift+/` | Open Rofi shortcut cheat sheet |
| `$mod+Shift+e` | Open Nemo file manager (like Windows File Explorer) |
| `$mod+n` | Open Mousepad (like Windows Notepad) |
| `$mod+Shift+s` | Start Flameshot screenshot selection (like Snipping Tool) |
| `Print Screen` | Copy a full desktop screenshot to the clipboard with Flameshot |
| `$mod+Shift+o` | Launch OBS Studio for screen recording |
| `Ctrl+Shift+l` | Lock the screen with Betterlockscreen |
| `$mod+c` | Launch Chrome through the dotfiles wrapper |
| `$mod+g` | Launch Steam |
| `$mod+t` | Launch Telegram |
| `$mod+Shift+v` | Toggle VPN control |
| `$mod+Alt+v` | Open PulseAudio volume control above Polybar (like Volume Mixer) |
| `$mod+Alt+b` | Open Blueman manager above Polybar; Bluetooth tray left-click toggles the same popup (like Bluetooth settings) |
| `$mod+Shift+t` | Launch Element |
| `$mod+p` | Launch Positron through the dotfiles wrapper (like an RStudio or VS Code-style data IDE) |
| `$mod+Shift+d` | Launch Drawing (like Windows Paint) |
| `$mod+Alt+r` | Launch RStudio |

### Polybar Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+Shift+c` | Open the Polybar calendar popup |
| `$mod+Shift+p` | Open the Polybar power menu above Polybar |

### i3 Action Shortcuts

| Shortcut | Action |
| --- | --- |
| `$mod+1` through `$mod+0` | Switch to workspace 1 through 10 |
| `$mod+Shift+1` through `$mod+Shift+0` | Move focused window to workspace 1 through 10 |
| `$mod+h/j/k/l` or `$mod+arrow keys` | Move focus left/down/up/right |
| `$mod+Shift+h/j/k/l` or `$mod+Shift+arrow keys` | Swap the focused window left/down/up/right |
| `$mod+f` | Toggle fullscreen |
| `$mod+r` | Enter resize mode |
| resize mode: `j/k/l/;` or arrow keys | Resize the focused window |
| resize mode: `Enter`, `Escape`, or `$mod+r` | Return to normal mode |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Raise or lower volume by 5% |
| `XF86AudioMute` | Toggle audio mute |
| `$mod+Shift+r` | Restart i3 |
| `$mod+Shift+q` | Close the focused window |
| `$mod+b` / `$mod+v` | Split next container vertically or horizontally |
| `$mod+s` / `$mod+w` / `$mod+e` | Use stacking, tabbed, or split layout |
| `$mod+Shift+f` | Toggle floating mode for the focused window |
| `$mod+Alt+a` | Toggle automatic tiling |
| `$mod+a` | Focus parent container |
