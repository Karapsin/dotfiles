#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
old_binary="$cache_dir/bluetooth-tray-left-click"
old_pid_file="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-bluetooth-tray-left-click.pid"

if [[ -r "$old_pid_file" ]]; then
  old_pid="$(cat "$old_pid_file" 2>/dev/null || true)"
  old_cmdline=""
  if [[ "$old_pid" =~ ^[0-9]+$ && -r "/proc/$old_pid/cmdline" ]]; then
    old_cmdline="$(tr '\0' ' ' <"/proc/$old_pid/cmdline")"
  fi

  if [[ "$old_cmdline" == "$old_binary"* ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi

  rm -f "$old_pid_file"
fi

exec "$script_dir/close-popups-on-outside-click.sh"
