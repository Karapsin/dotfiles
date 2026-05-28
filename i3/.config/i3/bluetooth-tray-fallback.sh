#!/bin/sh

set -eu

pid_file="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-bluetooth-tray-fallback.pid"
manager_command="${HOME}/.config/i3/blueman-launch.sh --manager"

has_bluetooth_adapter() {
  find /sys/class/bluetooth -maxdepth 1 -name 'hci*' -print -quit 2>/dev/null | grep -q .
}

read_pid_cmdline() {
  pid=$1
  if [ -r "/proc/$pid/cmdline" ]; then
    tr '\0' ' ' <"/proc/$pid/cmdline"
  fi
}

if has_bluetooth_adapter; then
  exit 0
fi

if [ -r "$pid_file" ]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if printf '%s' "$old_pid" | grep -Eq '^[0-9]+$'; then
    old_cmdline="$(read_pid_cmdline "$old_pid" || true)"
    if printf '%s' "$old_cmdline" | grep -Fq 'yad --notification --image=blueman-tray --text=Bluetooth' && kill -0 "$old_pid" 2>/dev/null; then
      exit 0
    fi
  fi

  rm -f "$pid_file"
fi

command -v yad >/dev/null 2>&1 || exit 0

(
  printf '%s\n' "$$" >"$pid_file"
  trap 'rm -f "$pid_file"' EXIT
  exec yad \
    --notification \
    --image=blueman-tray \
    --text='Bluetooth' \
    --command="$manager_command" \
    --no-middle
)
