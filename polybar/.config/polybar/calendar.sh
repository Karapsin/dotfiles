#!/bin/sh

case "$1" in
  --popup)
    if command -v gsimplecal >/dev/null 2>&1; then
      if command -v python3 >/dev/null 2>&1 && command -v i3-msg >/dev/null 2>&1 && command -v xdotool >/dev/null 2>&1 && command -v xinput >/dev/null 2>&1; then
        geometry="$(python3 - <<'PY' 2>/dev/null
import json
import os
import subprocess
from pathlib import Path


def i3_json(*args):
    return json.loads(subprocess.check_output(("i3-msg", "-t", *args), text=True))


def clamp(value, lower, upper):
    return max(lower, min(upper, value))


try:
    workspaces = i3_json("get_workspaces")
    workspace = next((w for w in workspaces if w.get("focused")), None)
    if not workspace:
        raise SystemExit

    rect = workspace["rect"]
    output_rect = rect
    for output in i3_json("get_outputs"):
        if output.get("name") == workspace.get("output"):
            output_rect = output.get("rect", rect)
            break

    width = clamp(round(rect["width"] * 0.091), 232, 340)
    height = clamp(round(rect["height"] * 0.122), 172, 260)
    margin = clamp(round(rect["width"] * 0.006), 12, 24)
    gap = clamp(round(rect["height"] * 0.006), 8, 16)

    x = rect["x"] + rect["width"] - width - margin
    y = rect["y"] + rect["height"] - height - gap

    config_home = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "gsimplecal-polybar"
    config_dir = config_home / "gsimplecal"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "config").write_text(
        "\n".join(
            (
                "show_calendar = 1",
                "show_timezones = 0",
                "mark_today = 1",
                "show_week_numbers = 0",
                "close_on_unfocus = 0",
                "close_on_mouseleave = 0",
                "mainwindow_decorated = 0",
                "mainwindow_keep_above = 1",
                "mainwindow_sticky = 0",
                "mainwindow_skip_taskbar = 1",
                "mainwindow_resizable = 0",
                "mainwindow_position = none",
                "mainwindow_xoffset = 0",
                "mainwindow_yoffset = 0",
                "",
            )
        )
    )

    print(
        config_home,
        width,
        height,
        x,
        y,
        output_rect["x"],
        output_rect["y"],
        output_rect["width"],
        output_rect["height"],
    )
except Exception:
    raise SystemExit(1)
PY
)"
        if [ -n "$geometry" ]; then
          set -- $geometry
          config_home=$1
          width=$2
          height=$3
          pos_x=$4
          pos_y=$5
          output_x=$6
          output_y=$7
          output_width=$8
          output_height=$9

          if pgrep -x gsimplecal >/dev/null 2>&1; then
            pkill -x gsimplecal >/dev/null 2>&1
            exit 0
          fi

          setsid env XDG_CONFIG_HOME="$config_home" gsimplecal >/dev/null 2>&1 &

          setsid python3 - "$config_home" "$width" "$height" "$pos_x" "$pos_y" "$output_x" "$output_y" "$output_width" "$output_height" <<'PY' >/dev/null 2>&1 &
import json
import os
import select
import shutil
import subprocess
import sys
import time


def i3_json(*args):
    return json.loads(subprocess.check_output(("i3-msg", "-t", *args), text=True))


def find_gsimplecal(node):
    props = node.get("window_properties") or {}
    if props.get("class") == "Gsimplecal":
        return node

    for group in ("nodes", "floating_nodes"):
        for child in node.get(group, []):
            found = find_gsimplecal(child)
            if found:
                return found

    return None


try:
    config_home, width, height, x, y, output_x, output_y, output_width, output_height = sys.argv[1:10]

    window = None
    for _ in range(20):
        window = find_gsimplecal(i3_json("get_tree"))
        if window:
            break
        time.sleep(0.05)

    if not window:
        raise SystemExit

    subprocess.run(
        (
            "i3-msg",
            f'[con_id="{window["id"]}"] floating enable, border none, '
            f"resize set {width} px {height} px, "
            f"move absolute position {x} px {y} px, "
            "move to workspace current, focus",
        ),
        check=False,
    )
    if not window.get("window"):
        raise SystemExit

    x_window = str(window["window"])
    subprocess.run(("xdotool", "windowactivate", "--sync", x_window), check=False)
    subprocess.run(("xdotool", "windowraise", x_window), check=False)

    left = int(x)
    top = int(y)
    right = left + int(width)
    bottom = top + int(height)

    def pointer_position():
        values = {}
        output = subprocess.check_output(("xdotool", "getmouselocation", "--shell"), text=True)
        for line in output.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value

        return int(values["X"]), int(values["Y"])

    def pointer_inside_calendar():
        pointer_x, pointer_y = pointer_position()
        return left <= pointer_x <= right and top <= pointer_y <= bottom

    def calendar_window_exists():
        return subprocess.run(
            ("xdotool", "getwindowname", x_window),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0

    xinput_command = ("xinput", "test-xi2", "--root")
    if shutil.which("stdbuf"):
        xinput_command = ("stdbuf", "-oL", "-eL", *xinput_command)

    xinput = subprocess.Popen(
        xinput_command,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=1,
        text=True,
    )

    armed = False
    arm_after = time.monotonic() + 0.08
    last_window_check = time.monotonic()
    while True:
        ready, _, _ = select.select((xinput.stdout,), (), (), 0.25)
        now = time.monotonic()
        if not ready:
            if now - last_window_check >= 0.75:
                if not calendar_window_exists():
                    break
                last_window_check = now
            continue

        line = xinput.stdout.readline()
        if not line:
            break

        now = time.monotonic()
        if not armed and (now >= arm_after or "RawButtonRelease" in line):
            armed = True

        if armed and "RawButtonPress" in line and not pointer_inside_calendar():
            subprocess.run(("xdotool", "windowunmap", x_window, "windowclose", x_window), check=False)
            break

        if now - last_window_check < 0.75:
            continue

        if not calendar_window_exists():
            break
        last_window_check = now

    xinput.terminate()
except Exception:
    pass
PY
          exit 0
        fi
      fi

      exec gsimplecal
    fi

    notify-send "Calendar unavailable" "Install gsimplecal to use the Polybar datetime calendar."
    exit 1
    ;;
  *)
    date +"%Y-%m-%d %H:%M:%S"
    ;;
esac
