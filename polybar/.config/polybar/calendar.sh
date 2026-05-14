#!/bin/sh

case "$1" in
  --popup)
    config_home="${XDG_RUNTIME_DIR:-/tmp}/gsimplecal-polybar"
    outside_close_file="$config_home/outside-close"
    popup_pid_file="$config_home/popup.pid"
    script_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
    calendar_popup="$(dirname "$script_path")/calendar_popup.py"

    if [ -f "$popup_pid_file" ]; then
      popup_pid="$(sed -n '1p' "$popup_pid_file" 2>/dev/null || true)"
      case "$popup_pid" in
        ''|*[!0-9]*)
          rm -f "$popup_pid_file"
          ;;
        *)
          if kill -0 "$popup_pid" 2>/dev/null; then
            kill "$popup_pid" 2>/dev/null || true
            rm -f "$popup_pid_file"
            exit 0
          fi
          rm -f "$popup_pid_file"
          ;;
      esac
    fi

    if pgrep -x gsimplecal >/dev/null 2>&1; then
      pkill -x gsimplecal >/dev/null 2>&1
      exit 0
    fi

    if command -v python3 >/dev/null 2>&1 && [ -f "$outside_close_file" ] && python3 - "$outside_close_file" <<'PY'
import os
import sys
import time

try:
    age = time.time() - os.path.getmtime(sys.argv[1])
except OSError:
    raise SystemExit(1)

raise SystemExit(0 if age < 0.75 else 1)
PY
    then
      exit 0
    fi

    if command -v gsimplecal >/dev/null 2>&1 || [ -x "$calendar_popup" ]; then
      if command -v python3 >/dev/null 2>&1 && command -v i3-msg >/dev/null 2>&1 && command -v xdotool >/dev/null 2>&1 && command -v xinput >/dev/null 2>&1; then
        geometry="$(POLYBAR_CALENDAR_SCRIPT="$script_path" python3 - <<'PY' 2>/dev/null
import json
import os
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


def i3_json(*args):
    return json.loads(subprocess.check_output(("i3-msg", "-t", *args), text=True))


def pointer_position(rect):
    try:
        values = {}
        output = subprocess.check_output(("xdotool", "getmouselocation", "--shell"), text=True)
        for line in output.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value

        return int(values["X"]), int(values["Y"])
    except Exception:
        return rect["x"] + rect["width"], rect["y"] + rect["height"]


def estimated_size(rect, state_file):
    for path in state_file:
        try:
            cached = json.loads(path.read_text())
            width = int(cached.get("width", 0))
            height = int(cached.get("height", 0))
            if 0 < width < rect["width"] and 0 < height < rect["height"]:
                return width, height
        except Exception:
            pass

    return round(rect["width"] * 0.092), round(rect["height"] * 0.124)


def safe_name(value):
    return "".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in value or "default")


def positive_int(value, default):
    try:
        result = int(value)
        return result if result > 0 else default
    except (TypeError, ValueError):
        return default


def output_dpi(output_name):
    configured = positive_int(os.environ.get("POLYBAR_DPI"), 0)
    if configured:
        return configured

    if not output_name or not shutil.which("xrandr"):
        return 96

    try:
        output = subprocess.check_output(
            ("xrandr", "--query"),
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return 96

    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 2 or fields[0] != output_name or fields[1] != "connected":
            continue

        width = 0
        mm_width = 0
        for index, field in enumerate(fields):
            if "x" in field and "+" in field:
                try:
                    width = int(field.split("x", 1)[0])
                except ValueError:
                    pass

            if (
                field.endswith("mm")
                and index + 2 < len(fields)
                and fields[index + 1] == "x"
                and fields[index + 2].endswith("mm")
            ):
                try:
                    mm_width = int(field[:-2])
                except ValueError:
                    pass

        if width > 0 and mm_width > 0:
            return round(width * 25.4 / mm_width)

    return 96


def polybar_font_description():
    font = os.environ.get(
        "POLYBAR_FONT_0",
        "Noto Sans Mono,Liberation Mono,DejaVu Sans Mono:size=11;2",
    )
    family, _, options = font.partition(":")
    family = family.split(",", 1)[0].strip() or "monospace"
    size = "11"
    for option in options.split(":"):
        if option.startswith("size="):
            size = option.split("=", 1)[1].split(";", 1)[0]
            break

    return f"{family} {size}"


def adaptive_ui_metrics(rect, dpi):
    width = max(1, int(rect.get("width") or 3840))
    height = max(1, int(rect.get("height") or 2160))
    scale = min(width / 3840, height / 2160)
    scale = max(0.75, min(scale, 1.8))

    if dpi > 96:
        scale = max(scale, min(dpi / 96, 1.8))

    return {
        "@font_size_px@": str(max(10, round(13 * scale))),
        "@border_width_px@": str(max(1, round(scale))),
    }


def render_gtk_css(css, rect, dpi):
    for placeholder, value in adaptive_ui_metrics(rect, dpi).items():
        css = css.replace(placeholder, value)

    return css


def ensure_monday_locale(config_home):
    locale_dir = config_home / "locale"
    locale_name = "en_GB.UTF-8"
    if (locale_dir / locale_name / "LC_TIME").is_file():
        return

    if not shutil.which("localedef"):
        return

    locale_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ("localedef", "--no-archive", "-i", "en_GB", "-f", "UTF-8", str(locale_dir / locale_name)),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def measure_text_width(text, rect, dpi):
    fallback_char_width = max(1, round(rect["height"] * 0.007))
    fallback = len(text) * fallback_char_width
    if not shutil.which("pango-view") or not shutil.which("identify"):
        return fallback

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(prefix="polybar-calendar-", suffix=".png", delete=False) as temp:
            temp_path = temp.name

        subprocess.run(
            (
                "pango-view",
                "--no-display",
                f"--dpi={dpi}",
                f"--font={polybar_font_description()}",
                "--margin=0",
                f"--text={text}",
                f"--output={temp_path}",
            ),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        width = int(subprocess.check_output(("identify", "-format", "%w", temp_path), text=True))
        return width if width > 0 else fallback
    except Exception:
        return fallback
    finally:
        if temp_path:
            try:
                Path(temp_path).unlink()
            except Exception:
                pass


try:
    workspaces = i3_json("get_workspaces")
    focused_workspace = next((w for w in workspaces if w.get("focused")), None)
    if not focused_workspace:
        raise SystemExit

    pointer_x, pointer_y = pointer_position(focused_workspace["rect"])
    output_name = None
    for output in i3_json("get_outputs"):
        if not output.get("active", True):
            continue

        output_rect = output.get("rect") or {}
        if (
            output_rect.get("x", 0) <= pointer_x < output_rect.get("x", 0) + output_rect.get("width", 0)
            and output_rect.get("y", 0) <= pointer_y < output_rect.get("y", 0) + output_rect.get("height", 0)
        ):
            output_name = output.get("name")
            break

    workspace = next(
        (w for w in workspaces if w.get("visible") and w.get("output") == output_name),
        focused_workspace,
    )
    rect = workspace["rect"]
    margin = round(rect["width"] * 0.006)
    gap = round(rect["height"] * 0.006)

    config_home = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "gsimplecal-polybar"
    ensure_monday_locale(config_home)
    state_file = config_home / f"last-size-{safe_name(workspace.get('output'))}.json"
    width, height = estimated_size(rect, (state_file, config_home / "last-size.json"))

    date_text = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    dpi = output_dpi(workspace.get("output") or output_name)
    date_width = measure_text_width(date_text, rect, dpi)
    char_width = max(1, round(date_width / max(1, len(date_text))))
    padding_right = int(os.environ.get("POLYBAR_PADDING_RIGHT", "1") or "1") * char_width
    date_center = rect["x"] + rect["width"] - padding_right - round(date_width / 2)

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
                "force_lang = en_GB.UTF-8",
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

    gtk_dir = config_home / "gtk-3.0"
    gtk_dir.mkdir(parents=True, exist_ok=True)
    (gtk_dir / "settings.ini").write_text(
        "\n".join(
            (
                "[Settings]",
                "gtk-application-prefer-dark-theme=1",
                "",
            )
        )
    )
    theme_css_candidates = []
    configured_theme_css = os.environ.get("GSIMPLECAL_GTK_CSS")
    if configured_theme_css:
        theme_css_candidates.append(Path(configured_theme_css).expanduser())
    theme_css_candidates.append(Path.home() / ".config" / "gsimplecal" / "gtk.css")

    script_path = os.environ.get("POLYBAR_CALENDAR_SCRIPT")
    if script_path:
        try:
            dotfiles_root = Path(script_path).expanduser().resolve().parents[3]
            theme_css_candidates.append(dotfiles_root / "gsimplecal" / ".config" / "gsimplecal" / "gtk.css")
        except IndexError:
            pass

    for theme_css in theme_css_candidates:
        if theme_css.is_file():
            (gtk_dir / "gtk.css").write_text(render_gtk_css(theme_css.read_text(), rect, dpi))
            break

    print(
        config_home,
        state_file,
        workspace.get("output", output_name or ""),
        rect["x"],
        rect["y"],
        rect["width"],
        rect["height"],
        margin,
        gap,
        date_center,
        width,
        height,
    )
except Exception:
    raise SystemExit(1)
PY
)"
        if [ -n "$geometry" ]; then
          set -- $geometry
          config_home=$1
          state_file=$2
          output_name=$3
          workspace_x=$4
          workspace_y=$5
          workspace_width=$6
          workspace_height=$7
          margin=$8
          gap=$9
          date_center=${10}
          width=${11}
          height=${12}

          locale_home="$config_home/locale"
          locale_name=en_GB.UTF-8
          if [ -x "$calendar_popup" ]; then
            if [ -f "$locale_home/$locale_name/LC_TIME" ]; then
              setsid env XDG_CONFIG_HOME="$config_home" LOCPATH="$locale_home" LC_ALL="$locale_name" LANG="$locale_name" "$calendar_popup" >/dev/null 2>&1 &
            else
              setsid env XDG_CONFIG_HOME="$config_home" "$calendar_popup" >/dev/null 2>&1 &
            fi
            printf '%s\n' "$!" > "$popup_pid_file"
          else
            if [ -f "$locale_home/$locale_name/LC_TIME" ]; then
              setsid env XDG_CONFIG_HOME="$config_home" LOCPATH="$locale_home" LC_ALL="$locale_name" LANG="$locale_name" gsimplecal >/dev/null 2>&1 &
            else
              setsid env XDG_CONFIG_HOME="$config_home" gsimplecal >/dev/null 2>&1 &
            fi
          fi

          setsid python3 - "$config_home" "$state_file" "$output_name" "$workspace_x" "$workspace_y" "$workspace_width" "$workspace_height" "$margin" "$gap" "$date_center" "$width" "$height" <<'PY' >/dev/null 2>&1 &
import json
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path


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


def centered_on(origin, size, window_size, center, margin):
    minimum = origin + margin
    maximum = origin + size - window_size - margin
    if maximum >= minimum:
        return max(minimum, min(center - round(window_size / 2), maximum))

    return origin + max(0, (size - window_size) // 2)


def read_window_rect(fallback_window):
    for _ in range(12):
        window = find_gsimplecal(i3_json("get_tree"))
        if window:
            rect = window.get("rect") or {}
            width = int(rect.get("width") or 0)
            height = int(rect.get("height") or 0)
            if width > 0 and height > 0:
                return window, rect
        time.sleep(0.04)

    return fallback_window, fallback_window.get("rect") or {}


def remember_size(state_file, width, height):
    try:
        Path(state_file).write_text(json.dumps({"width": width, "height": height}) + "\n")
    except Exception:
        pass


try:
    (
        config_home,
        state_file,
        output_name,
        workspace_x,
        workspace_y,
        workspace_width,
        workspace_height,
        margin,
        gap,
        date_center,
        width,
        height,
    ) = sys.argv[1:13]
    workspace_x = int(workspace_x)
    workspace_y = int(workspace_y)
    workspace_width = int(workspace_width)
    workspace_height = int(workspace_height)
    margin = int(margin)
    gap = int(gap)
    date_center = int(date_center)
    width = int(width)
    height = int(height)

    window = None
    for _ in range(20):
        window = find_gsimplecal(i3_json("get_tree"))
        if window:
            break
        time.sleep(0.05)

    if not window:
        raise SystemExit

    window, rect = read_window_rect(window)
    if not window.get("window"):
        raise SystemExit
    width = int(rect.get("width") or width)
    height = int(rect.get("height") or height)
    x = centered_on(workspace_x, workspace_width, width, date_center, margin)
    y = workspace_y + workspace_height - height - gap

    subprocess.run(
        (
            "i3-msg",
            f'[con_id="{window["id"]}"] '
            f"move to output {output_name}, "
            f"move absolute position {x} px {y} px, "
            "focus",
        ),
        check=False,
    )
    time.sleep(0.04)
    window, rect = read_window_rect(window)

    remember_size(
        state_file,
        int(rect.get("width") or width),
        int(rect.get("height") or height),
    )

    x_window = str(window["window"])

    left = int(rect.get("x") or x)
    top = int(rect.get("y") or y)
    right = left + int(rect.get("width") or width)
    bottom = top + int(rect.get("height") or height)

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
            try:
                (Path(config_home) / "outside-close").write_text(f"{time.time()}\n")
            except Exception:
                pass
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

      if [ -x "$calendar_popup" ]; then
        exec env XDG_CONFIG_HOME="$config_home" "$calendar_popup"
      fi

      exec gsimplecal
    fi

    notify-send "Calendar unavailable" "Install gsimplecal or PyGObject to use the Polybar datetime calendar."
    exit 1
    ;;
  *)
    date +"%Y-%m-%d %H:%M:%S"
    ;;
esac
