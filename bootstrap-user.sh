#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run as your normal user: ./bootstrap-user.sh [--noconfirm] [--skip-aur]"
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUR_FILE="$DOTFILES_DIR/packages/aur.txt"
STOW_FILE="$DOTFILES_DIR/packages/stow.txt"

NO_CONFIRM=0
SKIP_AUR=0

while (($#)); do
  case "$1" in
    --noconfirm)
      NO_CONFIRM=1
      ;;
    --skip-aur)
      SKIP_AUR=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

read_manifest() {
  local file=$1
  [[ -f "$file" ]] || return 0
  sed -E 's/[[:space:]]+#.*$//; s/#.*$//; /^[[:space:]]*$/d' "$file"
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

mapfile -t STOW_PACKAGES < <(read_manifest "$STOW_FILE")
mapfile -t AUR_PACKAGES < <(read_manifest "$AUR_FILE")

if [[ ${#STOW_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty stow manifest: $STOW_FILE" >&2
  exit 1
fi

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  echo "Bootstrapping yay..."
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  pushd "$tmpdir/yay" >/dev/null
  if [[ $NO_CONFIRM -eq 1 ]]; then
    makepkg -si --needed --noconfirm
  else
    makepkg -si --needed
  fi
  popd >/dev/null
  trap - RETURN
  rm -rf "$tmpdir"
}

require_command stow

echo "[1/5] Pulling Git LFS assets (if available)..."
if command -v git-lfs >/dev/null 2>&1; then
  git -C "$DOTFILES_DIR" lfs pull || true
fi

echo "[2/5] Deploying stow packages..."
stow -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"

EXPECTED_EXECUTABLES=(
  "$HOME/.config/i3/blueman-launch.sh"
  "$HOME/.config/i3/session-start.sh"
  "$HOME/.config/i3/vpn-control-toggle.sh"
  "$HOME/.config/polybar/calendar.sh"
  "$HOME/.config/polybar/launch.sh"
  "$HOME/.local/bin/load-xkb-shortcuts"
)

missing_executable=0
for executable in "${EXPECTED_EXECUTABLES[@]}"; do
  if [[ -e "$executable" ]]; then
    chmod +x "$executable"
  else
    echo "Expected script missing after stow: $executable" >&2
    missing_executable=1
  fi
done

if [[ $missing_executable -ne 0 ]]; then
  exit 1
fi

if [[ $SKIP_AUR -eq 0 && ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  echo "[3/5] Installing AUR packages..."
  ensure_yay
  YAY_ARGS=(-S --needed)
  if [[ $NO_CONFIRM -eq 1 ]]; then
    YAY_ARGS+=(--noconfirm)
  fi
  yay "${YAY_ARGS[@]}" "${AUR_PACKAGES[@]}"
else
  echo "[3/5] Skipping AUR packages."
fi

echo "[4/5] Enabling user services..."
if systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now wallpaper-cycle.timer
  systemctl --user start wallpaper-cycle.service || true
else
  echo "Skipping user systemd setup: user manager is unavailable."
  echo "Run later: systemctl --user daemon-reload && systemctl --user enable --now wallpaper-cycle.timer"
fi

echo "[5/5] Applying the custom XKB map..."
if [[ -x "$HOME/.local/bin/load-xkb-shortcuts" ]]; then
  "$HOME/.local/bin/load-xkb-shortcuts" || true
fi

echo
echo "User bootstrap complete."
echo "Manual follow-up: restore secrets such as ~/.ssh, gh auth, browser profiles, and any app logins."
