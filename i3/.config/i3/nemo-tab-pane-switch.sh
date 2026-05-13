#!/bin/sh

pid_file="${XDG_RUNTIME_DIR:-/tmp}/nemo-tab-pane-switch-xbindkeys.pid"
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/xbindkeys/nemo-tab-pane-switch"

have_commands() {
  command -v xdotool >/dev/null 2>&1 &&
    command -v xbindkeys >/dev/null 2>&1
}

read_pid() {
  [ -f "$pid_file" ] || return 1
  read -r pid < "$pid_file" || return 1
  [ -n "$pid" ] || return 1
}

binding_is_running() {
  read_pid || return 1
  kill -0 "$pid" 2>/dev/null
}

active_window_is_nemo() {
  class=$(xdotool getactivewindow getwindowclassname 2>/dev/null || true)
  [ "$class" = "Nemo" ] || [ "$class" = "nemo" ]
}

start_binding() {
  binding_is_running && return 0
  [ -f "$config_file" ] || return 0

  xbindkeys -n -f "$config_file" >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$pid_file"
}

stop_binding() {
  if binding_is_running; then
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

sync_binding() {
  if active_window_is_nemo; then
    start_binding
  else
    stop_binding
  fi
}

have_commands || exit 0

trap 'stop_binding; exit 0' INT TERM HUP EXIT

while :; do
  sync_binding
  sleep 0.2
done
