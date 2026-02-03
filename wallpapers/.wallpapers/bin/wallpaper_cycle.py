#!/usr/bin/env python3
from __future__ import annotations

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

def main() -> int:
    now = datetime.now()
    today = date.today().isoformat()
    per = period_now(now)

    themes = list_themes()
    if not themes:
        print(f"[wallpapers] No themes found in {THEMES_DIR} (expected themes/<name>/{'/'.join(PERIODS)}/...)")
        return 1

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
        print(f"[wallpapers] No images in {folder}")
        return 1

    chosen = pick_image(imgs, st.last.get(per))
    st.last[per] = chosen.name
    save_state(st)

    BASE.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(chosen, CURRENT)

    # Lock screen cache update (fast lock afterward)
    run(["betterlockscreen", "-u", str(CURRENT)])

    # Desktop wallpaper (X11): only if running in a session
    if os.environ.get("DISPLAY"):
        run(["feh", "--no-fehbg", "--bg-fill", str(CURRENT)])

    print(f"[wallpapers] theme={st.theme} period={per} image={chosen.name}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
