#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_helper="${DOTFILES_UI_HELPER:-$HOME/.config/dotfiles/ui-sizes.sh}"
if [[ ! -r "$ui_helper" ]]; then
  ui_helper="$script_dir/../../../home/.config/dotfiles/ui-sizes.sh"
fi
# shellcheck disable=SC1090
source "$ui_helper"

BASE_WINDOW_WIDTH="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_VOLUME_BASE_WINDOW_WIDTH)"
BASE_WINDOW_HEIGHT="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_VOLUME_BASE_WINDOW_HEIGHT)"
MIN_WINDOW_WIDTH="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_VOLUME_MIN_WINDOW_WIDTH)"
MIN_WINDOW_HEIGHT="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_VOLUME_MIN_WINDOW_HEIGHT)"
EDGE_GAP="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_EDGE_GAP)"
BOTTOM_GAP="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_BOTTOM_GAP)"
PULSE_TRAY_WINDOW_NAME="PulseAudio system tray"

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
  local bar_geometry
  local bar_x
  local bar_y
  local bar_width
  local bar_height
  local output_right=$((output_x + output_width))
  local output_bottom=$((output_y + output_height))
  local bar_right
  local polybar_id

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

find_pavucontrol_window() {
  i3-msg -t get_tree |
    jq -r '.. | objects | select(.window? != null and (.window_properties.class? // "" | test("^pavucontrol$"; "i"))) | .window' |
    head -n 1
}

pavucontrol_scratchpad_state() {
  local window_id=$1

  i3-msg -t get_tree |
    jq -r --argjson window_id "$window_id" '.. | objects | select(.window? == $window_id) | .scratchpad_state // "none"' |
    head -n 1
}

tray_anchor_center_x() {
  local workspace_x=$1
  local workspace_width=$2
  local workspace_right=$((workspace_x + workspace_width))
  local tray_id
  local tray_geometry
  local tray_x
  local tray_width
  local tray_right

  command -v xdotool >/dev/null 2>&1 || return 1

  while IFS= read -r tray_id; do
    [[ -n "$tray_id" ]] || continue
    tray_geometry="$(xdotool getwindowgeometry --shell "$tray_id" 2>/dev/null || true)"
    [[ -n "$tray_geometry" ]] || continue

    tray_x="$(read_geometry_value X <<<"$tray_geometry")"
    tray_width="$(read_geometry_value WIDTH <<<"$tray_geometry")"
    [[ "$tray_x" =~ ^-?[0-9]+$ && "$tray_width" =~ ^[0-9]+$ ]] || continue

    tray_right=$((tray_x + tray_width))
    if ((tray_x < workspace_right && tray_right > workspace_x)); then
      printf '%s\n' "$((tray_x + tray_width / 2))"
      return 0
    fi
  done < <(xdotool search --name "$PULSE_TRAY_WINDOW_NAME" 2>/dev/null || true)

  return 1
}

open_pavucontrol_if_needed() {
  local window_id
  local attempt

  window_id="$(find_pavucontrol_window)"
  if [[ -n "$window_id" ]]; then
    printf '%s\n' "$window_id"
    return
  fi

  if command -v setsid >/dev/null 2>&1; then
    setsid -f pavucontrol --tab=1 >/dev/null 2>&1
  else
    pavucontrol --tab=1 >/dev/null 2>&1 &
  fi
  for ((attempt = 0; attempt < 100; attempt++)); do
    sleep 0.02
    window_id="$(find_pavucontrol_window)"
    if [[ -n "$window_id" ]]; then
      printf '%s\n' "$window_id"
      return
    fi
  done

  return 1
}

place_pavucontrol() {
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
  local safe_bottom
  local window_id
  local scratchpad_state
  local actual_geometry
  local actual_y
  local actual_height
  local adjusted_y
  local actual_bottom
  local bottom_overlap

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

  if tray_center_x="$(tray_anchor_center_x "$workspace_x" "$workspace_width")"; then
    target_x=$((tray_center_x - target_width / 2))
  else
    target_x=$((workspace_x + (workspace_width - target_width) / 2))
  fi
  target_x="$(max "$target_x" "$((workspace_x + EDGE_GAP))")"
  target_x="$(min "$target_x" "$((workspace_x + workspace_width - target_width - EDGE_GAP))")"
  safe_bottom=$((usable_bottom - BOTTOM_GAP))
  target_y=$((safe_bottom - target_height))

  window_id="$(open_pavucontrol_if_needed)"
  scratchpad_state="$(pavucontrol_scratchpad_state "$window_id")"

  if [[ "$scratchpad_state" == "none" ]]; then
    i3-msg -q "[id=\"$window_id\"] move to workspace current, floating enable, resize set $target_width $target_height, move position $target_x $target_y, focus"
  else
    i3-msg -q "[id=\"$window_id\"] floating enable, resize set $target_width $target_height, move position $target_x $target_y, scratchpad show, focus"
  fi
  sleep 0.1

  actual_geometry="$(xdotool getwindowgeometry --shell "$window_id" 2>/dev/null || true)"
  [[ -n "$actual_geometry" ]] || return 0

  actual_y="$(read_geometry_value Y <<<"$actual_geometry")"
  actual_height="$(read_geometry_value HEIGHT <<<"$actual_geometry")"
  [[ "$actual_y" =~ ^-?[0-9]+$ && "$actual_height" =~ ^[0-9]+$ ]] || return 0

  actual_bottom=$((actual_y + actual_height))
  if ((actual_bottom > safe_bottom)); then
    bottom_overlap=$((actual_bottom - safe_bottom))
    adjusted_y=$((target_y - bottom_overlap))
    i3-msg -q "[id=\"$window_id\"] move position $target_x $adjusted_y, focus"
  fi
}

place_pavucontrol
