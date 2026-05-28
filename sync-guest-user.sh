#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./sync-guest-user.sh [options]

Sync this dotfiles checkout into a guest/local account using the light user
bootstrap. The target account receives Stow links into this checkout plus
guest-local generated files for Git, GTK bookmarks, and rendered UI config.

Options:
  --target-user USER          Target account to sync (default: guest, or DOTFILES_GUEST_USER).
  --git-name NAME             Generated guest Git user.name (default: Guest).
  --git-email EMAIL           Generated guest Git user.email (default: USER@localhost).
  --downloads-dir PATH        GTK Downloads bookmark path (default: TARGET_HOME/Downloads).
  --projects-dir PATH         GTK Projects bookmark path (default: TARGET_HOME/projects).
  --no-backup                 Fail on existing target files instead of backing them up.
  --with-user-services        Let the user bootstrap enable user services if available.
  --apply-xkb                 Apply the custom XKB map immediately for the target account.
  --enable-linger             Enable systemd linger for the target account.
  --enable-login-wallpaper    Enable the LightDM wallpaper sync timer for the target account.
  -h, --help                  Show this help.

Environment overrides:
  DOTFILES_GUEST_USER, DOTFILES_GUEST_GIT_NAME, DOTFILES_GUEST_GIT_EMAIL,
  DOTFILES_GUEST_DOWNLOADS_DIR, DOTFILES_GUEST_PROJECTS_DIR.
EOF
}

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${DOTFILES_GUEST_USER:-guest}"
GUEST_GIT_NAME="${DOTFILES_GUEST_GIT_NAME:-}"
GUEST_GIT_EMAIL="${DOTFILES_GUEST_GIT_EMAIL:-}"
GUEST_DOWNLOADS_DIR="${DOTFILES_GUEST_DOWNLOADS_DIR:-}"
GUEST_PROJECTS_DIR="${DOTFILES_GUEST_PROJECTS_DIR:-}"
NO_BACKUP=0
WITH_USER_SERVICES=0
APPLY_XKB=0
ENABLE_LINGER=0
ENABLE_LOGIN_WALLPAPER=0

while (($#)); do
  case "$1" in
    --target-user)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --target-user" >&2
        exit 1
      fi
      TARGET_USER="$2"
      shift
      ;;
    --target-user=*)
      TARGET_USER="${1#*=}"
      ;;
    --git-name)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --git-name" >&2
        exit 1
      fi
      GUEST_GIT_NAME="$2"
      shift
      ;;
    --git-name=*)
      GUEST_GIT_NAME="${1#*=}"
      ;;
    --git-email)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --git-email" >&2
        exit 1
      fi
      GUEST_GIT_EMAIL="$2"
      shift
      ;;
    --git-email=*)
      GUEST_GIT_EMAIL="${1#*=}"
      ;;
    --downloads-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --downloads-dir" >&2
        exit 1
      fi
      GUEST_DOWNLOADS_DIR="$2"
      shift
      ;;
    --downloads-dir=*)
      GUEST_DOWNLOADS_DIR="${1#*=}"
      ;;
    --projects-dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --projects-dir" >&2
        exit 1
      fi
      GUEST_PROJECTS_DIR="$2"
      shift
      ;;
    --projects-dir=*)
      GUEST_PROJECTS_DIR="${1#*=}"
      ;;
    --no-backup)
      NO_BACKUP=1
      ;;
    --with-user-services)
      WITH_USER_SERVICES=1
      ;;
    --apply-xkb)
      APPLY_XKB=1
      ;;
    --enable-linger)
      ENABLE_LINGER=1
      ;;
    --enable-login-wallpaper)
      ENABLE_LOGIN_WALLPAPER=1
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

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo ./sync-guest-user.sh [options]" >&2
  exit 1
fi

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

expand_target_path() {
  local path=$1

  case "$path" in
    \~)
      printf '%s\n' "$TARGET_HOME"
      ;;
    \~/*)
      printf '%s/%s\n' "$TARGET_HOME" "${path#~/}"
      ;;
    /*)
      printf '%s\n' "$path"
      ;;
    *)
      echo "Guest path must be absolute or use ~/path: $path" >&2
      exit 1
      ;;
  esac
}

write_env_assignment() {
  local key=$1
  local value=$2

  printf '%s=%q\n' "$key" "$value"
}

run_as_target() {
  local env_args=(
    "HOME=$TARGET_HOME"
    "USER=$TARGET_USER"
    "LOGNAME=$TARGET_USER"
    "DOTFILES_ENV_FILE=$GUEST_ENV_FILE"
  )

  if [[ -d "$TARGET_RUNTIME_DIR" ]]; then
    env_args+=("XDG_RUNTIME_DIR=$TARGET_RUNTIME_DIR")
  fi

  runuser -u "$TARGET_USER" -- env "${env_args[@]}" "$@"
}

require_command getent
require_command install
require_command runuser
if [[ $ENABLE_LINGER -eq 1 ]]; then
  require_command loginctl
fi
if [[ $ENABLE_LOGIN_WALLPAPER -eq 1 ]]; then
  require_command systemctl
fi

PASSWD_ENTRY="$(getent passwd "$TARGET_USER" || true)"
if [[ -z "$PASSWD_ENTRY" ]]; then
  echo "Target user does not exist: $TARGET_USER" >&2
  exit 1
fi

IFS=: read -r _ _ TARGET_UID TARGET_GID _ TARGET_HOME _ <<< "$PASSWD_ENTRY"
if [[ -z "$TARGET_UID" || -z "$TARGET_GID" || -z "$TARGET_HOME" ]]; then
  echo "Could not read passwd entry for target user: $TARGET_USER" >&2
  exit 1
fi
if [[ "$TARGET_UID" == 0 || "$TARGET_HOME" == "/" ]]; then
  echo "Refusing unsafe target user/home: $TARGET_USER ($TARGET_HOME)" >&2
  exit 1
fi

TARGET_RUNTIME_DIR="/run/user/$TARGET_UID"
GUEST_GIT_NAME="${GUEST_GIT_NAME:-Guest}"
GUEST_GIT_EMAIL="${GUEST_GIT_EMAIL:-$TARGET_USER@localhost}"
GUEST_DOWNLOADS_DIR="$(expand_target_path "${GUEST_DOWNLOADS_DIR:-$TARGET_HOME/Downloads}")"
GUEST_PROJECTS_DIR="$(expand_target_path "${GUEST_PROJECTS_DIR:-$TARGET_HOME/projects}")"
GUEST_ENV_FILE="$TARGET_HOME/.dotfiles-bootstrap.env"

if [[ ! -d "$TARGET_HOME" ]]; then
  install -d -o "$TARGET_UID" -g "$TARGET_GID" -m 0700 "$TARGET_HOME"
fi
install -d -o "$TARGET_UID" -g "$TARGET_GID" -m 0755 "$GUEST_DOWNLOADS_DIR" "$GUEST_PROJECTS_DIR"

TMP_ENV=""
cleanup() {
  if [[ -n "$TMP_ENV" && -e "$TMP_ENV" ]]; then
    rm -f -- "$TMP_ENV"
  fi
}
trap cleanup EXIT

TMP_ENV="$(mktemp)"
{
  printf '# Generated by sync-guest-user.sh; rerun guest sync to update.\n'
  write_env_assignment DOTFILES_GIT_NAME "$GUEST_GIT_NAME"
  write_env_assignment DOTFILES_GIT_EMAIL "$GUEST_GIT_EMAIL"
  write_env_assignment DOTFILES_GTK_DOWNLOADS_DIR "$GUEST_DOWNLOADS_DIR"
  write_env_assignment DOTFILES_GTK_PROJECTS_DIR "$GUEST_PROJECTS_DIR"
} > "$TMP_ENV"
chown "$TARGET_UID:$TARGET_GID" "$TMP_ENV"
chmod 0600 "$TMP_ENV"
mv -- "$TMP_ENV" "$GUEST_ENV_FILE"
TMP_ENV=""

if ! run_as_target test -r "$DOTFILES_DIR/bootstrap-user-light.sh"; then
  echo "Target user cannot read the dotfiles checkout: $DOTFILES_DIR" >&2
  echo "Ensure parent directories are searchable and files are readable by $TARGET_USER." >&2
  exit 1
fi

BOOTSTRAP_ARGS=(--skip-lfs)
if [[ $NO_BACKUP -eq 1 ]]; then
  BOOTSTRAP_ARGS+=(--no-backup)
fi
if [[ $WITH_USER_SERVICES -eq 0 ]]; then
  BOOTSTRAP_ARGS+=(--skip-services)
fi
if [[ $APPLY_XKB -eq 0 ]]; then
  BOOTSTRAP_ARGS+=(--skip-xkb)
fi

echo "Syncing dotfiles to $TARGET_USER ($TARGET_HOME)..."
if command -v dbus-run-session >/dev/null 2>&1; then
  run_as_target dbus-run-session -- "$DOTFILES_DIR/bootstrap-user-light.sh" "${BOOTSTRAP_ARGS[@]}"
else
  echo "dbus-run-session is unavailable; graphical gsettings may be skipped."
  run_as_target "$DOTFILES_DIR/bootstrap-user-light.sh" "${BOOTSTRAP_ARGS[@]}"
fi

if [[ $ENABLE_LINGER -eq 1 ]]; then
  echo "Enabling linger for $TARGET_USER..."
  loginctl enable-linger "$TARGET_USER"
fi

if [[ $ENABLE_LOGIN_WALLPAPER -eq 1 ]]; then
  if [[ -f /etc/systemd/system/wallpaper-login-copy@.timer ]]; then
    echo "Enabling login wallpaper timer for $TARGET_USER..."
    systemctl enable --now "wallpaper-login-copy@${TARGET_USER}.timer"
    if [[ -f "$TARGET_HOME/.wallpapers/current_wallpaper.png" ]]; then
      systemctl start "wallpaper-login-copy@${TARGET_USER}.service" || true
    else
      echo "Skipping immediate login wallpaper sync: $TARGET_HOME/.wallpapers/current_wallpaper.png is not installed yet."
    fi
  else
    echo "Skipping login wallpaper timer: /etc/systemd/system/wallpaper-login-copy@.timer is not installed." >&2
    echo "Run sudo ./bootstrap-root.sh --with-lightdm once on this machine if LightDM integration is desired." >&2
  fi
fi

echo
echo "Guest sync complete."
