#!/bin/sh

set -eu

i3_dir=${0%/*}
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
pid_file="$runtime_dir/blueman-placement-watch.pid"

pid_matches_this_script() {
  pid=$1

  [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline" | grep -F "$i3_dir/blueman-placement-watch.sh" >/dev/null 2>&1
}

if [ -r "$pid_file" ]; then
  old_pid=$(cat "$pid_file" 2>/dev/null || true)
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null && pid_matches_this_script "$old_pid"; then
    exit 0
  fi
fi

printf '%s\n' "$$" >"$pid_file"
trap 'rm -f "$pid_file"' EXIT HUP INT TERM

command -v i3-msg >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ -x "$i3_dir/blueman-launch.sh" ] || exit 0

i3-msg -t subscribe -m '["window"]' |
  while IFS= read -r event; do
    printf '%s\n' "$event" |
      jq -e '(.change == "new" or .change == "title") and ((.container.window_properties.class? // "") | test("^Blueman-manager$"; "i"))' >/dev/null 2>&1 || continue

    (
      sleep 0.03
      "$i3_dir/blueman-launch.sh" --place-existing >/dev/null 2>&1
    ) &
  done
