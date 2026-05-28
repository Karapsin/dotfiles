#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./bootstrap-root.sh [options]

Options:
  --noconfirm                  Pass --noconfirm to pacman.
  --with-lightdm               Install and enable LightDM integration.
  --enable-networkmanager      Enable NetworkManager.
  --enable-multilib            Enable the Arch [multilib] repository.
  --vulkan-provider PROVIDER   Choose Vulkan provider: auto, nvidia, intel,
                               amd, virtio, swrast, or none.
  -h, --help                   Show this help.
EOF
}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo ./bootstrap-root.sh [options]"
  exit 1
fi

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACMAN_FILE="$DOTFILES_DIR/packages/pacman.txt"
LIGHTDM_FILE="$DOTFILES_DIR/packages/pacman-lightdm.txt"

NO_CONFIRM=0
WITH_LIGHTDM=0
ENABLE_NETWORKMANAGER=0
ENABLE_MULTILIB=0
VULKAN_PROVIDER="${DOTFILES_VULKAN_PROVIDER:-auto}"

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
    --enable-multilib)
      ENABLE_MULTILIB=1
      ;;
    --vulkan-provider)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --vulkan-provider" >&2
        exit 1
      fi
      VULKAN_PROVIDER="$2"
      shift
      ;;
    --vulkan-provider=*)
      VULKAN_PROVIDER="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
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

contains_package() {
  local needle=$1
  shift
  local package

  for package in "$@"; do
    [[ "$package" == "$needle" ]] && return 0
  done

  return 1
}

append_unique_packages() {
  local package
  local existing

  for package in "$@"; do
    [[ -n "$package" ]] || continue
    existing=0
    if contains_package "$package" "${PACMAN_PACKAGES[@]}"; then
      existing=1
    fi
    [[ $existing -eq 1 ]] || PACMAN_PACKAGES+=("$package")
  done
}

retry_command() {
  local attempts=$1
  local delay_seconds=$2
  local label=$3
  local attempt
  shift 3

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if "$@"; then
      return 0
    fi

    if [[ $attempt -lt $attempts ]]; then
      echo "$label failed (attempt $attempt/$attempts); retrying in ${delay_seconds}s..." >&2
      sleep "$delay_seconds"
    fi
  done

  echo "$label failed after $attempts attempts." >&2
  return 1
}

multilib_enabled() {
  grep -Eq '^[[:space:]]*\[multilib\][[:space:]]*$' /etc/pacman.conf
}

enable_multilib_repo() {
  if multilib_enabled; then
    echo "Arch [multilib] repository is already enabled."
    return
  fi

  echo "Enabling Arch [multilib] repository..."
  if grep -Eq '^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$' /etc/pacman.conf; then
    sed -i -E '/^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/{
      s/^[[:space:]]*#[[:space:]]*//
      n
      s/^[[:space:]]*#[[:space:]]*//
    }' /etc/pacman.conf
  else
    cat >>/etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
  fi
}

detect_vulkan_provider() {
  local device
  local class
  local vendor
  local fallback="swrast"

  for device in /sys/bus/pci/devices/*; do
    [[ -r "$device/class" && -r "$device/vendor" ]] || continue
    class="$(<"$device/class")"
    case "$class" in
      0x03*|0x120000)
        vendor="$(<"$device/vendor")"
        case "$vendor" in
          0x10de)
            printf 'nvidia\n'
            return
            ;;
          0x8086)
            fallback="intel"
            ;;
          0x1002|0x1022)
            fallback="amd"
            ;;
          0x1af4)
            fallback="virtio"
            ;;
        esac
        ;;
    esac
  done

  printf '%s\n' "$fallback"
}

vulkan_provider_packages() {
  local provider=$1
  local include_lib32=$2
  local packages=()

  case "$provider" in
    nvidia)
      packages+=(nvidia-utils)
      [[ $include_lib32 -eq 1 ]] && packages+=(lib32-nvidia-utils)
      ;;
    intel)
      packages+=(vulkan-intel)
      [[ $include_lib32 -eq 1 ]] && packages+=(lib32-vulkan-intel)
      ;;
    amd)
      packages+=(vulkan-radeon)
      [[ $include_lib32 -eq 1 ]] && packages+=(lib32-vulkan-radeon)
      ;;
    virtio)
      packages+=(vulkan-virtio)
      [[ $include_lib32 -eq 1 ]] && packages+=(lib32-vulkan-virtio)
      ;;
    swrast)
      packages+=(vulkan-swrast)
      [[ $include_lib32 -eq 1 ]] && packages+=(lib32-vulkan-swrast)
      ;;
    none)
      ;;
    *)
      echo "Unknown Vulkan provider: $provider" >&2
      echo "Choose auto, nvidia, intel, amd, virtio, swrast, or none." >&2
      exit 1
      ;;
  esac

  printf '%s\n' "${packages[@]}"
}

mapfile -t PACMAN_PACKAGES < <(read_manifest "$PACMAN_FILE")
mapfile -t LIGHTDM_PACKAGES < <(read_manifest "$LIGHTDM_FILE")

if [[ ${#PACMAN_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty package manifest: $PACMAN_FILE" >&2
  exit 1
fi

if [[ $ENABLE_MULTILIB -eq 1 ]]; then
  enable_multilib_repo
fi

if contains_package steam "${PACMAN_PACKAGES[@]}" && ! multilib_enabled; then
  echo "Steam requires the Arch [multilib] repository." >&2
  echo "Rerun with --enable-multilib, or remove steam from $PACMAN_FILE." >&2
  exit 1
fi

case "$VULKAN_PROVIDER" in
  auto)
    VULKAN_PROVIDER="$(detect_vulkan_provider)"
    ;;
  nvidia|intel|amd|virtio|swrast|none)
    ;;
  *)
    echo "Unknown Vulkan provider: $VULKAN_PROVIDER" >&2
    echo "Choose auto, nvidia, intel, amd, virtio, swrast, or none." >&2
    exit 1
    ;;
esac

if [[ "$VULKAN_PROVIDER" != "none" ]]; then
  echo "Using Vulkan provider: $VULKAN_PROVIDER"
  mapfile -t VULKAN_PACKAGES < <(vulkan_provider_packages "$VULKAN_PROVIDER" "$(multilib_enabled && printf 1 || printf 0)")
  append_unique_packages "${VULKAN_PACKAGES[@]}"
else
  echo "Leaving Vulkan provider selection to pacman."
fi

PACMAN_ARGS=(-Syu --needed)
PACMAN_INSTALL_ARGS=(-S --needed)
if [[ $NO_CONFIRM -eq 1 ]]; then
  PACMAN_ARGS+=(--noconfirm)
  PACMAN_INSTALL_ARGS+=(--noconfirm)
fi

echo "[1/7] Installing official packages..."
retry_command 5 10 "Installing official packages" pacman "${PACMAN_ARGS[@]}" "${PACMAN_PACKAGES[@]}"

echo "[2/7] Setting the X11 keyboard baseline..."
localectl --no-convert set-x11-keymap us,ru pc105+inet "" "grp:win_space_toggle,terminate:ctrl_alt_bksp"

BOOTSTRAP_USER="${SUDO_USER:-${BOOTSTRAP_USER:-}}"
if [[ -n "$BOOTSTRAP_USER" ]]; then
  echo "[3/7] Enabling lingering for $BOOTSTRAP_USER..."
  loginctl enable-linger "$BOOTSTRAP_USER" || true
else
  echo "[3/7] Skipping linger enable: no non-root target user detected."
fi

if [[ $ENABLE_NETWORKMANAGER -eq 1 ]]; then
  echo "[4/7] Enabling NetworkManager..."
  systemctl enable --now NetworkManager.service
else
  echo "[4/7] Leaving NetworkManager disabled (pass --enable-networkmanager to enable it)."
fi

echo "[5/7] Enabling Bluetooth service..."
systemctl enable --now bluetooth.service || true

echo "[6/7] Installing Chrome dark-blue theme policy..."
install -Dm644 \
  "$DOTFILES_DIR/root/etc/opt/chrome/policies/managed/dotfiles-dark-blue-theme.json" \
  /etc/opt/chrome/policies/managed/dotfiles-dark-blue-theme.json

if [[ $WITH_LIGHTDM -eq 1 ]]; then
  if [[ ${#LIGHTDM_PACKAGES[@]} -eq 0 ]]; then
    echo "Missing or empty LightDM package manifest: $LIGHTDM_FILE" >&2
    exit 1
  fi

  echo "[7/7] Installing LightDM packages, greeter theme, and wallpaper sync units..."
  retry_command 5 10 "Installing LightDM packages" pacman "${PACMAN_INSTALL_ARGS[@]}" "${LIGHTDM_PACKAGES[@]}"

  install -d /usr/share/backgrounds
  if [[ -f "$DOTFILES_DIR/wallpapers/.wallpapers/current_wallpaper.png" ]]; then
    install -Dm644 \
      "$DOTFILES_DIR/wallpapers/.wallpapers/current_wallpaper.png" \
      /usr/share/backgrounds/current_wallpaper.png
  fi
  install -Dm644 \
    "$DOTFILES_DIR/root/etc/systemd/system/wallpaper-login-copy@.service" \
    /etc/systemd/system/wallpaper-login-copy@.service
  install -Dm644 \
    "$DOTFILES_DIR/root/etc/systemd/system/wallpaper-login-copy@.timer" \
    /etc/systemd/system/wallpaper-login-copy@.timer
  if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf && ! -f /etc/lightdm/lightdm-gtk-greeter.conf.bak ]]; then
    cp -p /etc/lightdm/lightdm-gtk-greeter.conf /etc/lightdm/lightdm-gtk-greeter.conf.bak
  fi
  install -Dm644 \
    "$DOTFILES_DIR/root/etc/lightdm/lightdm.conf.d/50-dotfiles-greeter.conf" \
    /etc/lightdm/lightdm.conf.d/50-dotfiles-greeter.conf
  install -Dm644 \
    "$DOTFILES_DIR/root/usr/share/themes/Dotfiles-DarkBlue/index.theme" \
    /usr/share/themes/Dotfiles-DarkBlue/index.theme
  bash "$DOTFILES_DIR/scripts/render-root-ui.sh"
  systemctl daemon-reload
  systemctl enable lightdm.service

  if [[ -n "$BOOTSTRAP_USER" ]]; then
    systemctl enable --now "wallpaper-login-copy@${BOOTSTRAP_USER}.timer"
    if [[ -f "/home/${BOOTSTRAP_USER}/.wallpapers/current_wallpaper.png" ]]; then
      systemctl start "wallpaper-login-copy@${BOOTSTRAP_USER}.service"
    else
      echo "Skipping immediate login wallpaper sync: /home/${BOOTSTRAP_USER}/.wallpapers/current_wallpaper.png is not installed yet."
    fi
  else
    echo "Skipping wallpaper-login-copy timer enable: no non-root target user detected."
  fi
else
  echo "[7/7] Skipping LightDM wallpaper integration (pass --with-lightdm to enable it)."
fi

echo
echo "Root bootstrap complete."
echo "Next: run ./bootstrap-user.sh as your normal user."
