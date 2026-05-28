#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_helper="${DOTFILES_UI_HELPER:-$HOME/.config/dotfiles/ui-sizes.sh}"
if [[ ! -r "$ui_helper" ]]; then
  ui_helper="$script_dir/../../../home/.config/dotfiles/ui-sizes.sh"
fi
# shellcheck disable=SC1090
source "$ui_helper"

BASE_WINDOW_WIDTH="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_BASE_WINDOW_WIDTH)"
BASE_WINDOW_HEIGHT="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_BASE_WINDOW_HEIGHT)"
MIN_WINDOW_WIDTH="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_MIN_WINDOW_WIDTH)"
MIN_WINDOW_HEIGHT="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_MIN_WINDOW_HEIGHT)"
EDGE_GAP="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_EDGE_GAP)"
BOTTOM_GAP="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_BOTTOM_GAP)"
TRAY_MAX_ICON_WIDTH="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_TRAY_MAX_ICON_WIDTH)"
TRAY_MAX_ICON_HEIGHT="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_BLUETOOTH_TRAY_MAX_ICON_HEIGHT)"

max() {
  dotfiles_ui_max "$@"
}

min() {
  dotfiles_ui_min "$@"
}

read_geometry_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { print $2 }'
}

focused_workspace_geometry() {
  i3-msg -t get_workspaces |
    jq -r '.[] | select(.focused) | [.rect.x, .rect.y, .rect.width, .rect.height, .output] | @tsv'
}

output_geometry() {
  local output=$1

  i3-msg -t get_outputs |
    jq -r --arg output "$output" '.[] | select(.name == $output) | [.rect.x, .rect.y, .rect.width, .rect.height] | @tsv'
}

apply_polybar_bottom_clearance() {
  local output_x=$1
  local output_y=$2
  local output_width=$3
  local output_height=$4
  local current_bottom=$5
  local output_right=$((output_x + output_width))
  local output_bottom=$((output_y + output_height))
  local polybar_id
  local bar_geometry
  local bar_x
  local bar_y
  local bar_width
  local bar_height
  local bar_right

  command -v xdotool >/dev/null 2>&1 || {
    printf '%s\n' "$current_bottom"
    return
  }

  while IFS= read -r polybar_id; do
    [[ -n "$polybar_id" ]] || continue
    bar_geometry="$(xdotool getwindowgeometry --shell "$polybar_id" 2>/dev/null || true)"
    [[ -n "$bar_geometry" ]] || continue

    bar_x="$(read_geometry_value X <<<"$bar_geometry")"
    bar_y="$(read_geometry_value Y <<<"$bar_geometry")"
    bar_width="$(read_geometry_value WIDTH <<<"$bar_geometry")"
    bar_height="$(read_geometry_value HEIGHT <<<"$bar_geometry")"
    [[ "$bar_x" =~ ^-?[0-9]+$ && "$bar_y" =~ ^-?[0-9]+$ && "$bar_width" =~ ^[0-9]+$ && "$bar_height" =~ ^[0-9]+$ ]] || continue

    bar_right=$((bar_x + bar_width))
    if ((bar_x < output_right && bar_right > output_x && bar_y >= output_bottom - bar_height - EDGE_GAP)); then
      current_bottom="$(min "$current_bottom" "$bar_y")"
    fi
  done < <(xdotool search --class polybar 2>/dev/null || true)

  printf '%s\n' "$current_bottom"
}

find_blueman_manager_container() {
  i3-msg -t get_tree |
    jq -r '.. | objects | select(.window? != null and (.window_properties.class? // "" | test("^Blueman-manager$"; "i"))) | [.id, .window] | @tsv' |
    head -n 1
}

window_scratchpad_state() {
  local container_id=$1

  i3-msg -t get_tree |
    jq -r --argjson container_id "$container_id" '.. | objects | select(.id? == $container_id) | .scratchpad_state // "none"' |
    head -n 1
}

window_center_x_if_on_current_bar() {
  local window_id=$1
  local output_x=$2
  local output_y=$3
  local output_width=$4
  local output_height=$5
  local workspace_y=$6
  local usable_bottom=$7
  local output_right=$((output_x + output_width))
  local output_bottom=$((output_y + output_height))
  local geometry
  local window_x
  local window_y
  local window_width
  local window_height
  local window_right
  local on_bar=0

  geometry="$(xdotool getwindowgeometry --shell "$window_id" 2>/dev/null || true)"
  [[ -n "$geometry" ]] || return 1

  window_x="$(read_geometry_value X <<<"$geometry")"
  window_y="$(read_geometry_value Y <<<"$geometry")"
  window_width="$(read_geometry_value WIDTH <<<"$geometry")"
  window_height="$(read_geometry_value HEIGHT <<<"$geometry")"
  [[ "$window_x" =~ ^-?[0-9]+$ && "$window_y" =~ ^-?[0-9]+$ && "$window_width" =~ ^[0-9]+$ && "$window_height" =~ ^[0-9]+$ ]] || return 1
  ((window_width <= TRAY_MAX_ICON_WIDTH && window_height <= TRAY_MAX_ICON_HEIGHT)) || return 1

  window_right=$((window_x + window_width))
  ((window_x < output_right && window_right > output_x)) || return 1

  if ((usable_bottom < output_bottom && window_y + window_height > usable_bottom - EDGE_GAP && window_y < output_bottom + EDGE_GAP)); then
    on_bar=1
  fi
  if ((workspace_y > output_y && window_y < workspace_y + EDGE_GAP && window_y + window_height > output_y - EDGE_GAP)); then
    on_bar=1
  fi

  if ((on_bar == 1)); then
    printf '%s\n' "$((window_x + window_width / 2))"
    return 0
  fi

  return 1
}

bluetooth_tray_center_x() {
  local output_x=$1
  local output_y=$2
  local output_width=$3
  local output_height=$4
  local workspace_y=$5
  local usable_bottom=$6
  local window_id

  command -v xdotool >/dev/null 2>&1 || return 1

  while IFS= read -r window_id; do
    [[ -n "$window_id" ]] || continue
    window_center_x_if_on_current_bar "$window_id" "$output_x" "$output_y" "$output_width" "$output_height" "$workspace_y" "$usable_bottom" && return 0
  done < <(xdotool search --class blueman-tray 2>/dev/null || true)

  while IFS= read -r window_id; do
    [[ -n "$window_id" ]] || continue
    window_center_x_if_on_current_bar "$window_id" "$output_x" "$output_y" "$output_width" "$output_height" "$workspace_y" "$usable_bottom" && return 0
  done < <(xdotool search --class yad 2>/dev/null || true)

  return 1
}

start_applet() {
  if pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
    return 0
  fi

  setsid -f blueman-applet >/dev/null 2>&1
}

open_manager_if_needed() {
  local container
  local attempt

  container="$(find_blueman_manager_container)"
  if [[ -n "$container" ]]; then
    printf '%s\n' "$container"
    return
  fi

  if command -v setsid >/dev/null 2>&1; then
    setsid -f blueman-manager >/dev/null 2>&1
  else
    blueman-manager >/dev/null 2>&1 &
  fi

  for ((attempt = 0; attempt < 100; attempt++)); do
    sleep 0.02
    container="$(find_blueman_manager_container)"
    if [[ -n "$container" ]]; then
      printf '%s\n' "$container"
      return
    fi
  done

  return 1
}

place_manager() {
  local open_if_missing=${1:-yes}
  local workspace_x
  local workspace_y
  local workspace_width
  local workspace_height
  local workspace_output
  local output_x
  local output_y
  local output_width
  local output_height
  local usable_bottom
  local usable_height
  local max_width
  local max_height
  local target_width
  local target_height
  local target_x
  local target_y
  local tray_center_x
  local anchor_center_x
  local safe_bottom
  local container
  local container_id
  local window_id
  local scratchpad_state
  local actual_geometry
  local actual_y
  local actual_width
  local actual_height
  local actual_bottom
  local bottom_overlap
  local adjusted_x
  local adjusted_y
  local max_adjusted_x

  read -r workspace_x workspace_y workspace_width workspace_height workspace_output < <(focused_workspace_geometry)
  read -r output_x output_y output_width output_height < <(output_geometry "$workspace_output")

  if [[ -z "${output_x:-}" ]]; then
    output_x=$workspace_x
    output_y=$workspace_y
    output_width=$workspace_width
    output_height=$workspace_height
  fi

  usable_bottom=$((workspace_y + workspace_height))
  usable_bottom="$(apply_polybar_bottom_clearance "$output_x" "$output_y" "$output_width" "$output_height" "$usable_bottom")"
  usable_height=$((usable_bottom - workspace_y))
  ((usable_height > 0)) || usable_height=$workspace_height

  max_width="$(max 1 "$((workspace_width - EDGE_GAP * 2))")"
  max_height="$(max 1 "$((usable_height - EDGE_GAP - BOTTOM_GAP))")"

  target_width=$BASE_WINDOW_WIDTH
  target_height=$BASE_WINDOW_HEIGHT
  target_width="$(max "$target_width" "$MIN_WINDOW_WIDTH")"
  target_height="$(max "$target_height" "$MIN_WINDOW_HEIGHT")"
  target_width="$(min "$target_width" "$max_width")"
  target_height="$(min "$target_height" "$max_height")"

  if tray_center_x="$(bluetooth_tray_center_x "$output_x" "$output_y" "$output_width" "$output_height" "$workspace_y" "$usable_bottom")"; then
    anchor_center_x=$tray_center_x
  else
    anchor_center_x=$((workspace_x + workspace_width / 2))
  fi
  target_x=$((anchor_center_x - target_width / 2))
  target_x="$(max "$target_x" "$((workspace_x + EDGE_GAP))")"
  target_x="$(min "$target_x" "$((workspace_x + workspace_width - target_width - EDGE_GAP))")"
  safe_bottom=$((usable_bottom - BOTTOM_GAP))
  target_y=$((safe_bottom - target_height))

  if [[ "$open_if_missing" == "yes" ]]; then
    read -r container_id window_id < <(open_manager_if_needed)
  else
    read -r container_id window_id < <(find_blueman_manager_container)
    [[ -n "${container_id:-}" && -n "${window_id:-}" ]] || return 0
  fi
  scratchpad_state="$(window_scratchpad_state "$container_id")"

  if [[ "$scratchpad_state" == "none" ]]; then
    i3-msg -q "[con_id=\"$container_id\"] move to workspace current, floating enable, resize set $target_width $target_height, move position $target_x $target_y, focus"
  else
    i3-msg -q "[con_id=\"$container_id\"] floating enable, resize set $target_width $target_height, move position $target_x $target_y, scratchpad show, focus"
  fi
  sleep 0.1

  actual_geometry="$(xdotool getwindowgeometry --shell "$window_id" 2>/dev/null || true)"
  [[ -n "$actual_geometry" ]] || return 0

  actual_y="$(read_geometry_value Y <<<"$actual_geometry")"
  actual_width="$(read_geometry_value WIDTH <<<"$actual_geometry")"
  actual_height="$(read_geometry_value HEIGHT <<<"$actual_geometry")"
  [[ "$actual_y" =~ ^-?[0-9]+$ && "$actual_width" =~ ^[0-9]+$ && "$actual_height" =~ ^[0-9]+$ ]] || return 0

  adjusted_x=$((anchor_center_x - actual_width / 2))
  adjusted_x="$(max "$adjusted_x" "$((workspace_x + EDGE_GAP))")"
  max_adjusted_x=$((workspace_x + workspace_width - actual_width - EDGE_GAP))
  max_adjusted_x="$(max "$max_adjusted_x" "$((workspace_x + EDGE_GAP))")"
  adjusted_x="$(min "$adjusted_x" "$max_adjusted_x")"
  adjusted_y=$target_y
  actual_bottom=$((actual_y + actual_height))
  if ((actual_bottom > safe_bottom)); then
    bottom_overlap=$((actual_bottom - safe_bottom))
    adjusted_y=$((target_y - bottom_overlap))
  fi

  if ((adjusted_x != target_x || adjusted_y != target_y)); then
    i3-msg -q "[con_id=\"$container_id\"] move position $adjusted_x $adjusted_y, focus"
  fi
}

case "$1" in
  --applet)
    start_applet
    ;;
  --manager)
    start_applet
    place_manager yes
    ;;
  --place-existing)
    place_manager no
    ;;
  *)
    echo "Usage: $0 --applet|--manager|--place-existing" >&2
    exit 2
    ;;
esac
