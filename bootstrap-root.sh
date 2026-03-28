#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo ./bootstrap-root.sh [--noconfirm] [--with-lightdm] [--enable-networkmanager]"
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACMAN_FILE="$DOTFILES_DIR/packages/pacman.txt"

NO_CONFIRM=0
WITH_LIGHTDM=0
ENABLE_NETWORKMANAGER=0

while (($#)); do
  case "$1" in
    --noconfirm)
      NO_CONFIRM=1
      ;;
    --with-lightdm)
      WITH_LIGHTDM=1
      ;;
    --enable-networkmanager)
      ENABLE_NETWORKMANAGER=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "$PACMAN_FILE" ]]; then
  echo "Missing package manifest: $PACMAN_FILE" >&2
  exit 1
fi

mapfile -t PACMAN_PACKAGES < <(sed -E 's/[[:space:]]+#.*$//; s/#.*$//; /^[[:space:]]*$/d' "$PACMAN_FILE")

PACMAN_ARGS=(-Syu --needed)
if [[ $NO_CONFIRM -eq 1 ]]; then
  PACMAN_ARGS+=(--noconfirm)
fi

echo "[1/5] Installing official packages..."
pacman "${PACMAN_ARGS[@]}" "${PACMAN_PACKAGES[@]}"

echo "[2/5] Setting the X11 keyboard baseline..."
localectl --no-convert set-x11-keymap us,ru pc105+inet "" "grp:alt_shift_toggle,terminate:ctrl_alt_bksp"

BOOTSTRAP_USER="${SUDO_USER:-${BOOTSTRAP_USER:-}}"
if [[ -n "$BOOTSTRAP_USER" ]]; then
  echo "[3/5] Enabling lingering for $BOOTSTRAP_USER..."
  loginctl enable-linger "$BOOTSTRAP_USER" || true
else
  echo "[3/5] Skipping linger enable: no non-root target user detected."
fi

if [[ $ENABLE_NETWORKMANAGER -eq 1 ]]; then
  echo "[4/5] Enabling NetworkManager..."
  systemctl enable --now NetworkManager.service
else
  echo "[4/5] Leaving NetworkManager disabled (pass --enable-networkmanager to enable it)."
fi

if [[ $WITH_LIGHTDM -eq 1 ]]; then
  echo "[5/5] Installing LightDM wallpaper sync units..."
  install -Dm644 \
    "$DOTFILES_DIR/wallpapers/etc/systemd/system/wallpaper-login-copy@.service" \
    /etc/systemd/system/wallpaper-login-copy@.service
  install -Dm644 \
    "$DOTFILES_DIR/wallpapers/etc/systemd/system/wallpaper-login-copy@.timer" \
    /etc/systemd/system/wallpaper-login-copy@.timer
  systemctl daemon-reload

  if [[ -n "$BOOTSTRAP_USER" ]]; then
    systemctl enable --now "wallpaper-login-copy@${BOOTSTRAP_USER}.timer"
  else
    echo "Skipping wallpaper-login-copy timer enable: no non-root target user detected."
  fi

  if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
    sed -i '/^background=/d' /etc/lightdm/lightdm-gtk-greeter.conf
    printf 'background=/usr/share/backgrounds/current_wallpaper.png\n' >> /etc/lightdm/lightdm-gtk-greeter.conf
  fi
else
  echo "[5/5] Skipping LightDM wallpaper integration (pass --with-lightdm to enable it)."
fi

echo
echo "Root bootstrap complete."
echo "Next: run ./bootstrap-user.sh as your normal user."
