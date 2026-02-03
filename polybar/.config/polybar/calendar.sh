#!/bin/sh
#
# Polybar popup calendar for i3 — bottom-right on focused output,
# touches the bar (no vertical gap), focuses on open, and closes after a short
# mouse-out delay (does NOT rely on focus/blur).
#
# Requires: yad, xdotool, (optional) i3-msg, jq

# ---------- user-tweakables ----------
BAR_HEIGHT=22
BAR_POSITION="bottom"   # "top" or "bottom"
BORDER_SIZE=1
YAD_WIDTH=222
YAD_HEIGHT=193
MARGIN=16                # horizontal margin only
TITLE="yad-calendar"
UNFOCUS_DELAY_MS=1500     # close if mouse stays outside for this many ms
POLL_MS=50               # mouse polling interval
# ------------------------------------

DATE="$(date +"%Y-%m-%d %H:%M:%S")"
have() { command -v "$1" >/dev/null 2>&1; }

pos_from_rect() {
  RX=$1 RY=$2 RW=$3 RH=$4
  POS_X=$(( RX + RW - YAD_WIDTH - BORDER_SIZE - MARGIN ))
  if [ "$BAR_POSITION" = "bottom" ]; then
    POS_Y=$(( RY + RH - YAD_HEIGHT - BAR_HEIGHT - BORDER_SIZE ))  # touch bar
  else
    POS_Y=$(( RY + BAR_HEIGHT + BORDER_SIZE ))                    # touch bar
  fi
  echo "$POS_X $POS_Y"
}

launch_yad() {
  yad --calendar --undecorated --fixed --no-buttons \
      --width="$YAD_WIDTH" --height="$YAD_HEIGHT" \
      --posx="$POS_X" --posy="$POS_Y" \
      --title="$TITLE" --borders=0 >/dev/null 2>&1 &
}

close_win() {
  WIN_ID="$1"
  # Prefer i3 kill by id; fallback to xdotool
  i3-msg "[id=$WIN_ID]" kill >/dev/null 2>&1 || xdotool windowclose "$WIN_ID" >/dev/null 2>&1
}

case "$1" in
  --popup)
    # no-op if it's already focused
    if have xdotool; then
      FOCUS_NAME="$(xdotool getwindowfocus getwindowname 2>/dev/null || true)"
      [ "$FOCUS_NAME" = "$TITLE" ] && exit 0
    fi

    POS_X="" POS_Y=""
    # 1) place on focused i3 output
    if have i3-msg && have jq; then
      set -- $(i3-msg -t get_workspaces | jq -r '.[] | select(.focused).rect | "\(.x) \(.y) \(.width) \(.height)"')
      RX=$1; RY=$2; RW=$3; RH=$4
      if [ -n "$RX" ] && [ -n "$RW" ]; then
        set -- $(pos_from_rect "$RX" "$RY" "$RW" "$RH"); POS_X=$1; POS_Y=$2
      fi
    fi
    # 2) fallback: whole display
    if [ -z "$POS_X" ] || [ -z "$POS_Y" ]; then
      if have xdotool; then eval "$(xdotool getdisplaygeometry --shell 2>/dev/null)"; fi
      : "${WIDTH:=1920}"; : "${HEIGHT:=1080}"
      if [ "$BAR_POSITION" = "bottom" ]; then
        POS_X=$(( WIDTH  - YAD_WIDTH  - BORDER_SIZE - MARGIN ))
        POS_Y=$(( HEIGHT - YAD_HEIGHT - BAR_HEIGHT - BORDER_SIZE ))
      else
        POS_X=$(( WIDTH  - YAD_WIDTH  - BORDER_SIZE - MARGIN ))
        POS_Y=$(( BAR_HEIGHT + BORDER_SIZE ))
      fi
    fi

    # Launch the calendar
    launch_yad

    # Focus/raise it immediately so it's interactive right away
    WIN_ID="$(xdotool search --sync --onlyvisible --name "$TITLE" | head -n1)"
    [ -z "$WIN_ID" ] && exit 0
    i3-msg "[id=$WIN_ID]" focus >/dev/null 2>&1
    xdotool windowactivate --sync "$WIN_ID" >/dev/null 2>&1
    xdotool windowraise "$WIN_ID" >/dev/null 2>&1

    # Poll mouse; close when cursor stays outside for UNFOCUS_DELAY_MS
    (
      outside_ms=0
      while xdotool getwindowfocus >/dev/null 2>&1; do
        # geometry (prefix to avoid clobbering POS_X/Y)
        eval "$(xdotool getwindowgeometry --shell "$WIN_ID" 2>/dev/null | sed 's/^/WG_/')" || break
        # mouse (rename vars)
        eval "$(xdotool getmouselocation --shell 2>/dev/null | sed 's/^X=/MX=/; s/^Y=/MY=/')" || break

        # inside?
        if [ "$MX" -ge "$WG_X" ] && [ "$MX" -le $((WG_X+WG_WIDTH)) ] && \
           [ "$MY" -ge "$WG_Y" ] && [ "$MY" -le $((WG_Y+WG_HEIGHT)) ]; then
          outside_ms=0
        else
          outside_ms=$(( outside_ms + POLL_MS ))
          if [ "$outside_ms" -ge "$UNFOCUS_DELAY_MS" ]; then
            close_win "$WIN_ID"
            exit 0
          fi
        fi

        # sleep for POLL_MS milliseconds
        sleep "$(awk "BEGIN{print $POLL_MS/1000}")"
      done
    ) >/dev/null 2>&1 &

    ;;
  *)
    echo "$DATE"
    ;;
esac

