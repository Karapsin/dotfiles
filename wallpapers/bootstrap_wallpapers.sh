#!/usr/bin/env bash
set -euo pipefail

WITH_LIGHTDM=0
if [[ "${1:-}" == "--lightdm" ]]; then
  WITH_LIGHTDM=1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="wallpapers"

echo "[1/6] Installing base packages..."
sudo pacman -S --needed stow python feh git git-lfs

echo "[2/6] (Optional) Installing betterlockscreen..."
if ! command -v betterlockscreen >/dev/null 2>&1; then
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm betterlockscreen
  elif command -v paru >/dev/null 2>&1; then
    paru -S --needed --noconfirm betterlockscreen
  else
    echo "WARN: betterlockscreen not installed (no yay/paru). Install it manually, then rerun."
  fi
fi

echo "[3/6] Pulling Git LFS files (images)..."
git -C "$DOTFILES_DIR" lfs pull || true

echo "[4/6] Deploying dotfiles package via stow..."
stow -d "$DOTFILES_DIR" -t "$HOME" "$PKG"

echo "[5/6] Enabling user timer..."
systemctl --user daemon-reload
systemctl --user enable --now wallpaper-cycle.timer
systemctl --user start wallpaper-cycle.service || true

if [[ "$WITH_LIGHTDM" -eq 1 ]]; then
  echo "[6/6] Installing LightDM sync units (system) + setting greeter background..."
  sudo install -d /usr/share/backgrounds
  sudo install -m 0644 "$DOTFILES_DIR/$PKG/etc/systemd/system/wallpaper-login-copy@.service" /etc/systemd/system/
  sudo install -m 0644 "$DOTFILES_DIR/$PKG/etc/systemd/system/wallpaper-login-copy@.timer"   /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now "wallpaper-login-copy@${USER}.timer"

  # Set background for slick-greeter if present
  if [[ -f /etc/lightdm/slick-greeter.conf || -d /etc/lightdm ]]; then
    sudo cp -n /etc/lightdm/slick-greeter.conf /etc/lightdm/slick-greeter.conf.bak 2>/dev/null || true
    sudo mkdir -p /etc/lightdm
    if ! sudo grep -q '^\[Greeter\]' /etc/lightdm/slick-greeter.conf 2>/dev/null; then
      echo "[Greeter]" | sudo tee /etc/lightdm/slick-greeter.conf >/dev/null
    fi
    # remove old background line (if any) and append ours
    sudo sed -i '/^background=/d' /etc/lightdm/slick-greeter.conf
    echo "background=/usr/share/backgrounds/current_wallpaper.png" | sudo tee -a /etc/lightdm/slick-greeter.conf >/dev/null
  fi

  # Set background for gtk-greeter if config exists
  if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
    sudo cp -n /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.bak || true
    sudo sed -i '/^background=/d' /etc/lightdm/lightdm-gtk-greeter.conf
    echo "background=/usr/share/backgrounds/current_wallpaper.png" | sudo tee -a /etc/lightdm/lightdm-gtk-greeter.conf >/dev/null
  fi
fi

echo "Done."
echo "Verify: systemctl --user list-timers | grep wallpaper"
