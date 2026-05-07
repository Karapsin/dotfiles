#!/bin/sh

start_applet() {
  if pgrep -f '[b]lueman-applet' >/dev/null 2>&1; then
    return 0
  fi

  setsid -f blueman-applet >/dev/null 2>&1
}

case "$1" in
  --applet)
    start_applet
    ;;
  --manager)
    start_applet
    exec blueman-manager
    ;;
  *)
    echo "Usage: $0 --applet|--manager" >&2
    exit 2
    ;;
esac
