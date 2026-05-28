#!/usr/bin/env bash
set -u

terminal_cwd="${HOME:-$PWD}"
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
socket="${runtime_dir}/alacritty-i3.sock"
lock_dir="${runtime_dir}/dotfiles-i3-terminal.lock"
pid_file="$lock_dir/pid"
have_startup_lock=0

log() {
    if [ -n "${I3_TERMINAL_DEBUG_LOG:-}" ]; then
        printf '%s\n' "$*" >>"$I3_TERMINAL_DEBUG_LOG"
    fi
}

try_socket() {
    alacritty msg -s "$socket" create-window --working-directory "$terminal_cwd" "$@" >/dev/null 2>&1
}

cleanup_lock() {
    local recorded_pid

    [ "$have_startup_lock" -eq 1 ] || return 0

    if [ -r "$pid_file" ]; then
        recorded_pid="$(<"$pid_file")"
        [ "$recorded_pid" = "$$" ] || return 0
    fi

    rm -f -- "$pid_file"
    rmdir -- "$lock_dir" 2>/dev/null || true
    have_startup_lock=0
}

install_lock_traps() {
    trap cleanup_lock EXIT
    trap 'cleanup_lock; exit 0' INT TERM
}

lock_is_stale() {
    local recorded_pid

    if [ -r "$pid_file" ]; then
        recorded_pid="$(<"$pid_file")"
        if [[ "$recorded_pid" =~ ^[0-9]+$ ]] && kill -0 "$recorded_pid" 2>/dev/null; then
            return 1
        fi
    fi

    return 0
}

clear_stale_lock() {
    rm -f -- "$pid_file"
    rmdir -- "$lock_dir" 2>/dev/null || true
}

acquire_startup_lock() {
    local _attempt

    mkdir -p -- "$runtime_dir"

    for _attempt in {1..40}; do
        if mkdir -- "$lock_dir" 2>/dev/null; then
            printf '%s\n' "$$" >"$pid_file"
            have_startup_lock=1
            install_lock_traps
            return 0
        fi

        if lock_is_stale; then
            clear_stale_lock
            continue
        fi

        sleep 0.05
    done

    return 1
}

log "launch-terminal: start $*"

if try_socket "$@"; then
    log "launch-terminal: used daemon IPC $socket"
    exit 0
fi

log "launch-terminal: daemon IPC unavailable $socket"

if acquire_startup_lock; then
    if try_socket "$@"; then
        log "launch-terminal: used daemon IPC after lock $socket"
        exit 0
    fi

    rm -f -- "$socket"
    alacritty --socket "$socket" --daemon >/tmp/alacritty-i3-daemon.log 2>&1 &
    log "launch-terminal: started daemon socket $socket"

    for _attempt in {1..40}; do
        if try_socket "$@"; then
            log "launch-terminal: used daemon IPC"
            exit 0
        fi
        sleep 0.05
    done
else
    log "launch-terminal: startup lock busy $lock_dir"

    for _attempt in {1..60}; do
        if try_socket "$@"; then
            log "launch-terminal: used daemon IPC after wait"
            exit 0
        fi
        sleep 0.05
    done
fi

if [ "$have_startup_lock" -eq 1 ]; then
    cleanup_lock
fi

log "launch-terminal: falling back to direct alacritty"
exec env -u ALACRITTY_SOCKET -u ALACRITTY_LOG -u ALACRITTY_WINDOW_ID alacritty --working-directory "$terminal_cwd" "$@"
