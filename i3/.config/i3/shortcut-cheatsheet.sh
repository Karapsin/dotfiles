#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_text=""

if command -v i3-msg >/dev/null 2>&1; then
    config_text="$(i3-msg -t get_config 2>/dev/null || true)"
fi

if [[ -z "$config_text" && -r "$script_dir/config" ]]; then
    config_text="$(<"$script_dir/config")"
elif [[ -z "$config_text" && -r "$HOME/.config/i3/config" ]]; then
    config_text="$(<"$HOME/.config/i3/config")"
fi

notify_error() {
    local message=$1

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3 shortcuts" "$message"
    else
        printf 'i3 shortcuts: %s\n' "$message" >&2
    fi
}

if [[ -z "$config_text" ]]; then
    notify_error "Could not read the current i3 config."
    exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
    notify_error "Rofi is not installed."
    exit 1
fi

SHORTCUT_COLUMN_WIDTH=43

has_binding() {
    local pattern=$1
    grep -Eq "$pattern" <<<"$config_text"
}

markup_escape() {
    local text=$1

    text=${text//&/&amp;}
    text=${text//</&lt;}
    text=${text//>/&gt;}
    text=${text//\'/&apos;}
    text=${text//\"/&quot;}
    printf '%s' "$text"
}

current_section=""
current_section_display=""
current_group_meta=""
current_group_rows=()
current_group_displays=()

flush_section() {
    local index

    [[ -n "$current_section" ]] || return 0
    [[ ${#current_group_rows[@]} -gt 0 ]] || return 0

    printf '\x1e%s\0display\x1f<span foreground="#9AA7B2" weight="bold" size="small">%s</span>\x1fnonselectable\x1ftrue\n' \
        "$current_group_meta" "$current_section_display"

    for index in "${!current_group_rows[@]}"; do
        printf '%s\0display\x1f%s\n' "${current_group_rows[$index]}" "${current_group_displays[$index]}"
    done
}

add_section() {
    flush_section

    current_section=$1
    current_section_display="$(markup_escape "$current_section")"
    current_group_meta=""
    current_group_rows=()
    current_group_displays=()
}

add_row() {
    local shortcut=$1
    local action=$2
    local row
    local shortcut_cell
    local escaped_shortcut
    local escaped_action
    local display_row

    row="$shortcut  -  $action"
    printf -v shortcut_cell ' %-*s ' "$SHORTCUT_COLUMN_WIDTH" "$shortcut"
    escaped_shortcut="$(markup_escape "$shortcut_cell")"
    escaped_action="$(markup_escape "$action")"
    display_row="<span font_family=\"monospace\" foreground=\"#E5EAF0\" background=\"#172331\" weight=\"bold\">$escaped_shortcut</span><span foreground=\"#3A78A2\"> | </span><span foreground=\"#D7DDE4\">$escaped_action</span>"
    current_group_rows+=("$row")
    current_group_displays+=("$display_row")
    current_group_meta+="${current_group_meta:+ }$row"
}

add_if() {
    local pattern=$1
    local shortcut=$2
    local action=$3

    if has_binding "$pattern"; then
        add_row "$shortcut" "$action"
    fi
}

add_if_all() {
    local shortcut=$1
    local action=$2
    shift 2

    local pattern
    for pattern in "$@"; do
        has_binding "$pattern" || return 0
    done

    add_row "$shortcut" "$action"
}

generate_rows() {
    add_section "App Shortcuts"
    add_if_all '$mod+Enter / $mod+Keypad Enter' 'Launch terminal (like Windows Terminal or Command Prompt)' \
        '^[[:space:]]*bindcode[[:space:]]+\$mod\+36[[:space:]].*launch-terminal\.sh' \
        '^[[:space:]]*bindcode[[:space:]]+\$mod\+104[[:space:]].*launch-terminal\.sh'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+d[[:space:]].*rofi[[:space:]]+-show[[:space:]]+drun' \
        '$mod+d' 'Open Rofi application launcher (like Start menu search)'
    add_if '^[[:space:]]*bind(code|sym)[[:space:]]+\$mod\+Shift\+(61|slash)[[:space:]].*shortcut-cheatsheet\.sh' \
        '$mod+Shift+/' 'Open Rofi shortcut cheat sheet'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+e[[:space:]].*nemo[[:space:]]+--no-desktop' \
        '$mod+Shift+e' 'Open Nemo file manager (like Windows File Explorer)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+n[[:space:]].*mousepad' \
        '$mod+n' 'Open Mousepad (like Windows Notepad)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+s[[:space:]].*flameshot[[:space:]]+gui' \
        '$mod+Shift+s' 'Start Flameshot screenshot selection (like Snipping Tool)'
    add_if '^[[:space:]]*bindsym[[:space:]]+Ctrl\+Shift\+l[[:space:]].*betterlockscreen[[:space:]]+-l[[:space:]]+dim' \
        'Ctrl+Shift+l' 'Lock the screen with Betterlockscreen'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+c[[:space:]].*google-chrome-dotfiles' \
        '$mod+c' 'Launch Chrome through the dotfiles wrapper'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+g[[:space:]].*steam' \
        '$mod+g' 'Launch Steam'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+t[[:space:]].*Telegram' \
        '$mod+t' 'Launch Telegram'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+v[[:space:]].*vpn-control-toggle\.sh' \
        '$mod+Shift+v' 'Toggle VPN control'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Mod1\+v[[:space:]].*pavucontrol[[:space:]]+--tab=1' \
        '$mod+Alt+v' 'Open PulseAudio volume control (like Volume Mixer)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Mod1\+b[[:space:]].*blueman-launch\.sh[[:space:]]+--manager' \
        '$mod+Alt+b' 'Open Blueman manager (like Bluetooth settings)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+t[[:space:]].*element-desktop' \
        '$mod+Shift+t' 'Launch Element'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+p[[:space:]].*positron' \
        '$mod+p' 'Launch Positron (like an RStudio or VS Code-style data IDE)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+d[[:space:]].*drawing' \
        '$mod+Shift+d' 'Launch Drawing (like Windows Paint)'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Mod1\+r[[:space:]].*rstudio' \
        '$mod+Alt+r' 'Launch RStudio'

    add_section "Polybar Shortcuts"
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+c[[:space:]].*calendar\.sh[[:space:]]+--popup' \
        '$mod+Shift+c' 'Open the Polybar calendar popup'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+p[[:space:]].*powermenu\.sh' \
        '$mod+Shift+p' 'Open the Polybar power menu'

    add_section "i3 Action Shortcuts"
    add_if_all '$mod+1 through $mod+0' 'Switch to workspace 1 through 10' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+1[[:space:]]+workspace[[:space:]]+number[[:space:]]+\$ws1' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+0[[:space:]]+workspace[[:space:]]+number[[:space:]]+\$ws10'
    add_if_all '$mod+Shift+1 through $mod+Shift+0' 'Move focused window to workspace 1 through 10' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+1[[:space:]]+move[[:space:]]+container[[:space:]]+to[[:space:]]+workspace[[:space:]]+number[[:space:]]+\$ws1' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+0[[:space:]]+move[[:space:]]+container[[:space:]]+to[[:space:]]+workspace[[:space:]]+number[[:space:]]+\$ws10'
    add_if_all '$mod+j/k/l/; or $mod+arrow keys' 'Move focus left/down/up/right' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+j[[:space:]].*focus-visual\.py[[:space:]]+left' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+Right[[:space:]].*focus-visual\.py[[:space:]]+right'
    add_if_all '$mod+Shift+j/k/l/; or $mod+Shift+arrow keys' 'Move the focused window left/down/up/right' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+j[[:space:]]+move[[:space:]]+left' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+Right[[:space:]]+move[[:space:]]+right'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+f[[:space:]]+fullscreen[[:space:]]+toggle' \
        '$mod+f' 'Toggle fullscreen'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+r[[:space:]]+mode[[:space:]]+"resize"' \
        '$mod+r' 'Enter resize mode'
    add_if_all 'resize mode: j/k/l/; or arrow keys' 'Resize the focused window' \
        '^[[:space:]]*bindsym[[:space:]]+j[[:space:]]+resize[[:space:]]+shrink[[:space:]]+width' \
        '^[[:space:]]*bindsym[[:space:]]+Right[[:space:]]+resize[[:space:]]+grow[[:space:]]+width'
    add_if_all 'resize mode: Enter, Escape, or $mod+r' 'Return to normal mode' \
        '^[[:space:]]*bindsym[[:space:]]+Return[[:space:]]+mode[[:space:]]+"default"' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+r[[:space:]]+mode[[:space:]]+"default"'
    add_if_all 'XF86AudioRaiseVolume / XF86AudioLowerVolume' 'Raise or lower volume by 5%' \
        '^[[:space:]]*bindsym[[:space:]]+XF86AudioRaiseVolume[[:space:]].*pamixer[[:space:]]+--increase[[:space:]]+5' \
        '^[[:space:]]*bindsym[[:space:]]+XF86AudioLowerVolume[[:space:]].*pamixer[[:space:]]+--decrease[[:space:]]+5'
    add_if '^[[:space:]]*bindsym[[:space:]]+XF86AudioMute[[:space:]].*pamixer[[:space:]]+--toggle-mute' \
        'XF86AudioMute' 'Toggle audio mute'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+r[[:space:]]+restart' \
        '$mod+Shift+r' 'Restart i3'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+q[[:space:]]+kill' \
        '$mod+Shift+q' 'Close the focused window'
    add_if_all '$mod+h / $mod+v' 'Split next container vertically or horizontally' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+h[[:space:]]+split[[:space:]]+v' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+v[[:space:]]+split[[:space:]]+h'
    add_if_all '$mod+s / $mod+w / $mod+e' 'Use stacking, tabbed, or split layout' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+s[[:space:]]+layout[[:space:]]+stacking' \
        '^[[:space:]]*bindsym[[:space:]]+\$mod\+e[[:space:]]+layout[[:space:]]+toggle[[:space:]]+split'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+Shift\+space[[:space:]]+floating[[:space:]]+toggle' \
        '$mod+Shift+Space' 'Toggle floating mode'
    add_if '^[[:space:]]*bindsym[[:space:]]+\$mod\+a[[:space:]]+focus[[:space:]]+parent' \
        '$mod+a' 'Focus parent container'

    flush_section
}

generate_rows \
    | rofi -dmenu -i -no-custom -no-sort -markup-rows -p "i3 shortcuts" -theme-str 'window { width: 900px; } listview { lines: 24; }' \
    >/dev/null
