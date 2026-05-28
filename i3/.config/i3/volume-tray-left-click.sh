#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_dir/tray-left-click.c"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
binary="$cache_dir/volume-tray-left-click"
pid_file="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-volume-tray-left-click.pid"
open_command="$HOME/.config/i3/launch-volume-control.sh"
close_command='i3-msg -q [class="^pavucontrol$"] kill'

if [[ -r "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  old_cmdline=""
  if [[ "$old_pid" =~ ^[0-9]+$ && -r "/proc/$old_pid/cmdline" ]]; then
    old_cmdline="$(tr '\0' ' ' < "/proc/$old_pid/cmdline")"
  fi

  if [[ "$old_cmdline" == "$binary"* ]] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi

  rm -f "$pid_file"
fi

mkdir -p "$cache_dir"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
  cc -O2 -Wall -Wextra "$source_file" -lX11 -o "$binary"
fi

printf '%s\n' "$$" > "$pid_file"
trap 'rm -f "$pid_file"' EXIT

exec "$binary" \
  --target-name "PulseAudio system tray" \
  --app-class "pavucontrol" \
  --open-command "$open_command" \
  --close-command "$close_command"
