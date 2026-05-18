#!/usr/bin/env bash
set -euo pipefail

wallpaper="${1:-$HOME/.wallpapers/current_wallpaper.png}"

if ! command -v betterlockscreen >/dev/null 2>&1; then
  echo "Skipping betterlockscreen cache refresh: betterlockscreen is unavailable." >&2
  exit 0
fi

if [[ ! -f "$wallpaper" ]]; then
  echo "Skipping betterlockscreen cache refresh: missing wallpaper $wallpaper" >&2
  exit 0
fi

if ! betterlockscreen --quiet --update "$wallpaper" --fx dim,color --dim 45; then
  echo "Warning: betterlockscreen cache refresh failed." >&2
fi
