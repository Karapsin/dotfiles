#!/usr/bin/env bash

dotfiles_ui_helper_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
dotfiles_ui_sizes_file="${DOTFILES_UI_SIZES_FILE:-$dotfiles_ui_helper_dir/ui-sizes.env}"

if [[ -r "$dotfiles_ui_sizes_file" ]]; then
  # shellcheck disable=SC1090
  source "$dotfiles_ui_sizes_file"
fi

: "${DOTFILES_UI_SCALE_MIN_PERCENT:=75}"
: "${DOTFILES_UI_SCALE_MAX_PERCENT:=180}"

dotfiles_ui_valid_name() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

dotfiles_ui_value() {
  local name=$1
  local value

  if ! dotfiles_ui_valid_name "$name"; then
    printf 'Invalid UI size variable name: %s\n' "$name" >&2
    return 2
  fi

  if [[ ! -v "$name" ]]; then
    printf 'Missing UI size variable: %s\n' "$name" >&2
    return 1
  fi

  value=${!name}
  if [[ -z "$value" ]]; then
    printf 'Empty UI size variable: %s\n' "$name" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_int() {
  local name=$1
  local value

  value="$(dotfiles_ui_value "$name")" || return
  if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
    printf 'UI size variable must be an integer: %s=%s\n' "$name" "$value" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_positive_int() {
  local name=$1
  local value

  value="$(dotfiles_ui_int "$name")" || return
  if ((value <= 0)); then
    printf 'UI size variable must be positive: %s=%s\n' "$name" "$value" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_resolved_name() {
  local name=$1

  if [[ "$name" == DOTFILES_UI_* ]]; then
    printf 'DOTFILES_UI_RESOLVED_%s\n' "${name#DOTFILES_UI_}"
  else
    printf 'DOTFILES_UI_RESOLVED_%s\n' "$name"
  fi
}

dotfiles_ui_resolved_value() {
  local name=$1
  local resolved_name

  resolved_name="$(dotfiles_ui_resolved_name "$name")"
  if [[ -v "$resolved_name" ]]; then
    printf '%s\n' "${!resolved_name}"
    return 0
  fi

  dotfiles_ui_value "$name"
}

dotfiles_ui_resolved_int() {
  local name=$1
  local value

  value="$(dotfiles_ui_resolved_value "$name")" || return
  if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
    printf 'Resolved UI size variable must be an integer: %s=%s\n' "$name" "$value" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_resolved_positive_int() {
  local name=$1
  local value

  value="$(dotfiles_ui_resolved_int "$name")" || return
  if ((value <= 0)); then
    printf 'Resolved UI size variable must be positive: %s=%s\n' "$name" "$value" >&2
    return 1
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_max() {
  if (($1 > $2)); then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$2"
  fi
}

dotfiles_ui_min() {
  if (($1 < $2)); then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$2"
  fi
}

dotfiles_ui_scale_dimension() {
  local value=$1
  local base_value=$2
  local base_dimension=$3

  printf '%s\n' "$(((value * base_dimension + base_value / 2) / base_value))"
}

dotfiles_ui_decimal_precision() {
  local value=${1#-}
  local fraction

  if [[ "$value" == *.* ]]; then
    fraction=${value#*.}
    printf '%s\n' "${#fraction}"
  else
    printf '0\n'
  fi
}

dotfiles_ui_round_number() {
  local value=$1

  awk -v value="$value" '
    BEGIN {
      if (value < 0) {
        printf "%d\n", int(value - 0.5)
      } else {
        printf "%d\n", int(value + 0.5)
      }
    }
  '
}

dotfiles_ui_scale_int_literal() {
  local value=$1

  if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
    printf 'UI value must be an integer: %s\n' "$value" >&2
    return 1
  fi

  awk -v value="$value" -v scale="${DOTFILES_UI_RESOLVED_SCALE:-1}" '
    BEGIN {
      scaled = value * scale
      if (scaled < 0) {
        printf "%d\n", int(scaled - 0.5)
      } else {
        printf "%d\n", int(scaled + 0.5)
      }
    }
  '
}

dotfiles_ui_scale_decimal_literal() {
  local value=$1
  local precision=${2:-}

  if [[ ! "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf 'UI value must be numeric: %s\n' "$value" >&2
    return 1
  fi
  if [[ -z "$precision" ]]; then
    precision="$(dotfiles_ui_decimal_precision "$value")"
  fi

  awk -v value="$value" -v scale="${DOTFILES_UI_RESOLVED_SCALE:-1}" -v precision="$precision" '
    BEGIN {
      format = "%." precision "f\n"
      printf format, value * scale
    }
  '
}

dotfiles_ui_scale_unit_literal() {
  local value=$1
  local number
  local unit
  local precision
  local scaled

  if [[ ! "$value" =~ ^(-?[0-9]+([.][0-9]+)?)(pt|px|em)$ ]]; then
    printf 'UI unit value must be a number followed by pt, px, or em: %s\n' "$value" >&2
    return 1
  fi

  number=${BASH_REMATCH[1]}
  unit=${BASH_REMATCH[3]}
  precision="$(dotfiles_ui_decimal_precision "$number")"
  if [[ "$precision" == "0" ]]; then
    scaled="$(dotfiles_ui_scale_int_literal "$number")" || return
  else
    scaled="$(dotfiles_ui_scale_decimal_literal "$number" "$precision")" || return
  fi

  printf '%s%s\n' "$scaled" "$unit"
}

dotfiles_ui_scale_font_literal() {
  local value=$1
  local prefix
  local size
  local offset
  local suffix
  local scaled_size
  local scaled_offset

  if [[ "$value" =~ ^(.*size=)([0-9]+([.][0-9]+)?)(;(-?[0-9]+))?(.*)$ ]]; then
    prefix=${BASH_REMATCH[1]}
    size=${BASH_REMATCH[2]}
    offset=${BASH_REMATCH[5]}
    suffix=${BASH_REMATCH[6]}
    scaled_size="$(dotfiles_ui_scale_decimal_literal "$size" "$(dotfiles_ui_decimal_precision "$size")")" || return
    if [[ -n "$offset" ]]; then
      scaled_offset="$(dotfiles_ui_scale_int_literal "$offset")" || return
      printf '%s%s;%s%s\n' "$prefix" "$scaled_size" "$scaled_offset" "$suffix"
    else
      printf '%s%s%s\n' "$prefix" "$scaled_size" "$suffix"
    fi
    return 0
  fi

  if [[ "$value" =~ ^(.+[[:space:]])([0-9]+([.][0-9]+)?)([[:space:]]*)$ ]]; then
    prefix=${BASH_REMATCH[1]}
    size=${BASH_REMATCH[2]}
    suffix=${BASH_REMATCH[4]}
    scaled_size="$(dotfiles_ui_scale_decimal_literal "$size" "$(dotfiles_ui_decimal_precision "$size")")" || return
    printf '%s%s%s\n' "$prefix" "$scaled_size" "$suffix"
    return 0
  fi

  printf '%s\n' "$value"
}

dotfiles_ui_detect_i3_size() {
  command -v i3-msg >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1

  i3-msg -t get_workspaces 2>/dev/null |
    jq -r '.[] | select(.focused) | "\(.rect.width) \(.rect.height)"' 2>/dev/null |
    awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 > 0 && $2 > 0 { print; exit }'
}

dotfiles_ui_detect_xrandr_size() {
  command -v xrandr >/dev/null 2>&1 || return 1

  xrandr --query 2>/dev/null |
    awk '
      / connected/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]+x[0-9]+\+/) {
            split($i, geometry, /x|\+/)
            if (geometry[1] > 0 && geometry[2] > 0) {
              if ($0 ~ / connected primary/) {
                print geometry[1], geometry[2]
                exit
              }
              if (first_width == "") {
                first_width = geometry[1]
                first_height = geometry[2]
              }
            }
          }
        }
      }
      END {
        if (first_width != "") {
          print first_width, first_height
        }
      }
    ' |
    awk 'NF == 2 { print; exit }'
}

dotfiles_ui_detect_screen_size() {
  local width=${DOTFILES_UI_SCREEN_CURRENT_WIDTH:-}
  local height=${DOTFILES_UI_SCREEN_CURRENT_HEIGHT:-}
  local detected

  if [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ && "$width" -gt 0 && "$height" -gt 0 ]]; then
    printf '%s %s\n' "$width" "$height"
    return 0
  fi

  detected="$(dotfiles_ui_detect_i3_size || true)"
  if [[ -n "$detected" ]]; then
    printf '%s\n' "$detected"
    return 0
  fi

  detected="$(dotfiles_ui_detect_xrandr_size || true)"
  if [[ -n "$detected" ]]; then
    printf '%s\n' "$detected"
    return 0
  fi

  printf '%s %s\n' \
    "$(dotfiles_ui_positive_int DOTFILES_UI_SCREEN_BASE_WIDTH)" \
    "$(dotfiles_ui_positive_int DOTFILES_UI_SCREEN_BASE_HEIGHT)"
}

dotfiles_ui_compute_area_scale() {
  local width=$1
  local height=$2
  local base_width
  local base_height
  local min_percent
  local max_percent

  base_width="$(dotfiles_ui_positive_int DOTFILES_UI_SCREEN_BASE_WIDTH)" || return
  base_height="$(dotfiles_ui_positive_int DOTFILES_UI_SCREEN_BASE_HEIGHT)" || return
  min_percent="$(dotfiles_ui_positive_int DOTFILES_UI_SCALE_MIN_PERCENT)" || return
  max_percent="$(dotfiles_ui_positive_int DOTFILES_UI_SCALE_MAX_PERCENT)" || return

  awk \
    -v width="$width" \
    -v height="$height" \
    -v base_width="$base_width" \
    -v base_height="$base_height" \
    -v min_percent="$min_percent" \
    -v max_percent="$max_percent" '
      BEGIN {
        min_scale = min_percent / 100
        max_scale = max_percent / 100
        scale = sqrt((width * height) / (base_width * base_height))
        if (scale < min_scale) {
          scale = min_scale
        }
        if (scale > max_scale) {
          scale = max_scale
        }
        printf "%.6f\n", scale
      }
    '
}

dotfiles_ui_set_export() {
  local name=$1
  local value=$2

  printf -v "$name" '%s' "$value"
  export "$name"
}

dotfiles_ui_export_raw() {
  local source_name=$1
  local target_name
  local value

  value="$(dotfiles_ui_value "$source_name")" || return
  target_name="$(dotfiles_ui_resolved_name "$source_name")"
  dotfiles_ui_set_export "$target_name" "$value"
}

dotfiles_ui_export_scaled_int() {
  local source_name=$1
  local target_name
  local value
  local scaled

  value="$(dotfiles_ui_int "$source_name")" || return
  scaled="$(dotfiles_ui_scale_int_literal "$value")" || return
  target_name="$(dotfiles_ui_resolved_name "$source_name")"
  dotfiles_ui_set_export "$target_name" "$scaled"
}

dotfiles_ui_export_scaled_decimal() {
  local source_name=$1
  local target_name
  local value
  local scaled

  value="$(dotfiles_ui_value "$source_name")" || return
  scaled="$(dotfiles_ui_scale_decimal_literal "$value")" || return
  target_name="$(dotfiles_ui_resolved_name "$source_name")"
  dotfiles_ui_set_export "$target_name" "$scaled"
}

dotfiles_ui_export_scaled_unit() {
  local source_name=$1
  local target_name
  local value
  local scaled

  value="$(dotfiles_ui_value "$source_name")" || return
  scaled="$(dotfiles_ui_scale_unit_literal "$value")" || return
  target_name="$(dotfiles_ui_resolved_name "$source_name")"
  dotfiles_ui_set_export "$target_name" "$scaled"
}

dotfiles_ui_export_scaled_font() {
  local source_name=$1
  local target_name
  local value
  local scaled

  value="$(dotfiles_ui_value "$source_name")" || return
  scaled="$(dotfiles_ui_scale_font_literal "$value")" || return
  target_name="$(dotfiles_ui_resolved_name "$source_name")"
  dotfiles_ui_set_export "$target_name" "$scaled"
}

dotfiles_ui_export_scaled_int_alias() {
  local source_name=$1
  local target_name=$2
  local min_name=${3:-}
  local value
  local scaled
  local minimum

  value="$(dotfiles_ui_int "$source_name")" || return
  scaled="$(dotfiles_ui_scale_int_literal "$value")" || return
  if [[ -n "$min_name" ]]; then
    minimum="$(dotfiles_ui_int "$min_name")" || return
    if ((scaled < minimum)); then
      scaled=$minimum
    fi
  fi
  dotfiles_ui_set_export "$target_name" "$scaled"
}

dotfiles_ui_export_resolved_values() {
  local width
  local height
  local scale
  local scale_percent
  local name
  local raw_names
  local int_names
  local decimal_names
  local unit_names
  local font_names

  read -r width height < <(dotfiles_ui_detect_screen_size)
  scale="$(dotfiles_ui_compute_area_scale "$width" "$height")" || return
  scale_percent="$(awk -v scale="$scale" 'BEGIN { printf "%d\n", int(scale * 100 + 0.5) }')"

  dotfiles_ui_set_export DOTFILES_UI_RESOLVED_SCREEN_WIDTH "$width"
  dotfiles_ui_set_export DOTFILES_UI_RESOLVED_SCREEN_HEIGHT "$height"
  dotfiles_ui_set_export DOTFILES_UI_RESOLVED_SCALE "$scale"
  dotfiles_ui_set_export DOTFILES_UI_RESOLVED_SCALE_PERCENT "$scale_percent"

  raw_names=(
    DOTFILES_UI_XFT_DPI
    DOTFILES_UI_POLYBAR_DPI
    DOTFILES_UI_ALACRITTY_SCROLL_HISTORY
    DOTFILES_UI_ALACRITTY_SCROLL_MULTIPLIER
    DOTFILES_UI_DUNST_SHOW_AGE_THRESHOLD
    DOTFILES_UI_CALENDAR_FALLBACK_WIDTH_PERMILLE
    DOTFILES_UI_CALENDAR_FALLBACK_HEIGHT_PERMILLE
    DOTFILES_UI_CALENDAR_FALLBACK_CHAR_WIDTH_PERMILLE
    DOTFILES_UI_CALENDAR_MARGIN_PERMILLE
    DOTFILES_UI_CALENDAR_GAP_PERMILLE
    DOTFILES_UI_CALENDAR_FONT_BASE_PX
    DOTFILES_UI_CALENDAR_FONT_MIN_PX
    DOTFILES_UI_CALENDAR_BORDER_BASE_PX
    DOTFILES_UI_CALENDAR_BORDER_MIN_PX
    DOTFILES_UI_NEMO_DEFAULT_ZOOM_LEVEL
  )
  int_names=(
    DOTFILES_UI_I3_FONT_SIZE
    DOTFILES_UI_I3_RESIZE_STEP
    DOTFILES_UI_POPUP_EDGE_GAP
    DOTFILES_UI_POPUP_BOTTOM_GAP
    DOTFILES_UI_VOLUME_BASE_WINDOW_WIDTH
    DOTFILES_UI_VOLUME_BASE_WINDOW_HEIGHT
    DOTFILES_UI_VOLUME_MIN_WINDOW_WIDTH
    DOTFILES_UI_VOLUME_MIN_WINDOW_HEIGHT
    DOTFILES_UI_BLUETOOTH_BASE_WINDOW_WIDTH
    DOTFILES_UI_BLUETOOTH_BASE_WINDOW_HEIGHT
    DOTFILES_UI_BLUETOOTH_MIN_WINDOW_WIDTH
    DOTFILES_UI_BLUETOOTH_MIN_WINDOW_HEIGHT
    DOTFILES_UI_BLUETOOTH_TRAY_MAX_ICON_WIDTH
    DOTFILES_UI_BLUETOOTH_TRAY_MAX_ICON_HEIGHT
    DOTFILES_UI_POWERMENU_BASE_WIDTH
    DOTFILES_UI_POWERMENU_MIN_WIDTH
    DOTFILES_UI_POWERMENU_BASE_X_OFFSET
    DOTFILES_UI_POWERMENU_FONT_BASE_SIZE
    DOTFILES_UI_POWERMENU_FONT_MIN_SIZE
    DOTFILES_UI_POWERMENU_LIST_LINES
    DOTFILES_UI_CALENDAR_HEADER_SPACING
    DOTFILES_UI_CALENDAR_YEAR_NAV_GAP
    DOTFILES_UI_SHORTCUT_CHEATSHEET_WIDTH
    DOTFILES_UI_SHORTCUT_CHEATSHEET_LINES
    DOTFILES_UI_SHORTCUT_CHEATSHEET_COLUMN_WIDTH
    DOTFILES_UI_POLYBAR_PADDING_LEFT
    DOTFILES_UI_POLYBAR_PADDING_RIGHT
    DOTFILES_UI_POLYBAR_MODULE_MARGIN
    DOTFILES_UI_POLYBAR_WORKSPACE_LABEL_PADDING
    DOTFILES_UI_POLYBAR_KEYBOARD_INDICATOR_PADDING
    DOTFILES_UI_POLYBAR_KEYBOARD_INDICATOR_MARGIN
    DOTFILES_UI_POLYBAR_TITLE_MAXLEN
    DOTFILES_UI_LIGHTDM_PANEL_HEIGHT
    DOTFILES_UI_LIGHTDM_PANEL_ITEM_PADDING_X
    DOTFILES_UI_LIGHTDM_MENU_PADDING
    DOTFILES_UI_LIGHTDM_MENUITEM_PADDING_Y
    DOTFILES_UI_LIGHTDM_MENUITEM_PADDING_X
    DOTFILES_UI_LIGHTDM_CARD_BORDER_WIDTH
    DOTFILES_UI_LIGHTDM_CARD_RADIUS
    DOTFILES_UI_LIGHTDM_CARD_PADDING
    DOTFILES_UI_LIGHTDM_CARD_SHADOW_Y
    DOTFILES_UI_LIGHTDM_CARD_SHADOW_BLUR
    DOTFILES_UI_LIGHTDM_CONTENT_PADDING_TOP
    DOTFILES_UI_LIGHTDM_CONTENT_PADDING_X
    DOTFILES_UI_LIGHTDM_CONTENT_PADDING_BOTTOM
    DOTFILES_UI_LIGHTDM_BUTTONBOX_PADDING_TOP
    DOTFILES_UI_LIGHTDM_BUTTONBOX_PADDING_X
    DOTFILES_UI_LIGHTDM_BUTTONBOX_PADDING_BOTTOM
    DOTFILES_UI_LIGHTDM_AVATAR_PADDING
    DOTFILES_UI_LIGHTDM_AVATAR_BORDER_WIDTH
    DOTFILES_UI_LIGHTDM_AVATAR_BORDER_PADDING
    DOTFILES_UI_LIGHTDM_AVATAR_RADIUS
    DOTFILES_UI_LIGHTDM_TITLE_FONT_SIZE
    DOTFILES_UI_LIGHTDM_ENTRY_MIN_HEIGHT
    DOTFILES_UI_LIGHTDM_ENTRY_PADDING_Y
    DOTFILES_UI_LIGHTDM_ENTRY_PADDING_X
    DOTFILES_UI_LIGHTDM_BUTTON_MIN_HEIGHT
    DOTFILES_UI_LIGHTDM_BUTTON_PADDING_Y
    DOTFILES_UI_LIGHTDM_BUTTON_PADDING_X
    DOTFILES_UI_LIGHTDM_CONTROL_BORDER_WIDTH
    DOTFILES_UI_LIGHTDM_CONTROL_RADIUS
    DOTFILES_UI_GTK3_TAB_PADDING_Y
    DOTFILES_UI_GTK3_TAB_PADDING_X
    DOTFILES_UI_GTK4_TAB_PADDING_Y
    DOTFILES_UI_GTK4_TAB_PADDING_X
    DOTFILES_UI_GTK_ACTIVE_BORDER_WIDTH
    DOTFILES_UI_GTK_CONTROL_BORDER_WIDTH
    DOTFILES_UI_GTK_CONTROL_RADIUS
    DOTFILES_UI_GTK_SCALE_TROUGH_HEIGHT
    DOTFILES_UI_GTK_SCALE_SLIDER_BORDER_WIDTH
    DOTFILES_UI_GTK_SCALE_SLIDER_SIZE
    DOTFILES_UI_GTK_SEPARATOR_HEIGHT
    DOTFILES_UI_GTK_PILL_RADIUS
    DOTFILES_UI_ROFI_WINDOW_WIDTH
    DOTFILES_UI_ROFI_WINDOW_BORDER
    DOTFILES_UI_ROFI_WINDOW_RADIUS
    DOTFILES_UI_ROFI_MAINBOX_PADDING
    DOTFILES_UI_ROFI_MAINBOX_SPACING
    DOTFILES_UI_ROFI_INPUT_PADDING_Y
    DOTFILES_UI_ROFI_INPUT_PADDING_X
    DOTFILES_UI_ROFI_INPUT_SPACING
    DOTFILES_UI_ROFI_INPUT_BORDER
    DOTFILES_UI_ROFI_INPUT_RADIUS
    DOTFILES_UI_ROFI_LIST_LINES
    DOTFILES_UI_ROFI_LIST_SPACING
    DOTFILES_UI_ROFI_ELEMENT_PADDING_Y
    DOTFILES_UI_ROFI_ELEMENT_PADDING_X
    DOTFILES_UI_ROFI_ELEMENT_SPACING
    DOTFILES_UI_ROFI_ELEMENT_RADIUS
    DOTFILES_UI_ROFI_MESSAGE_PADDING
    DOTFILES_UI_ROFI_MESSAGE_BORDER
    DOTFILES_UI_ROFI_MESSAGE_RADIUS
    DOTFILES_UI_DUNST_NOTIFICATION_LIMIT
    DOTFILES_UI_DUNST_WIDTH_MIN
    DOTFILES_UI_DUNST_WIDTH_MAX
    DOTFILES_UI_DUNST_HEIGHT_MIN
    DOTFILES_UI_DUNST_HEIGHT_MAX
    DOTFILES_UI_DUNST_OFFSET_X
    DOTFILES_UI_DUNST_OFFSET_Y
    DOTFILES_UI_DUNST_LINE_HEIGHT
    DOTFILES_UI_DUNST_PADDING
    DOTFILES_UI_DUNST_HORIZONTAL_PADDING
    DOTFILES_UI_DUNST_TEXT_ICON_PADDING
    DOTFILES_UI_DUNST_FRAME_WIDTH
    DOTFILES_UI_DUNST_SEPARATOR_HEIGHT
    DOTFILES_UI_DUNST_CORNER_RADIUS
    DOTFILES_UI_DUNST_PROGRESS_BAR_HEIGHT
    DOTFILES_UI_DUNST_PROGRESS_BAR_FRAME_WIDTH
    DOTFILES_UI_DUNST_PROGRESS_BAR_MIN_WIDTH
    DOTFILES_UI_DUNST_PROGRESS_BAR_MAX_WIDTH
    DOTFILES_UI_DUNST_MIN_ICON_SIZE
    DOTFILES_UI_DUNST_MAX_ICON_SIZE
    DOTFILES_UI_ALACRITTY_PADDING_X
    DOTFILES_UI_ALACRITTY_PADDING_Y
    DOTFILES_UI_PICOM_SHADOW_RADIUS
    DOTFILES_UI_PICOM_SHADOW_OFFSET_X
    DOTFILES_UI_PICOM_SHADOW_OFFSET_Y
    DOTFILES_UI_PICOM_CORNER_RADIUS
    DOTFILES_UI_LOCKSCREEN_FONT_LG
    DOTFILES_UI_LOCKSCREEN_FONT_MD
    DOTFILES_UI_LOCKSCREEN_FONT_SM
    DOTFILES_UI_LOCKSCREEN_IND_OFFSET_X
    DOTFILES_UI_LOCKSCREEN_IND_OFFSET_BOTTOM
    DOTFILES_UI_LOCKSCREEN_RING_RADIUS
    DOTFILES_UI_LOCKSCREEN_RING_WIDTH
    DOTFILES_UI_LOCKSCREEN_TIME_OFFSET_LEFT
    DOTFILES_UI_LOCKSCREEN_TIME_OFFSET_UP
    DOTFILES_UI_LOCKSCREEN_GREETER_OFFSET_LEFT
    DOTFILES_UI_LOCKSCREEN_GREETER_OFFSET_DOWN
    DOTFILES_UI_LOCKSCREEN_LAYOUT_OFFSET_LEFT
    DOTFILES_UI_LOCKSCREEN_LAYOUT_OFFSET_DOWN
    DOTFILES_UI_LOCKSCREEN_VERIF_OFFSET_RIGHT
    DOTFILES_UI_LOCKSCREEN_VERIF_OFFSET_UP
    DOTFILES_UI_LOCKSCREEN_WRONG_OFFSET_RIGHT
    DOTFILES_UI_LOCKSCREEN_WRONG_OFFSET_UP
    DOTFILES_UI_LOCKSCREEN_MODIF_OFFSET_RIGHT
    DOTFILES_UI_LOCKSCREEN_MODIF_OFFSET_DOWN
    DOTFILES_UI_DRAWING_HANDLE_SIZE
    DOTFILES_UI_DRAWING_HANDLE_MIN_SIZE
    DOTFILES_UI_DRAWING_HANDLE_HIT_SIZE
    DOTFILES_UI_DRAWING_HANDLE_HIT_MIN_SIZE
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_SIZE
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_HIT_SIZE
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_HIT_MIN_SIZE
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_OFFSET
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_MARGIN
    DOTFILES_UI_DRAWING_TOOLS_PANEL_WIDTH
    DOTFILES_UI_DRAWING_CUSTOM_DIALOG_SPACING
    DOTFILES_UI_DRAWING_CUSTOM_DIALOG_MARGIN
    DOTFILES_UI_MOUSEPAD_WINDOW_WIDTH
    DOTFILES_UI_MOUSEPAD_WINDOW_HEIGHT
    DOTFILES_UI_MOUSEPAD_TAB_WIDTH
  )
  decimal_names=(
    DOTFILES_UI_GSIMPLECAL_WINDOW_RADIUS_EM
    DOTFILES_UI_GSIMPLECAL_PADDING_EM
    DOTFILES_UI_GSIMPLECAL_BUTTON_PADDING_Y_EM
    DOTFILES_UI_GSIMPLECAL_BUTTON_PADDING_X_EM
    DOTFILES_UI_GSIMPLECAL_BUTTON_RADIUS_EM
    DOTFILES_UI_GSIMPLECAL_POPUP_PADDING_EM
    DOTFILES_UI_GSIMPLECAL_HEADER_MARGIN_EM
    DOTFILES_UI_GSIMPLECAL_NAV_RADIUS_EM
    DOTFILES_UI_GSIMPLECAL_NAV_MIN_SIZE_EM
    DOTFILES_UI_GSIMPLECAL_WEEKDAY_MIN_HEIGHT_EM
    DOTFILES_UI_GSIMPLECAL_WEEKDAY_MIN_WIDTH_EM
    DOTFILES_UI_GSIMPLECAL_DAY_RADIUS_EM
    DOTFILES_UI_ROFI_ELEMENT_ICON_SIZE_EM
    DOTFILES_UI_ALACRITTY_FONT_SIZE
    DOTFILES_UI_DRAWING_ROTATE_HANDLE_MIN_RADIUS
    DOTFILES_UI_DRAWING_OVERLAY_BASE_LINE_WIDTH
    DOTFILES_UI_DRAWING_OVERLAY_MIN_LINE_WIDTH
  )
  unit_names=(
    DOTFILES_UI_POWERMENU_MAINBOX_PADDING
    DOTFILES_UI_POWERMENU_MAINBOX_SPACING
    DOTFILES_UI_POWERMENU_LIST_SPACING
    DOTFILES_UI_POWERMENU_ELEMENT_PADDING_Y
    DOTFILES_UI_POWERMENU_ELEMENT_PADDING_X
    DOTFILES_UI_POWERMENU_ELEMENT_SPACING
    DOTFILES_UI_POLYBAR_BAR_HEIGHT
    DOTFILES_UI_POLYBAR_LINE_SIZE
    DOTFILES_UI_POLYBAR_BORDER_SIZE
    DOTFILES_UI_POLYBAR_TRAY_MARGIN
    DOTFILES_UI_POLYBAR_TRAY_PADDING
    DOTFILES_UI_POLYBAR_TRAY_SPACING
    DOTFILES_UI_LIGHTDM_FONT_SIZE
  )
  font_names=(
    DOTFILES_UI_POLYBAR_FONT_0
    DOTFILES_UI_POLYBAR_FONT_1
    DOTFILES_UI_POLYBAR_FONT_2
    DOTFILES_UI_LIGHTDM_FONT
    DOTFILES_UI_ROFI_FONT
    DOTFILES_UI_DUNST_FONT
  )

  for name in "${raw_names[@]}"; do
    dotfiles_ui_export_raw "$name"
  done
  for name in "${int_names[@]}"; do
    dotfiles_ui_export_scaled_int "$name"
  done
  for name in "${decimal_names[@]}"; do
    dotfiles_ui_export_scaled_decimal "$name"
  done
  for name in "${unit_names[@]}"; do
    dotfiles_ui_export_scaled_unit "$name"
  done
  for name in "${font_names[@]}"; do
    dotfiles_ui_export_scaled_font "$name"
  done

  dotfiles_ui_export_scaled_int_alias DOTFILES_UI_CALENDAR_FONT_BASE_PX DOTFILES_UI_RESOLVED_CALENDAR_FONT_PX DOTFILES_UI_CALENDAR_FONT_MIN_PX
  dotfiles_ui_export_scaled_int_alias DOTFILES_UI_CALENDAR_BORDER_BASE_PX DOTFILES_UI_RESOLVED_CALENDAR_BORDER_PX DOTFILES_UI_CALENDAR_BORDER_MIN_PX
}

dotfiles_ui_export_resolved_values
