#!/usr/bin/env bash

set -euo pipefail

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
state_dir="$state_home/dotfiles"
disabled_file="$state_dir/i3-auto-split.disabled"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
user_id="$(id -u 2>/dev/null || printf unknown)"
lock_dir="$runtime_dir/dotfiles-i3-auto-split-${user_id}.lock"
pid_file="$lock_dir/pid"

usage() {
  cat <<'EOF'
Usage: auto-split.sh --daemon|--toggle|--apply

Automatically chooses the next i3 split direction from the focused tiled
container shape. The feature is enabled by default; --toggle persists an
off-state in XDG state.
EOF
}

notify_status() {
  local message=$1

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "i3 automatic tiling" "$message" >/dev/null 2>&1 || true
  else
    printf 'i3 automatic tiling: %s\n' "$message"
  fi
}

is_enabled() {
  [[ ! -e "$disabled_file" ]]
}

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
}

apply_smart_split() {
  local focused
  local width
  local height
  local split_direction

  is_enabled || return 0
  command -v i3-msg >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  focused="$(
    i3-msg -t get_tree 2>/dev/null | jq -r '
      def nodes($ancestor_layouts):
        . as $node |
        {
          focused: $node.focused,
          floating: $node.floating,
          scratchpad_state: $node.scratchpad_state,
          fullscreen_mode: $node.fullscreen_mode,
          rect: $node.rect,
          ancestor_layouts: $ancestor_layouts
        },
        ($node.nodes[]? | nodes($ancestor_layouts + [($node.layout // "")])),
        ($node.floating_nodes[]? | nodes($ancestor_layouts + ["floating"]));

      nodes([])
      | select(.focused == true)
      | select(((.floating // "auto_off") | test("_on$")) | not)
      | select((.scratchpad_state // "none") == "none")
      | select((.fullscreen_mode // 0) == 0)
      | select((.ancestor_layouts | index("floating")) | not)
      | select((.ancestor_layouts | index("stacked")) | not)
      | select((.ancestor_layouts | index("tabbed")) | not)
      | select((.rect.width // 0) > 0 and (.rect.height // 0) > 0)
      | "\(.rect.width) \(.rect.height)"
    ' 2>/dev/null || true
  )"

  [[ -n "$focused" ]] || return 0
  read -r width height <<< "$focused"
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || return 0

  if ((width >= height)); then
    split_direction=h
  else
    split_direction=v
  fi

  i3-msg -q "split $split_direction" >/dev/null 2>&1 || true
}

toggle_auto_split() {
  mkdir -p -- "$state_dir"

  if is_enabled; then
    : > "$disabled_file"
    notify_status "Off"
  else
    rm -f -- "$disabled_file"
    notify_status "On"
    apply_smart_split
  fi
}

process_is_auto_split() {
  local pid=$1
  local cmdline

  [[ -r "/proc/$pid/cmdline" ]] || return 1
  cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
  [[ "$cmdline" == *"auto-split.sh"* ]]
}

cleanup_lock() {
  local recorded_pid

  if [[ -r "$pid_file" ]]; then
    recorded_pid="$(<"$pid_file")"
    [[ "$recorded_pid" == "$$" ]] || return 0
  fi

  rm -f -- "$pid_file"
  rmdir -- "$lock_dir" 2>/dev/null || true
}

install_lock_traps() {
  trap cleanup_lock EXIT
  trap 'cleanup_lock; exit 0' INT TERM
}

acquire_daemon_lock() {
  local old_pid=""
  local attempt

  mkdir -p -- "$runtime_dir"

  if mkdir -- "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    install_lock_traps
    return 0
  fi

  if [[ -r "$pid_file" ]]; then
    old_pid="$(<"$pid_file")"
  fi

  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null && process_is_auto_split "$old_pid"; then
    kill "$old_pid" 2>/dev/null || true
    for attempt in {1..20}; do
      kill -0 "$old_pid" 2>/dev/null || break
      sleep 0.05
    done
  fi

  rm -f -- "$pid_file"
  rmdir -- "$lock_dir" 2>/dev/null || true

  if mkdir -- "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$pid_file"
    install_lock_traps
    return 0
  fi

  exit 0
}

run_daemon() {
  require_command i3-msg
  require_command jq
  acquire_daemon_lock
  apply_smart_split

  i3-msg -t subscribe -m '["window","workspace"]' 2>/dev/null |
    while IFS= read -r _event; do
      apply_smart_split
    done
}

case "${1:-}" in
  --daemon)
    run_daemon
    ;;
  --toggle)
    toggle_auto_split
    ;;
  --apply)
    apply_smart_split
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
