#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bootstrap-user.sh [options]

Full per-user bootstrap. Run this after bootstrap-root.sh on a fresh install.

Options:
  --noconfirm       Pass --noconfirm to yay when installing AUR packages.
  --skip-aur        Do not install AUR packages.
  --no-backup       Fail on existing target files instead of backing them up.
  --skip-lfs        Do not run git lfs pull.
  --skip-services   Do not enable user systemd services.
  --skip-xkb        Do not apply the custom XKB map immediately.
  -h, --help        Show this help.
EOF
}

if [[ ${EUID} -eq 0 ]]; then
  echo "Run as your normal user: ./bootstrap-user.sh [options]" >&2
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUR_FILE="$DOTFILES_DIR/packages/aur.txt"
STOW_FILE="$DOTFILES_DIR/packages/stow.txt"

# shellcheck source=scripts/bootstrap-user-lib.sh
source "$DOTFILES_DIR/scripts/bootstrap-user-lib.sh"
# shellcheck source=scripts/bootstrap-env.sh
source "$DOTFILES_DIR/scripts/bootstrap-env.sh"

NO_CONFIRM=0
SKIP_AUR=0
BACKUP_EXISTING=1
SKIP_LFS=0
SKIP_SERVICES=0
SKIP_XKB=0

while (($#)); do
  case "$1" in
    --noconfirm)
      NO_CONFIRM=1
      ;;
    --skip-aur)
      SKIP_AUR=1
      ;;
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
mapfile -t AUR_PACKAGES < <(read_manifest "$AUR_FILE")

if [[ ${#STOW_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty stow manifest: $STOW_FILE" >&2
  exit 1
fi

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  echo "Bootstrapping yay..."
  retry_git_clone 5 10 "Cloning yay from AUR" \
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  pushd "$tmpdir/yay" >/dev/null
  MAKEPKG_ARGS=(-si --needed)
  if [[ $NO_CONFIRM -eq 1 ]]; then
    MAKEPKG_ARGS+=(--noconfirm)
  fi
  retry_command 5 10 "Building and installing yay" makepkg "${MAKEPKG_ARGS[@]}"
  popd >/dev/null
  trap - RETURN
  rm -rf "$tmpdir"
}

require_command stow
ensure_dotfiles_env_values

echo "[1/10] Preparing stow targets..."
BACKUP_DIR="$HOME/.dotfiles-bootstrap-backup/$(date +%Y%m%d-%H%M%S)"
cleanup_legacy_wallpaper_links
backup_or_reject_conflicts "$BACKUP_DIR"
backup_or_reject_generated_targets "$BACKUP_DIR"

echo "[2/10] Pulling Git LFS assets (if available)..."
pull_lfs_assets

echo "[3/10] Deploying stow packages..."
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"
prepare_wallpaper_state

echo "[4/10] Generating local personal and UI files..."
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

if [[ $SKIP_AUR -eq 0 && ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  echo "[5/10] Installing AUR packages..."
  ensure_yay
  YAY_ARGS=(-S --needed)
  if [[ $NO_CONFIRM -eq 1 ]]; then
    YAY_ARGS+=(--noconfirm)
  fi
  retry_command 5 10 "Installing AUR packages" yay "${YAY_ARGS[@]}" "${AUR_PACKAGES[@]}"
else
  echo "[5/10] Skipping AUR packages."
fi

echo "[6/10] Installing VPN Control..."
install_vpn_control

echo "[7/10] Configuring file dialogs and folder handling..."
configure_file_dialogs

echo "[8/10] Configuring Chrome theme..."
configure_chrome_theme

echo "[9/10] Enabling user services..."
if [[ $SKIP_SERVICES -eq 1 ]]; then
  echo "Skipping user systemd setup."
elif systemctl --user show-environment >/dev/null 2>&1; then
  enable_wallpaper_timer
else
  echo "Skipping user systemd setup: user manager is unavailable."
  echo "Run later: systemctl --user daemon-reload && systemctl --user enable wallpaper-cycle.timer && systemctl --user start wallpaper-cycle.timer"
fi

echo "[10/10] Applying the custom XKB map..."
if [[ $SKIP_XKB -eq 1 ]]; then
  echo "Skipping XKB apply."
elif [[ -x "$HOME/.local/bin/load-xkb-shortcuts" ]]; then
  "$HOME/.local/bin/load-xkb-shortcuts" || true
else
  echo "Skipping XKB apply: ~/.local/bin/load-xkb-shortcuts is unavailable."
fi

echo
echo "User bootstrap complete."
echo "Manual follow-up: restore secrets such as ~/.ssh, gh auth, browser profiles, and any app logins."
