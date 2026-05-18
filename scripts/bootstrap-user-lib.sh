#!/usr/bin/env bash

# Shared helpers for per-user bootstrap scripts. This file is intended to be
# sourced after DOTFILES_DIR has been set by the caller.

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
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  git -C "$dotfiles_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

pull_lfs_assets() {
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  local skip_lfs="${SKIP_LFS:-0}"

  if [[ $skip_lfs -eq 1 ]]; then
    echo "Skipping Git LFS pull."
  elif ! command -v git >/dev/null 2>&1; then
    echo "Skipping Git LFS pull: git is unavailable."
  elif ! is_git_worktree; then
    echo "Skipping Git LFS pull: $dotfiles_dir is not a Git repository."
  elif command -v git-lfs >/dev/null 2>&1; then
    git -C "$dotfiles_dir" lfs pull || true
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

verify_expected_executables() {
  local executable
  local missing_executable=0

  for executable in "$@"; do
    if ! ensure_executable "$executable"; then
      missing_executable=1
    fi
  done

  [[ $missing_executable -eq 0 ]]
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
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  local current="$HOME/.wallpapers/current_wallpaper.png"
  local state_file="$HOME/.wallpapers/state/state.json"
  local current_source="$dotfiles_dir/wallpapers/.wallpapers/current_wallpaper.png"
  local state_source="$dotfiles_dir/wallpapers/.wallpapers/state/state.json"

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
  local skip_services="${SKIP_SERVICES:-0}"

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

  if command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --type=method_call --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
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

    if gsettings writable com.github.maoschanz.drawing deco-type >/dev/null 2>&1; then
      gsettings set com.github.maoschanz.drawing dark-theme-variant true >/dev/null 2>&1 || true
      gsettings set com.github.maoschanz.drawing deco-type mts >/dev/null 2>&1 || true
      gsettings set com.github.maoschanz.drawing show-labels false >/dev/null 2>&1 || true
      gsettings set com.github.maoschanz.drawing ui-background-rgba "['0.047', '0.067', '0.086', '1.0']" >/dev/null 2>&1 || true
    fi

    if gsettings writable org.xfce.mousepad.preferences.view color-scheme >/dev/null 2>&1; then
      gsettings set org.xfce.mousepad.preferences.view color-scheme dotfiles-dark-blue >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.view highlight-current-line true >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.view word-wrap true >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.view tab-width 4 >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.window menubar-visible true >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.window toolbar-visible false >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.window statusbar-visible true >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.preferences.window client-side-decorations false >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.state.window width 900 >/dev/null 2>&1 || true
      gsettings set org.xfce.mousepad.state.window height 600 >/dev/null 2>&1 || true
    fi
  fi

  if [[ $skip_services -eq 1 ]]; then
    echo "Skipping portal restart."
  elif systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user restart xdg-desktop-portal xdg-desktop-portal-gtk >/dev/null 2>&1 || true
  else
    echo "Skipping portal restart: user manager is unavailable."
  fi
}

configure_chrome_theme() {
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  local policy_file="/etc/opt/chrome/policies/managed/dotfiles-dark-blue-theme.json"
  local policy_source="$dotfiles_dir/root/etc/opt/chrome/policies/managed/dotfiles-dark-blue-theme.json"
  local launcher="$HOME/.local/bin/google-chrome-dotfiles"

  if [[ -f "$policy_file" ]]; then
    echo "Chrome dark-blue theme policy is installed: $policy_file"
  else
    echo "Chrome dark-blue theme policy is not installed." >&2
    echo "Run this once, then fully restart Chrome:" >&2
    echo "  sudo install -Dm644 $policy_source $policy_file" >&2
  fi

  if [[ -x "$launcher" ]]; then
    echo "Chrome launcher deployed: $launcher"
  else
    echo "Chrome theme launcher missing or not executable after stow: $launcher" >&2
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
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  local backup_existing="${BACKUP_EXISTING:-1}"
  local conflict_found=0
  local moved_any=0
  local package

  for package in "${STOW_PACKAGES[@]}"; do
    local package_dir="$dotfiles_dir/$package"

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
        .stow-local-ignore|.wallpapers/current_wallpaper.png|.wallpapers/state/state.json)
          continue
          ;;
      esac

      [[ -e "$target_path" || -L "$target_path" ]] || continue
      is_managed_target "$target_path" "$source_path" && continue

      if [[ $backup_existing -eq 0 ]]; then
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

remove_legacy_wallpaper_link() {
  local link=$1
  local old_path=$2
  local dotfiles_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}"
  local target

  [[ -L "$link" ]] || return 0
  target="$(readlink "$link")"
  case "$target" in
    "$old_path"|"$dotfiles_dir/$old_path"|*/$old_path)
      echo "Removing legacy wallpaper Stow link: $link"
      rm -f "$link"
      ;;
  esac
}

cleanup_legacy_wallpaper_links() {
  remove_legacy_wallpaper_link "$HOME/etc" "wallpapers/etc"
  remove_legacy_wallpaper_link "$HOME/bootstrap_wallpapers.sh" "wallpapers/bootstrap_wallpapers.sh"
}
