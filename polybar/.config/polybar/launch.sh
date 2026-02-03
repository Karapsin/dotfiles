#!/usr/bin/env bash

BAR_NAME="example"

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
  for m in $(xrandr --query | awk '/ connected/ {print $1}'); do
    MONITOR="$m" polybar --reload "$BAR_NAME" &
  done
else
  polybar --reload "$BAR_NAME" &
fi

wait
