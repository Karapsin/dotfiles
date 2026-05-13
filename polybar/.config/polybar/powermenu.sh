#!/usr/bin/env bash

set -euo pipefail

reboot_label=" reboot"
poweroff_label=" poweroff"
logout_label="logout"

dpi="${POLYBAR_DPI:-96}"
case "$dpi" in
  '' | *[!0-9]*)
    dpi=96
    ;;
esac

font_size=$(((11 * dpi + 48) / 96))
if ((font_size < 11)); then
  font_size=11
fi

theme="
window {
  font: \"Noto Sans Mono $font_size\";
  location: south west;
  anchor: south west;
  width: calc( 4% max 15ch min 16ch );
  x-offset: 0.35%;
  y-offset: -3.2%;
}

mainbox {
  padding: 0.25em;
  spacing: 0.25em;
}

inputbar {
  enabled: false;
}

listview {
  lines: 3;
  spacing: 0.15em;
}

element {
  children: [ element-text ];
  padding: 0.25em 0.25em;
  spacing: 0;
}
"

choice="$(
  printf '%s\n' "$reboot_label" "$poweroff_label" "$logout_label" |
    rofi \
      -dmenu \
      -no-custom \
      -no-sort \
      -no-show-icons \
      -p "" \
      -l 3 \
      -theme-str "$theme"
)" || exit 0

case "$choice" in
  "$reboot_label")
    exec systemctl reboot
    ;;
  "$poweroff_label")
    exec systemctl poweroff
    ;;
  "$logout_label")
    exec i3-msg exit
    ;;
  *)
    exit 0
    ;;
esac
