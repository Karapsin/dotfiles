#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run as your normal user: ./bootstrap-user.sh [--noconfirm] [--skip-aur]"
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUR_FILE="$DOTFILES_DIR/packages/aur.txt"
STOW_FILE="$DOTFILES_DIR/packages/stow.txt"

NO_CONFIRM=0
SKIP_AUR=0

while (($#)); do
  case "$1" in
    --noconfirm)
      NO_CONFIRM=1
      ;;
    --skip-aur)
      SKIP_AUR=1
      ;;
    *)
      echo "Unknown option: $1" >&2
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
  if ! command -v git >/dev/null 2>&1; then
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

  if systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk >/dev/null 2>&1 || true
  else
    echo "Skipping portal restart: user manager is unavailable."
  fi
}

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
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  pushd "$tmpdir/yay" >/dev/null
  if [[ $NO_CONFIRM -eq 1 ]]; then
    makepkg -si --needed --noconfirm
  else
    makepkg -si --needed
  fi
  popd >/dev/null
  trap - RETURN
  rm -rf "$tmpdir"
}

remove_legacy_wallpaper_link() {
  local link=$1
  local old_path=$2
  local target

  [[ -L "$link" ]] || return 0
  target="$(readlink "$link")"
  case "$target" in
    "$old_path"|"$DOTFILES_DIR/$old_path"|*/$old_path)
      echo "Removing legacy wallpaper Stow link: $link"
      rm -f "$link"
      ;;
  esac
}

cleanup_legacy_wallpaper_links() {
  remove_legacy_wallpaper_link "$HOME/etc" "wallpapers/etc"
  remove_legacy_wallpaper_link "$HOME/bootstrap_wallpapers.sh" "wallpapers/bootstrap_wallpapers.sh"
}

require_command stow

echo "[1/6] Pulling Git LFS assets (if available)..."
pull_lfs_assets

echo "[2/6] Deploying stow packages..."
cleanup_legacy_wallpaper_links
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"
prepare_wallpaper_state

EXPECTED_EXECUTABLES=(
  "$HOME/.config/i3/blueman-launch.sh"
  "$HOME/.config/i3/nemo-tab-pane-switch.sh"
  "$HOME/.config/i3/session-start.sh"
  "$HOME/.config/i3/vpn-control-toggle.sh"
  "$HOME/.config/polybar/calendar.sh"
  "$HOME/.config/polybar/launch.sh"
  "$HOME/.local/bin/load-xkb-shortcuts"
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

if [[ $SKIP_AUR -eq 0 && ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  echo "[3/6] Installing AUR packages..."
  ensure_yay
  YAY_ARGS=(-S --needed)
  if [[ $NO_CONFIRM -eq 1 ]]; then
    YAY_ARGS+=(--noconfirm)
  fi
  yay "${YAY_ARGS[@]}" "${AUR_PACKAGES[@]}"
else
  echo "[3/6] Skipping AUR packages."
fi

echo "[4/6] Configuring file dialogs and folder handling..."
configure_file_dialogs

echo "[5/6] Enabling user services..."
if systemctl --user show-environment >/dev/null 2>&1; then
  enable_wallpaper_timer
else
  echo "Skipping user systemd setup: user manager is unavailable."
  echo "Run later: systemctl --user daemon-reload && systemctl --user enable wallpaper-cycle.timer && systemctl --user start wallpaper-cycle.timer"
fi

echo "[6/6] Applying the custom XKB map..."
if [[ -x "$HOME/.local/bin/load-xkb-shortcuts" ]]; then
  "$HOME/.local/bin/load-xkb-shortcuts" || true
fi

echo
echo "User bootstrap complete."
echo "Manual follow-up: restore secrets such as ~/.ssh, gh auth, browser profiles, and any app logins."
