#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, date
from pathlib import Path

HOME = Path.home()
BASE = HOME / ".wallpapers"
THEMES_DIR = BASE / "themes"
STATE_DIR = BASE / "state"
STATE_FILE = STATE_DIR / "state.json"
CURRENT = BASE / "current_wallpaper.png"

PERIODS = ("night", "morning", "day", "evening")
IMG_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}

@dataclass
class State:
    day: str
    theme: str
    last: dict

def period_now(now: datetime) -> str:
    h = now.hour
    if 0 <= h < 7:
        return "night"
    if 7 <= h < 12:
        return "morning"
    if 12 <= h < 18:
        return "day"
    return "evening"

def list_themes() -> list[Path]:
    if not THEMES_DIR.is_dir():
        return []
    themes = []
    for d in THEMES_DIR.iterdir():
        if not d.is_dir():
            continue
        if all((d / p).is_dir() for p in PERIODS):
            themes.append(d)
    return sorted(themes)

def list_images(folder: Path) -> list[Path]:
    imgs = [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in IMG_EXTS]
    return imgs

def load_state(today: str) -> State | None:
    if not STATE_FILE.exists():
        return None
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if data.get("day") != today:
            return None
        return State(day=data["day"], theme=data["theme"], last=data.get("last", {}))
    except Exception:
        return None

def save_state(st: State) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps({"day": st.day, "theme": st.theme, "last": st.last}, ensure_ascii=False, indent=2),
                          encoding="utf-8")

def pick_image(imgs: list[Path], last_name: str | None) -> Path:
    if not imgs:
        raise RuntimeError("No images")
    if last_name and len(imgs) > 1:
        filtered = [p for p in imgs if p.name != last_name]
        if filtered:
            return random.choice(filtered)
    return random.choice(imgs)

def run(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=False)
    except FileNotFoundError:
        pass


def has_usable_x11_session() -> bool:
    display = os.environ.get("DISPLAY")
    xauthority = os.environ.get("XAUTHORITY")
    if not display or not xauthority:
        return False
    if not Path(xauthority).exists():
        return False
    try:
        result = subprocess.run(
            ["xset", "q"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def apply_wallpaper(image: Path) -> None:
    x11_ready = has_usable_x11_session()

    # betterlockscreen shells out to X11 tools; skip it until the session is ready.
    if x11_ready:
        run(["betterlockscreen", "-u", str(image)])
        run(["feh", "--no-fehbg", "--bg-fill", str(image)])
    else:
        print("[wallpapers] X11 session not ready; updated current file only")


def choose_wallpaper(now: datetime) -> tuple[State, str, Path]:
    today = now.date().isoformat()
    per = period_now(now)

    themes = list_themes()
    if not themes:
        raise RuntimeError(
            f"No themes found in {THEMES_DIR} (expected themes/<name>/{'/'.join(PERIODS)}/...)"
        )

    st = load_state(today)
    if st is None:
        chosen_theme = random.choice(themes).name
        st = State(day=today, theme=chosen_theme, last={})

    theme_dir = THEMES_DIR / st.theme
    if not theme_dir.is_dir():
        theme_dir = random.choice(themes)
        st.theme = theme_dir.name

    folder = theme_dir / per
    imgs = list_images(folder)
    if not imgs:
        raise RuntimeError(f"No images in {folder}")

    chosen = pick_image(imgs, st.last.get(per))
    return st, per, chosen


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Rotate and apply wallpapers")
    parser.add_argument(
        "--apply-current",
        action="store_true",
        help="apply the current wallpaper file without rotating to a new image",
    )
    return parser

def main() -> int:
    args = build_parser().parse_args()
    now = datetime.now()

    if args.apply_current and CURRENT.exists():
        apply_wallpaper(CURRENT)
        print(f"[wallpapers] applied current wallpaper {CURRENT.name}")
        return 0
    if args.apply_current:
        print("[wallpapers] current wallpaper missing; rotating now")

    try:
        st, per, chosen = choose_wallpaper(now)
    except RuntimeError as exc:
        print(f"[wallpapers] {exc}")
        return 1

    BASE.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(chosen, CURRENT)
    st.last[per] = chosen.name
    save_state(st)
    apply_wallpaper(CURRENT)

    print(f"[wallpapers] theme={st.theme} period={per} image={chosen.name}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
