#!/usr/bin/env bash
set -u

terminal_cwd="${HOME:-$PWD}"

log() {
    if [ -n "${I3_TERMINAL_DEBUG_LOG:-}" ]; then
        printf '%s\n' "$*" >>"$I3_TERMINAL_DEBUG_LOG"
    fi
}

log "launch-terminal: start $*"

if alacritty msg create-window --working-directory "$terminal_cwd" "$@" >/dev/null 2>&1; then
    log "launch-terminal: used existing alacritty IPC"
    exit 0
fi

log "launch-terminal: existing alacritty IPC unavailable"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
socket="${runtime_dir}/alacritty-i3.sock"

rm -f "$socket"
alacritty --socket "$socket" --daemon >/tmp/alacritty-i3-daemon.log 2>&1 &
log "launch-terminal: started daemon socket $socket"

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if alacritty msg -s "$socket" create-window --working-directory "$terminal_cwd" "$@" >/dev/null 2>&1; then
        log "launch-terminal: used daemon IPC"
        exit 0
    fi
    sleep 0.05
done

log "launch-terminal: falling back to direct alacritty"
exec env -u ALACRITTY_SOCKET -u ALACRITTY_LOG -u ALACRITTY_WINDOW_ID alacritty --working-directory "$terminal_cwd" "$@"
