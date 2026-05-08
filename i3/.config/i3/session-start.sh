#!/bin/sh

user_id=$(id -u)
i3_dir="${0%/*}"

if command -v xrdb >/dev/null 2>&1 && [ -f "$HOME/.Xresources" ]; then
  xrdb -merge "$HOME/.Xresources" >/dev/null 2>&1 || true
fi

start_detached() {
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$@" >/dev/null 2>&1
  else
    "$@" >/dev/null 2>&1 &
  fi
}

start_once_name() {
  process_name=$1
  shift

  command -v "$1" >/dev/null 2>&1 || return 0
  pgrep -u "$user_id" -x "$process_name" >/dev/null 2>&1 && return 0

  start_detached "$@"
}

start_once_pattern() {
  process_pattern=$1
  shift

  command -v "$1" >/dev/null 2>&1 || return 0
  pgrep -u "$user_id" -f "$process_pattern" >/dev/null 2>&1 && return 0

  start_detached "$@"
}

if command -v python3 >/dev/null 2>&1 && [ -f "$HOME/.wallpapers/bin/wallpaper_cycle.py" ]; then
  python3 "$HOME/.wallpapers/bin/wallpaper_cycle.py" --apply-current >/dev/null 2>&1 &
fi

start_once_pattern '[l]xqt-policykit-agent' /usr/bin/lxqt-policykit-agent
start_once_name nm-applet nm-applet
start_once_name pasystray pasystray
start_once_name dunst dunst

if command -v xset >/dev/null 2>&1 && command -v xss-lock >/dev/null 2>&1 && command -v betterlockscreen >/dev/null 2>&1; then
  xset s 3600 3600 >/dev/null 2>&1 || true
  start_once_name xss-lock xss-lock -- betterlockscreen -l
fi

if command -v picom >/dev/null 2>&1 && ! pgrep -u "$user_id" -x picom >/dev/null 2>&1; then
  if [ -f "$HOME/.config/picom/picom.conf" ]; then
    picom --daemon --config "$HOME/.config/picom/picom.conf" >/dev/null 2>&1 || true
  else
    picom --daemon --no-fading-openclose >/dev/null 2>&1 || true
  fi
fi

if [ -x "$i3_dir/blueman-launch.sh" ]; then
  "$i3_dir/blueman-launch.sh" --applet >/dev/null 2>&1
fi
