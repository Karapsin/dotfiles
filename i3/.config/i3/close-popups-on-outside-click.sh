#!/usr/bin/env bash

set -euo pipefail

pid_file="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-popup-autoclose.pid"

if [[ -r "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    exit 0
  fi
fi

printf '%s\n' "$$" > "$pid_file"
trap 'rm -f "$pid_file"' EXIT

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
  ' |
  while read -r button click_x click_y; do
    [[ -n "$button" ]] || continue
    close_targets_outside_point "$click_x" "$click_y"
  done
