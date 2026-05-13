#!/usr/bin/env bash

BAR_NAME="example"

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

# If we were called with "restart", try a clean in-place restart via IPC.
# Falls back to full relaunch if restart fails (e.g., no bar running or IPC off).
if [[ "$1" == "restart" ]]; then
  if polybar-msg cmd restart >/dev/null 2>&1; then
    exit 0
  fi
  # else: continue to hard-relaunch below
fi

# Try to gracefully quit any existing bars via IPC; if that fails, kill them.
polybar-msg cmd quit >/dev/null 2>&1 || killall -q polybar

# Wait until the processes have been shut down
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 1; done

# Launch a bar on each connected monitor
if command -v xrandr >/dev/null 2>&1; then
  launched=false
  while read -r m dpi; do
    launched=true
    MONITOR="$m" POLYBAR_DPI="$dpi" polybar --reload "$BAR_NAME" &
  done < <(monitor_layouts)

  if [[ "$launched" == false ]]; then
    polybar --reload "$BAR_NAME" &
  fi
else
  polybar --reload "$BAR_NAME" &
fi

wait
