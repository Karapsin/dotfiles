#!/usr/bin/env bash
set -euo pipefail

# Detect internal panel and one external (prefer HDMI, then DP)
INTERNAL=$(xrandr --query | awk '/ connected/{print $1}' | grep -E '^eDP|^LVDS' | head -n1 || true)
EXT_HDMI=$(xrandr --query | awk '/ connected/{print $1}' | grep -E '^HDMI' | head -n1 || true)
EXT_DP=$(xrandr --query | awk '/ connected/{print $1}' | grep -E '^DP' | head -n1 || true)
EXTERNAL=${EXT_HDMI:-${EXT_DP:-}}

# Always enable internal and make it primary 1920x1080 (change if you want)
if [[ -n "${INTERNAL:-}" ]]; then
  xrandr --output "$INTERNAL" --auto --primary
fi

# Kill a specific troublesome output if you used to force it off
# (Only if it exists in this setup)
if xrandr --query | awk '/ connected/{print $1}' | grep -q '^DP-1-1$'; then
  xrandr --output DP-1-1 --off || true
fi

if [[ -n "${EXTERNAL:-}" ]]; then
  # Try your preferred 2560x1440@144 if supported; otherwise just --auto
  if xrandr | grep -A1 "^$EXTERNAL connected" | grep -q '2560x1440 .*144\.00'; then
    xrandr --output "$EXTERNAL" --mode 2560x1440 --rate 144 --right-of "$INTERNAL"
  else
    xrandr --output "$EXTERNAL" --auto --right-of "$INTERNAL"
  fi
fi

# Workspace placement (adjust numbers as you like)
# Move WS1 to internal, WS2 to external if present
if [[ -n "${INTERNAL:-}" ]]; then
  i3-msg "workspace 1; move workspace to output $INTERNAL" >/dev/null
fi
if [[ -n "${EXTERNAL:-}" ]]; then
  i3-msg "workspace 2; move workspace to output $EXTERNAL" >/dev/null
fi

# Focus back to WS1
i3-msg 'workspace 1' >/dev/null
