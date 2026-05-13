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

read_manifest() {
  local file=$1
  [[ -f "$file" ]] || return 0
  sed -E 's/[[:space:]]+#.*$//; s/#.*$//; /^[[:space:]]*$/d' "$file"
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

is_git_worktree() {
  git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

pull_lfs_assets() {
  if [[ $SKIP_LFS -eq 1 ]]; then
    echo "Skipping Git LFS pull."
  elif ! command -v git >/dev/null 2>&1; then
    echo "Skipping Git LFS pull: git is unavailable."
  elif ! is_git_worktree; then
    echo "Skipping Git LFS pull: $DOTFILES_DIR is not a Git repository."
  elif command -v git-lfs >/dev/null 2>&1; then
    git -C "$DOTFILES_DIR" lfs pull || true
  else
    echo "Skipping Git LFS pull: git-lfs is unavailable."
  fi
}

ensure_executable() {
  local executable=$1

  if [[ -x "$executable" ]]; then
    return 0
  fi

  if [[ ! -e "$executable" ]]; then
    echo "Expected script missing after stow: $executable" >&2
    return 1
  fi

  if chmod +x "$executable" 2>/dev/null; then
    return 0
  fi

  echo "Expected script is not executable and could not be fixed: $executable" >&2
  echo "The Stow target may point into a dotfiles checkout owned by another user." >&2
  return 1
}

copy_link_target_locally() {
  local path=$1
  local source

  [[ -L "$path" ]] || return 0

  source="$(readlink -f -- "$path" 2>/dev/null || true)"
  rm -f -- "$path"

  if [[ -n "$source" && -f "$source" ]]; then
    cp -- "$source" "$path"
  fi
}

prepare_wallpaper_state() {
  local current="$HOME/.wallpapers/current_wallpaper.png"
  local state_file="$HOME/.wallpapers/state/state.json"
  local current_source="$DOTFILES_DIR/wallpapers/.wallpapers/current_wallpaper.png"
  local state_source="$DOTFILES_DIR/wallpapers/.wallpapers/state/state.json"

  mkdir -p -- "$HOME/.wallpapers/state"
  copy_link_target_locally "$current"
  copy_link_target_locally "$state_file"

  if [[ ! -e "$current" && -f "$current_source" ]]; then
    cp -- "$current_source" "$current"
  fi
  if [[ ! -e "$state_file" ]]; then
    if [[ -f "$state_source" ]]; then
      cp -- "$state_source" "$state_file"
    else
      printf '{}\n' > "$state_file"
    fi
  fi
}

enable_wallpaper_timer() {
  local wants_dir="$HOME/.config/systemd/user/timers.target.wants"
  local wants_link="$wants_dir/wallpaper-cycle.timer"

  if [[ -L "$wants_dir" && ! -e "$wants_dir" ]]; then
    echo "Removing stale user timer directory link: $wants_dir"
    rm -f -- "$wants_dir"
  fi
  if [[ -L "$wants_link" && ! -e "$wants_link" ]]; then
    echo "Removing stale user timer link: $wants_link"
    rm -f -- "$wants_link"
  fi

  mkdir -p -- "$wants_dir"
  systemctl --user daemon-reload
  systemctl --user enable wallpaper-cycle.timer
  systemctl --user start wallpaper-cycle.timer
  systemctl --user start wallpaper-cycle.service || true
}

configure_file_dialogs() {
  local mime_file="$HOME/.config/mimeapps.list"
  local gtk_theme="adw-gtk3-dark"

  if command -v xdg-mime >/dev/null 2>&1; then
    if [[ ! -f "$mime_file" ]] || ! grep -Eq '^[[:space:]]*inode/directory=nemo\.desktop([;[:space:]]|$)' "$mime_file"; then
      xdg-mime default nemo.desktop inode/directory || true
    fi
  else
    echo "Skipping directory MIME default: xdg-mime is unavailable."
  fi

  if command -v gio >/dev/null 2>&1 && ! gio mime inode/directory 2>/dev/null | grep -q 'nemo\.desktop'; then
    gio mime inode/directory nemo.desktop >/dev/null 2>&1 || true
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark >/dev/null 2>&1 || true
    gsettings set org.cinnamon.desktop.interface gtk-theme "$gtk_theme" >/dev/null 2>&1 || true
    gsettings set org.nemo.preferences start-with-dual-pane true >/dev/null 2>&1 || true
    gsettings set org.nemo.preferences default-folder-viewer list-view >/dev/null 2>&1 || true
    gsettings set org.nemo.window-state start-with-sidebar false >/dev/null 2>&1 || true
    gsettings set org.nemo.list-view default-visible-columns "['name', 'size', 'type', 'date_modified']" >/dev/null 2>&1 || true
    gsettings set org.nemo.list-view default-column-order "['name', 'size', 'type', 'date_modified']" >/dev/null 2>&1 || true
    gsettings set org.nemo.list-view default-zoom-level smaller >/dev/null 2>&1 || true
  fi

  if [[ $SKIP_SERVICES -eq 1 ]]; then
    echo "Skipping portal restart."
  elif systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk >/dev/null 2>&1 || true
  else
    echo "Skipping portal restart: user manager is unavailable."
  fi
}

is_managed_target() {
  local target=$1
  local source=$2
  local resolved_target
  local resolved_source

  resolved_target="$(readlink -f -- "$target" 2>/dev/null || true)"
  resolved_source="$(readlink -f -- "$source" 2>/dev/null || true)"

  [[ -n "$resolved_target" && -n "$resolved_source" && "$resolved_target" == "$resolved_source" ]]
}

backup_or_reject_conflicts() {
  local backup_dir=$1
  local conflict_found=0
  local moved_any=0
  local package

  for package in "${STOW_PACKAGES[@]}"; do
    local package_dir="$DOTFILES_DIR/$package"

    if [[ ! -d "$package_dir" ]]; then
      echo "Missing stow package directory: $package_dir" >&2
      exit 1
    fi

    while IFS= read -r -d '' source_path; do
      local rel_path="${source_path#"$package_dir"/}"
      local target_path="$HOME/$rel_path"
      local backup_path="$backup_dir/$rel_path"
      local backup_parent

      case "$rel_path" in
        .wallpapers/current_wallpaper.png|.wallpapers/state/state.json)
          continue
          ;;
      esac

      [[ -e "$target_path" || -L "$target_path" ]] || continue
      is_managed_target "$target_path" "$source_path" && continue

      if [[ $BACKUP_EXISTING -eq 0 ]]; then
        echo "Existing unmanaged target would conflict: $target_path" >&2
        conflict_found=1
        continue
      fi

      backup_parent="$(dirname -- "$backup_path")"
      mkdir -p "$backup_parent"
      echo "Backing up existing target: $target_path -> $backup_path"
      mv -- "$target_path" "$backup_path"
      moved_any=1
    done < <(find "$package_dir" \( -type f -o -type l \) -print0)
  done

  if [[ $conflict_found -ne 0 ]]; then
    echo "Rerun without --no-backup to move conflicts into ~/.dotfiles-bootstrap-backup/." >&2
    exit 1
  fi

  if [[ $moved_any -eq 0 && -d "$backup_dir" ]]; then
    rmdir "$backup_dir" 2>/dev/null || true
  elif [[ $moved_any -eq 1 ]]; then
    echo "Backups saved under: $backup_dir"
  fi
}

mapfile -t STOW_PACKAGES < <(read_manifest "$STOW_FILE")

if [[ ${#STOW_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty stow manifest: $STOW_FILE" >&2
  exit 1
fi

require_command stow

if [[ $ENABLE_LINGER -eq 1 || $ENABLE_LOGIN_WALLPAPER -eq 1 ]]; then
  require_command sudo
fi

echo "[1/6] Preparing stow targets..."
BACKUP_DIR="$HOME/.dotfiles-bootstrap-backup/$(date +%Y%m%d-%H%M%S)"
backup_or_reject_conflicts "$BACKUP_DIR"

echo "[2/6] Pulling Git LFS assets (if available)..."
pull_lfs_assets

echo "[3/6] Deploying stow packages..."
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"
prepare_wallpaper_state

EXPECTED_EXECUTABLES=(
  "$HOME/.config/i3/blueman-launch.sh"
  "$HOME/.config/i3/focus-visual.py"
  "$HOME/.config/i3/launch-terminal.sh"
  "$HOME/.config/i3/nemo-tab-pane-switch.sh"
  "$HOME/.config/i3/restart_monitors.sh"
  "$HOME/.config/i3/session-start.sh"
  "$HOME/.config/i3/vpn-control-toggle.sh"
  "$HOME/.config/polybar/calendar.sh"
  "$HOME/.config/polybar/launch.sh"
  "$HOME/.local/bin/i3-terminal"
  "$HOME/.local/bin/load-xkb-shortcuts"
  "$HOME/.wallpapers/bin/wallpaper_cycle.py"
)

missing_executable=0
for executable in "${EXPECTED_EXECUTABLES[@]}"; do
  if ! ensure_executable "$executable"; then
    missing_executable=1
  fi
done

if [[ $missing_executable -ne 0 ]]; then
  exit 1
fi

echo "[4/6] Configuring file dialogs and folder handling..."
configure_file_dialogs

echo "[5/6] Enabling user services..."
if [[ $SKIP_SERVICES -eq 1 ]]; then
  echo "Skipping user systemd setup."
elif systemctl --user show-environment >/dev/null 2>&1; then
  enable_wallpaper_timer
else
  echo "Skipping user systemd setup: user manager is unavailable."
  echo "Run later: systemctl --user daemon-reload && systemctl --user enable wallpaper-cycle.timer && systemctl --user start wallpaper-cycle.timer"
fi

echo "[6/6] Applying the custom XKB map..."
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
