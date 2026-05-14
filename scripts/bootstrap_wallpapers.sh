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
stow --no-folding -d "$DOTFILES_DIR" -t "$HOME" "$PKG"
CURRENT="$HOME/.wallpapers/current_wallpaper.png"
STATE_FILE="$HOME/.wallpapers/state/state.json"
mkdir -p -- "$HOME/.wallpapers/state"
if [[ -L "$CURRENT" ]]; then
  CURRENT_SOURCE="$(readlink -f -- "$CURRENT" 2>/dev/null || true)"
  rm -f -- "$CURRENT"
  if [[ -n "$CURRENT_SOURCE" && -f "$CURRENT_SOURCE" ]]; then
    cp -- "$CURRENT_SOURCE" "$CURRENT"
  fi
fi
if [[ -L "$STATE_FILE" ]]; then
  STATE_SOURCE="$(readlink -f -- "$STATE_FILE" 2>/dev/null || true)"
  rm -f -- "$STATE_FILE"
  if [[ -n "$STATE_SOURCE" && -f "$STATE_SOURCE" ]]; then
    cp -- "$STATE_SOURCE" "$STATE_FILE"
  fi
fi
if [[ ! -e "$CURRENT" && -f "$DOTFILES_DIR/wallpapers/.wallpapers/current_wallpaper.png" ]]; then
  cp -- "$DOTFILES_DIR/wallpapers/.wallpapers/current_wallpaper.png" "$CURRENT"
fi
if [[ ! -e "$STATE_FILE" ]]; then
  if [[ -f "$DOTFILES_DIR/wallpapers/.wallpapers/state/state.json" ]]; then
    cp -- "$DOTFILES_DIR/wallpapers/.wallpapers/state/state.json" "$STATE_FILE"
  else
    printf '{}\n' > "$STATE_FILE"
  fi
fi

echo "[5/6] Enabling lingering for user timers..."
sudo loginctl enable-linger "$USER"

echo "[6/6] Enabling user timer..."
WANTS_DIR="$HOME/.config/systemd/user/timers.target.wants"
WANTS_LINK="$WANTS_DIR/wallpaper-cycle.timer"
if [[ -L "$WANTS_DIR" && ! -e "$WANTS_DIR" ]]; then
  echo "Removing stale user timer directory link: $WANTS_DIR"
  rm -f -- "$WANTS_DIR"
fi
if [[ -L "$WANTS_LINK" && ! -e "$WANTS_LINK" ]]; then
  echo "Removing stale user timer link: $WANTS_LINK"
  rm -f -- "$WANTS_LINK"
fi
mkdir -p -- "$WANTS_DIR"
systemctl --user daemon-reload
systemctl --user enable wallpaper-cycle.timer
systemctl --user start wallpaper-cycle.timer
systemctl --user start wallpaper-cycle.service || true

if [[ "$WITH_LIGHTDM" -eq 1 ]]; then
  echo "[7/7] Installing LightDM sync units, theme, and greeter config..."
  sudo install -d /usr/share/backgrounds
  sudo install -m 0644 "$DOTFILES_DIR/root/etc/systemd/system/wallpaper-login-copy@.service" /etc/systemd/system/
  sudo install -m 0644 "$DOTFILES_DIR/root/etc/systemd/system/wallpaper-login-copy@.timer"   /etc/systemd/system/
  sudo cp -n /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.bak 2>/dev/null || true
  sudo install -Dm644 \
    "$DOTFILES_DIR/root/etc/lightdm/lightdm-gtk-greeter.conf" \
    /etc/lightdm/lightdm-gtk-greeter.conf
  sudo install -Dm644 \
    "$DOTFILES_DIR/root/etc/lightdm/lightdm.conf.d/50-dotfiles-greeter.conf" \
    /etc/lightdm/lightdm.conf.d/50-dotfiles-greeter.conf
  sudo install -Dm644 \
    "$DOTFILES_DIR/root/usr/share/themes/Dotfiles-DarkBlue/index.theme" \
    /usr/share/themes/Dotfiles-DarkBlue/index.theme
  sudo install -Dm644 \
    "$DOTFILES_DIR/root/usr/share/themes/Dotfiles-DarkBlue/gtk-3.0/gtk.css" \
    /usr/share/themes/Dotfiles-DarkBlue/gtk-3.0/gtk.css
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

fi

echo "Done."
echo "Verify: systemctl --user list-timers | grep wallpaper"
