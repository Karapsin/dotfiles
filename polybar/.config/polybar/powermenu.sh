#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_helper="${DOTFILES_UI_HELPER:-$HOME/.config/dotfiles/ui-sizes.sh}"
if [[ ! -r "$ui_helper" ]]; then
  ui_helper="$script_dir/../../../home/.config/dotfiles/ui-sizes.sh"
fi
# shellcheck disable=SC1090
source "$ui_helper"

reboot_label=" reboot"
poweroff_label=" poweroff"
logout_label="logout"
screenshot_keys="Super+Shift+s,Super+S"
cancel_keys="Escape,Control+g,Control+bracketleft,Super+Shift+p,Super+P"
base_menu_width="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_POWERMENU_BASE_WIDTH)"
min_menu_width="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_POWERMENU_MIN_WIDTH)"
base_x_offset="$(dotfiles_ui_resolved_int DOTFILES_UI_POWERMENU_BASE_X_OFFSET)"
edge_gap="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_EDGE_GAP)"
bottom_gap="$(dotfiles_ui_resolved_int DOTFILES_UI_POPUP_BOTTOM_GAP)"
font_base_size="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_POWERMENU_FONT_BASE_SIZE)"
font_min_size="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_POWERMENU_FONT_MIN_SIZE)"
mainbox_padding="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_MAINBOX_PADDING)"
mainbox_spacing="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_MAINBOX_SPACING)"
list_lines="$(dotfiles_ui_resolved_positive_int DOTFILES_UI_POWERMENU_LIST_LINES)"
list_spacing="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_LIST_SPACING)"
element_padding_y="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_ELEMENT_PADDING_Y)"
element_padding_x="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_ELEMENT_PADDING_X)"
element_spacing="$(dotfiles_ui_resolved_value DOTFILES_UI_POWERMENU_ELEMENT_SPACING)"

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

polybar_top_for_output() {
  local output_x=$1
  local output_width=$2
  local output_y=$3
  local output_height=$4
  local output_right=$((output_x + output_width))
  local output_bottom=$((output_y + output_height))
  local current_bottom=$output_bottom
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
    if ((bar_x < output_right && bar_right > output_x && bar_y >= output_bottom - bar_height - edge_gap)); then
      current_bottom="$(min "$current_bottom" "$bar_y")"
    fi
  done < <(xdotool search --class polybar 2>/dev/null || true)

  printf '%s\n' "$current_bottom"
}

menu_geometry() {
  local workspace_x
  local workspace_y
  local workspace_width
  local workspace_height
  local workspace_output
  local output_x
  local output_y
  local output_width
  local output_height
  local polybar_top
  local bottom_clearance
  local menu_width
  local x_offset

  read -r workspace_x workspace_y workspace_width workspace_height workspace_output < <(focused_workspace_geometry)
  read -r output_x output_y output_width output_height < <(output_geometry "$workspace_output")

  if [[ -z "${output_x:-}" ]]; then
    output_x=$workspace_x
    output_y=$workspace_y
    output_width=$workspace_width
    output_height=$workspace_height
  fi

  polybar_top="$(polybar_top_for_output "$output_x" "$output_width" "$output_y" "$output_height")"
  bottom_clearance=$((output_y + output_height - polybar_top + bottom_gap))
  menu_width=$base_menu_width
  menu_width="$(max "$menu_width" "$min_menu_width")"
  menu_width="$(min "$menu_width" "$((workspace_width - edge_gap * 2))")"
  x_offset=$base_x_offset
  x_offset="$(max "$x_offset" "$edge_gap")"

  printf '%s %s %s\n' "$menu_width" "$bottom_clearance" "$x_offset"
}

font_size=$font_base_size
if ((font_size < font_min_size)); then
  font_size=$font_min_size
fi

read -r menu_width bottom_clearance x_offset < <(menu_geometry)

theme="
window {
  font: \"Noto Sans Mono $font_size\";
  location: south west;
  anchor: south west;
  width: ${menu_width}px;
  x-offset: ${x_offset}px;
  y-offset: -${bottom_clearance}px;
}

mainbox {
  padding: $mainbox_padding;
  spacing: $mainbox_spacing;
}

inputbar {
  enabled: false;
}

listview {
  lines: $list_lines;
  spacing: $list_spacing;
}

element {
  children: [ element-text ];
  padding: $element_padding_y $element_padding_x;
  spacing: $element_spacing;
}
"

set +e
choice="$(
  printf '%s\n' "$logout_label" "$reboot_label" "$poweroff_label" |
    rofi \
      -dmenu \
      -no-custom \
      -no-sort \
      -no-show-icons \
      -selected-row 2 \
      -hover-select \
      -me-select-entry "" \
      -me-accept-entry MousePrimary \
      -kb-custom-1 "$screenshot_keys" \
      -kb-cancel "$cancel_keys" \
      -p "" \
      -l "$list_lines" \
      -theme-str "$theme"
)"
status=$?
set -e

case "$status" in
  0)
    ;;
  1)
    exit 0
    ;;
  10)
    exec flameshot gui
    ;;
  *)
    exit "$status"
    ;;
esac

case "$choice" in
  "$reboot_label")
    exec systemctl reboot
    ;;
  "$poweroff_label")
    exec systemctl poweroff
    ;;
  "$logout_label")
    exec i3-msg exit
    ;;
  *)
    exit 0
    ;;
esac
