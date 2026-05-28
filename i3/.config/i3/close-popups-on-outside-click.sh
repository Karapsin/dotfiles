#!/usr/bin/env bash

set -euo pipefail

i3_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pid_file="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-popup-autoclose.pid"
current_pgid="$(ps -o pgid= -p "$$" | tr -d '[:space:]')"

read_pid_cmdline() {
  local pid=$1

  [[ -r "/proc/$pid/cmdline" ]] || return 1
  tr '\0' ' ' <"/proc/$pid/cmdline"
}

terminate_descendants() {
  local pid=$1
  local child

  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    terminate_descendants "$child"
    kill "$child" 2>/dev/null || true
  done < <(pgrep -P "$pid" 2>/dev/null || true)
}

terminate_old_listener() {
  local pid=$1
  local pgid

  [[ "$pid" =~ ^[0-9]+$ && "$pid" != "$$" ]] || return 0
  kill -0 "$pid" 2>/dev/null || return 0

  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$pgid" =~ ^[0-9]+$ && "$pgid" != "$current_pgid" ]]; then
    kill -TERM "-$pgid" 2>/dev/null || true
  else
    terminate_descendants "$pid"
    kill "$pid" 2>/dev/null || true
  fi

  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
}

if [[ -r "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  old_cmdline=""
  if [[ "$old_pid" =~ ^[0-9]+$ ]]; then
    old_cmdline="$(read_pid_cmdline "$old_pid" 2>/dev/null || true)"
  fi

  if [[ "$old_cmdline" == *"$i3_dir/close-popups-on-outside-click.sh"* ]] && kill -0 "$old_pid" 2>/dev/null; then
    terminate_old_listener "$old_pid"
  fi

  rm -f "$pid_file"
fi

while IFS= read -r old_pid; do
  old_cmdline="$(read_pid_cmdline "$old_pid" 2>/dev/null || true)"
  [[ "$old_cmdline" == *"$i3_dir/close-popups-on-outside-click.sh"* ]] || continue
  terminate_old_listener "$old_pid"
done < <(pgrep -f "$i3_dir/close-popups-on-outside-click.sh" 2>/dev/null || true)

printf '%s\n' "$$" > "$pid_file"

cleanup() {
  trap - EXIT HUP INT TERM
  terminate_descendants "$$"
  rm -f "$pid_file"
}

trap cleanup EXIT HUP INT TERM

read_geometry_value() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { print $2 }'
}

blueman_manager_is_open() {
  i3-msg -t get_tree |
    jq -e '.. | objects | select(.window? != null and (.window_properties.class? // "" | test("^Blueman-manager$"; "i")))' >/dev/null
}

point_is_inside_bluetooth_tray() {
  local click_x=$1
  local click_y=$2
  local window_id
  local geometry
  local window_x
  local window_y
  local window_width
  local window_height
  local window_right
  local window_bottom

  command -v xdotool >/dev/null 2>&1 || return 1

  while IFS= read -r window_id; do
    [[ -n "$window_id" ]] || continue

    geometry="$(xdotool getwindowgeometry --shell "$window_id" 2>/dev/null || true)"
    [[ -n "$geometry" ]] || continue

    window_x="$(read_geometry_value X <<<"$geometry")"
    window_y="$(read_geometry_value Y <<<"$geometry")"
    window_width="$(read_geometry_value WIDTH <<<"$geometry")"
    window_height="$(read_geometry_value HEIGHT <<<"$geometry")"
    [[ "$window_x" =~ ^-?[0-9]+$ && "$window_y" =~ ^-?[0-9]+$ && "$window_width" =~ ^[0-9]+$ && "$window_height" =~ ^[0-9]+$ ]] || continue

    window_right=$((window_x + window_width))
    window_bottom=$((window_y + window_height))
    if ((click_x >= window_x && click_x < window_right && click_y >= window_y && click_y < window_bottom)); then
      return 0
    fi
  done < <(xdotool search --class blueman-tray 2>/dev/null || true)

  return 1
}

toggle_bluetooth_manager() {
  if blueman_manager_is_open; then
    i3-msg -q '[class="^Blueman-manager$"] kill' >/dev/null 2>&1 || true
  elif [[ -x "$i3_dir/blueman-launch.sh" ]]; then
    "$i3_dir/blueman-launch.sh" --manager >/dev/null 2>&1 &
  fi
}

close_targets_outside_point() {
  local click_x=$1
  local click_y=$2
  local con_id rect_x rect_y rect_width rect_height rect_right rect_bottom

  while IFS=$'\t' read -r con_id rect_x rect_y rect_width rect_height; do
    [[ -n "$con_id" ]] || continue

    rect_right=$((rect_x + rect_width))
    rect_bottom=$((rect_y + rect_height))

    if ((click_x >= rect_x && click_x < rect_right && click_y >= rect_y && click_y < rect_bottom)); then
      continue
    fi

    i3-msg -q "[con_id=${con_id}] kill" >/dev/null 2>&1 || true
  done < <(
    i3-msg -t get_tree |
      jq -r '
        .. | objects
        | select(.window? != null)
        | select(.window_properties.class? == "pavucontrol" or .window_properties.class? == "Blueman-manager")
        | [.id, .rect.x, .rect.y, .rect.width, .rect.height]
        | @tsv
      '
  )
}

last_release_button=0
last_release_x=0
last_release_y=0
last_release_ms=0

is_duplicate_release() {
  local button=$1
  local click_x=$2
  local click_y=$3
  local now_ms

  now_ms="$(date +%s%3N)"
  if ((button == last_release_button &&
       click_x == last_release_x &&
       click_y == last_release_y &&
       now_ms - last_release_ms < 150)); then
    return 0
  fi

  last_release_button=$button
  last_release_x=$click_x
  last_release_y=$click_y
  last_release_ms=$now_ms
  return 1
}

while read -r button click_x click_y; do
  [[ -n "$button" ]] || continue
  is_duplicate_release "$button" "$click_x" "$click_y" && continue

  if ((button == 1)) && point_is_inside_bluetooth_tray "$click_x" "$click_y"; then
    toggle_bluetooth_manager
    continue
  fi

  close_targets_outside_point "$click_x" "$click_y"
done < <(
  xinput test-xi2 --root |
    awk '
      /^EVENT type [0-9]+ \(ButtonRelease\)/ {
        is_button_release = 1
        detail = 0
        next
      }

      /^EVENT type / {
        is_button_release = 0
        next
      }

      is_button_release && /^[[:space:]]*detail:/ {
        detail = $2
        next
      }

      is_button_release && /^[[:space:]]*root:/ {
        split($2, coords, "/")
        if (detail >= 1 && detail <= 3) {
          printf "%d %d %d\n", detail, coords[1], coords[2]
          fflush()
        }
        is_button_release = 0
      }
    '
)
