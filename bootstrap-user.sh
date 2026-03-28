#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run as your normal user: ./bootstrap-user.sh [--noconfirm] [--skip-aur]"
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUR_FILE="$DOTFILES_DIR/packages/aur.txt"
STOW_PACKAGES=(home i3 polybar wallpapers xkb)

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

mapfile -t AUR_PACKAGES < <(sed -E 's/[[:space:]]+#.*$//; s/#.*$//; /^[[:space:]]*$/d' "$AUR_FILE")

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

echo "[1/5] Pulling Git LFS assets (if available)..."
if command -v git-lfs >/dev/null 2>&1; then
  git -C "$DOTFILES_DIR" lfs pull || true
fi

echo "[2/5] Deploying stow packages..."
stow -d "$DOTFILES_DIR" -t "$HOME" -R "${STOW_PACKAGES[@]}"

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
systemctl --user daemon-reload
systemctl --user enable --now wallpaper-cycle.timer
systemctl --user start wallpaper-cycle.service || true

echo "[5/5] Applying the custom XKB map..."
if [[ -x "$HOME/.local/bin/load-xkb-shortcuts" ]]; then
  "$HOME/.local/bin/load-xkb-shortcuts" || true
fi

echo
echo "User bootstrap complete."
echo "Manual follow-up: restore secrets such as ~/.ssh, gh auth, browser profiles, and any app logins."
