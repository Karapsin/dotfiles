#!/usr/bin/env bash

set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"
DOTFILES_DIR="$(cd -- "$script_dir/../../../.." && pwd)"
if [[ ! -r "$DOTFILES_DIR/scripts/bootstrap-env.sh" ]]; then
  DOTFILES_DIR="$(cd -- "$script_dir/../../.." && pwd)"
fi
BACKUP_EXISTING="${BACKUP_EXISTING:-1}"
render_only=0

for arg in "$@"; do
  case "$arg" in
    --render-only)
      render_only=1
      ;;
    -h|--help)
      printf 'Usage: %s [--render-only]\n' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      printf 'Usage: %s [--render-only]\n' "$0" >&2
      exit 2
      ;;
  esac
done

# shellcheck source=scripts/bootstrap-env.sh
source "$DOTFILES_DIR/scripts/bootstrap-env.sh"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$HOME/.dotfiles-bootstrap-backup/update-ui-$timestamp"

has_display() {
  [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]
}

start_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$@" >/dev/null 2>&1
  else
    "$@" >/dev/null 2>&1 &
  fi
}

status() {
  printf '[update-ui] %s\n' "$*"
}

render_ui_files() {
  status "Rendering UI files from $DOTFILES_DIR/home/.config/dotfiles/ui-sizes.env"
  generate_dotfiles_ui_files "$backup_dir"
}

merge_xresources() {
  if ! has_display; then
    status "Skipping Xresources merge: no graphical display."
    return
  fi
  if ! command -v xrdb >/dev/null 2>&1; then
    status "Skipping Xresources merge: xrdb is unavailable."
    return
  fi
  if [[ ! -f "$HOME/.Xresources" ]]; then
    status "Skipping Xresources merge: ~/.Xresources is missing."
    return
  fi

  xrdb -merge "$HOME/.Xresources"
  status "Merged Xresources."
}

restart_polybar() {
  local launcher="$HOME/.config/polybar/launch.sh"

  if [[ ! -x "$launcher" ]]; then
    status "Skipping Polybar restart: $launcher is missing or not executable."
    return
  fi

  start_detached "$launcher" restart
  status "Restarted Polybar."
}

restart_dunst() {
  if ! has_display; then
    status "Skipping Dunst restart: no graphical display."
    return
  fi
  if ! command -v dunst >/dev/null 2>&1; then
    status "Skipping Dunst restart: dunst is unavailable."
    return
  fi

  pkill -x dunst >/dev/null 2>&1 || true
  start_detached dunst
  status "Restarted Dunst."
}

restart_picom() {
  local config="$HOME/.config/picom/picom.conf"

  if ! has_display; then
    status "Skipping Picom restart: no graphical display."
    return
  fi
  if ! command -v picom >/dev/null 2>&1; then
    status "Skipping Picom restart: picom is unavailable."
    return
  fi

  pkill -x picom >/dev/null 2>&1 || true
  if [[ -f "$config" ]]; then
    start_detached picom --daemon --config "$config"
  else
    start_detached picom --daemon --no-fading-openclose
  fi
  status "Restarted Picom."
}

reload_i3() {
  if ! has_display; then
    status "Skipping i3 reload: no graphical display."
    return
  fi
  if ! command -v i3-msg >/dev/null 2>&1; then
    status "Skipping i3 reload: i3-msg is unavailable."
    return
  fi

  if i3-msg reload >/dev/null 2>&1; then
    status "Reloaded i3."
  else
    status "Skipping i3 reload: could not contact i3."
  fi
}

render_ui_files
if ((render_only == 1)); then
  status "Done."
  exit 0
fi
merge_xresources
restart_polybar
restart_dunst
restart_picom
reload_i3
status "Done."
