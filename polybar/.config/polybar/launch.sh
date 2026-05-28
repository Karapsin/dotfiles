#!/usr/bin/env bash

BAR_NAME="example"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_helper="${DOTFILES_UI_HELPER:-$HOME/.config/dotfiles/ui-sizes.sh}"
if [[ ! -r "$ui_helper" ]]; then
  ui_helper="$script_dir/../../../home/.config/dotfiles/ui-sizes.sh"
fi
# shellcheck disable=SC1090
source "$ui_helper"

export POLYBAR_BAR_HEIGHT="${POLYBAR_BAR_HEIGHT:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_BAR_HEIGHT)}"
export POLYBAR_LINE_SIZE="${POLYBAR_LINE_SIZE:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_LINE_SIZE)}"
export POLYBAR_BORDER_SIZE="${POLYBAR_BORDER_SIZE:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_BORDER_SIZE)}"
export POLYBAR_PADDING_LEFT="${POLYBAR_PADDING_LEFT:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_PADDING_LEFT)}"
export POLYBAR_PADDING_RIGHT="${POLYBAR_PADDING_RIGHT:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_PADDING_RIGHT)}"
export POLYBAR_MODULE_MARGIN="${POLYBAR_MODULE_MARGIN:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_MODULE_MARGIN)}"
export POLYBAR_WORKSPACE_LABEL_PADDING="${POLYBAR_WORKSPACE_LABEL_PADDING:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_WORKSPACE_LABEL_PADDING)}"
export POLYBAR_KEYBOARD_INDICATOR_PADDING="${POLYBAR_KEYBOARD_INDICATOR_PADDING:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_KEYBOARD_INDICATOR_PADDING)}"
export POLYBAR_KEYBOARD_INDICATOR_MARGIN="${POLYBAR_KEYBOARD_INDICATOR_MARGIN:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_KEYBOARD_INDICATOR_MARGIN)}"
export POLYBAR_TITLE_MAXLEN="${POLYBAR_TITLE_MAXLEN:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_TITLE_MAXLEN)}"
export POLYBAR_FONT_0="${POLYBAR_FONT_0:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_FONT_0)}"
export POLYBAR_FONT_1="${POLYBAR_FONT_1:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_FONT_1)}"
export POLYBAR_FONT_2="${POLYBAR_FONT_2:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_FONT_2)}"
export POLYBAR_TRAY_MARGIN="${POLYBAR_TRAY_MARGIN:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_TRAY_MARGIN)}"
export POLYBAR_TRAY_PADDING="${POLYBAR_TRAY_PADDING:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_TRAY_PADDING)}"
export POLYBAR_TRAY_SPACING="${POLYBAR_TRAY_SPACING:-$(dotfiles_ui_resolved_value DOTFILES_UI_POLYBAR_TRAY_SPACING)}"

monitor_layouts() {
  xrandr --query |
    awk '
      function round(value) {
        return int(value + 0.5)
      }

      / connected/ {
        name = $1
        width = 0
        mm_width = 0

        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]+x[0-9]+\+/) {
            split($i, geometry, /x|\+/)
            width = geometry[1]
          }

          if ($i ~ /^[0-9]+mm$/ && $(i + 1) == "x" && $(i + 2) ~ /^[0-9]+mm$/) {
            mm_width = $i
            sub(/mm$/, "", mm_width)
          }
        }

        dpi = 96
        if (width > 0 && mm_width > 0) {
          dpi = round(width * 25.4 / mm_width)
        }

        print name, dpi
      }
    '
}

# Always hard-relaunch so Polybar receives the current exported size variables.
polybar-msg cmd quit >/dev/null 2>&1 || killall -q polybar

# Wait until the processes have been shut down
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 1; done

# Launch a bar on each connected monitor
if command -v xrandr >/dev/null 2>&1; then
  launched=false
  while read -r m dpi; do
    launched=true
    MONITOR="$m" POLYBAR_DPI="${POLYBAR_DPI:-$dpi}" polybar --reload "$BAR_NAME" &
  done < <(monitor_layouts)

  if [[ "$launched" == false ]]; then
    POLYBAR_DPI="${POLYBAR_DPI:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_DPI)}" polybar --reload "$BAR_NAME" &
  fi
else
  POLYBAR_DPI="${POLYBAR_DPI:-$(dotfiles_ui_resolved_int DOTFILES_UI_POLYBAR_DPI)}" polybar --reload "$BAR_NAME" &
fi

wait
