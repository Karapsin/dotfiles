#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bootstrap-user-light.sh [options]

Light per-user bootstrap for an already configured machine.

Options:
  --no-backup                 Fail on existing target files instead of backing them up.
  --skip-lfs                  Do not run git lfs pull.
  --skip-services             Do not enable user systemd services.
  --skip-xkb                  Do not apply the custom XKB map immediately.
  --enable-linger             Run sudo loginctl enable-linger for the current user.
  --enable-login-wallpaper    Enable the system wallpaper-login-copy timer for the current user.
  -h, --help                  Show this help.

This script does not install pacman or AUR packages.
EOF
}

if [[ ${EUID} -eq 0 ]]; then
  echo "Run as the target normal user: ./bootstrap-user-light.sh [options]" >&2
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STOW_FILE="$DOTFILES_DIR/packages/stow.txt"
TARGET_USER="$(id -un)"

# shellcheck source=scripts/bootstrap-user-lib.sh
source "$DOTFILES_DIR/scripts/bootstrap-user-lib.sh"
# shellcheck source=scripts/bootstrap-env.sh
source "$DOTFILES_DIR/scripts/bootstrap-env.sh"

BACKUP_EXISTING=1
SKIP_LFS=0
SKIP_SERVICES=0
SKIP_XKB=0
ENABLE_LINGER=0
ENABLE_LOGIN_WALLPAPER=0

while (($#)); do
  case "$1" in
    --no-backup)
      BACKUP_EXISTING=0
      ;;
    --skip-lfs)
      SKIP_LFS=1
      ;;
    --skip-services)
      SKIP_SERVICES=1
      ;;
    --skip-xkb)
      SKIP_XKB=1
      ;;
    --enable-linger)
      ENABLE_LINGER=1
      ;;
    --enable-login-wallpaper)
      ENABLE_LOGIN_WALLPAPER=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

mapfile -t STOW_PACKAGES < <(read_manifest "$STOW_FILE")

if [[ ${#STOW_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty stow manifest: $STOW_FILE" >&2
  exit 1
fi

require_command stow
ensure_dotfiles_env_values

if [[ $ENABLE_LINGER -eq 1 || $ENABLE_LOGIN_WALLPAPER -eq 1 ]]; then
  require_command sudo
fi

echo "[1/8] Preparing stow targets..."
BACKUP_DIR="$HOME/.dotfiles-bootstrap-backup/$(date +%Y%m%d-%H%M%S)"
backup_or_reject_conflicts "$BACKUP_DIR"
backup_or_reject_generated_targets "$BACKUP_DIR"

echo "[2/8] Pulling Git LFS assets (if available)..."
pull_lfs_assets

echo "[3/8] Deploying stow packages..."
cleanup_legacy_wallpaper_links
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"
prepare_wallpaper_state

echo "[4/8] Generating local personal and UI files..."
generate_dotfiles_personal_files "$BACKUP_DIR"

EXPECTED_EXECUTABLES=(
  "$HOME/.config/i3/auto-split.sh"
  "$HOME/.config/i3/blueman-launch.sh"
  "$HOME/.config/i3/blueman-placement-watch.sh"
  "$HOME/.config/i3/bluetooth-tray-fallback.sh"
  "$HOME/.config/i3/bluetooth-tray-left-click.sh"
  "$HOME/.config/i3/close-popups-on-outside-click.sh"
  "$HOME/.config/i3/focus-visual.py"
  "$HOME/.config/i3/launch-terminal.sh"
  "$HOME/.config/i3/launch-volume-control.sh"
  "$HOME/.config/i3/nemo-switch-pane.py"
  "$HOME/.config/i3/nemo-tab-pane-switch.sh"
  "$HOME/.config/i3/restart_monitors.sh"
  "$HOME/.config/i3/session-start.sh"
  "$HOME/.config/i3/shortcut-cheatsheet.sh"
  "$HOME/.config/i3/volume-tray-left-click.sh"
  "$HOME/.config/i3/vpn-control-toggle.sh"
  "$HOME/.config/dotfiles/update-ui.sh"
  "$HOME/.config/polybar/calendar.sh"
  "$HOME/.config/polybar/launch.sh"
  "$HOME/.local/bin/i3-terminal"
  "$HOME/.local/bin/drawing"
  "$HOME/.local/bin/google-chrome-dotfiles"
  "$HOME/.local/bin/load-xkb-shortcuts"
  "$HOME/.local/bin/positron"
  "$HOME/.local/bin/vim"
  "$HOME/.wallpapers/bin/update_betterlockscreen_cache.sh"
  "$HOME/.wallpapers/bin/wallpaper_cycle.py"
)

verify_expected_executables "${EXPECTED_EXECUTABLES[@]}" || exit 1

echo "[5/8] Configuring file dialogs and folder handling..."
configure_file_dialogs

echo "[6/8] Configuring Chrome theme..."
configure_chrome_theme

echo "[7/8] Enabling user services..."
if [[ $SKIP_SERVICES -eq 1 ]]; then
  echo "Skipping user systemd setup."
elif systemctl --user show-environment >/dev/null 2>&1; then
  enable_wallpaper_timer
else
  echo "Skipping user systemd setup: user manager is unavailable."
  echo "Run later: systemctl --user daemon-reload && systemctl --user enable wallpaper-cycle.timer && systemctl --user start wallpaper-cycle.timer"
fi

echo "[8/8] Applying the custom XKB map..."
if [[ $SKIP_XKB -eq 1 ]]; then
  echo "Skipping XKB apply."
elif [[ -x "$HOME/.local/bin/load-xkb-shortcuts" ]]; then
  "$HOME/.local/bin/load-xkb-shortcuts" || true
else
  echo "Skipping XKB apply: ~/.local/bin/load-xkb-shortcuts is unavailable."
fi

if [[ $ENABLE_LINGER -eq 1 ]]; then
  echo "Enabling linger for $TARGET_USER..."
  sudo loginctl enable-linger "$TARGET_USER"
fi

if [[ $ENABLE_LOGIN_WALLPAPER -eq 1 ]]; then
  if [[ -f /etc/systemd/system/wallpaper-login-copy@.timer ]]; then
    echo "Enabling login wallpaper timer for $TARGET_USER..."
    sudo systemctl enable --now "wallpaper-login-copy@${TARGET_USER}.timer"
    if [[ -f "$HOME/.wallpapers/current_wallpaper.png" ]]; then
      sudo systemctl start "wallpaper-login-copy@${TARGET_USER}.service"
    else
      echo "Skipping immediate login wallpaper sync: ~/.wallpapers/current_wallpaper.png is not installed yet."
    fi
  else
    echo "Skipping login wallpaper timer: /etc/systemd/system/wallpaper-login-copy@.timer is not installed." >&2
    echo "Run sudo ./bootstrap-root.sh --with-lightdm once on this machine if LightDM integration is desired." >&2
  fi
fi

echo
echo "Light user bootstrap complete."
echo "Optional root follow-up for new users:"
echo "  sudo loginctl enable-linger $TARGET_USER"
echo "  sudo systemctl enable --now wallpaper-login-copy@${TARGET_USER}.timer"
echo "Manual follow-up: restore secrets such as ~/.ssh, gh auth, browser profiles, and any app logins."
