#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh MODE [target options]

Choose exactly one mode:
  --root         Run bootstrap-root.sh.
  --user         Run bootstrap-user.sh.
  --user-light   Run bootstrap-user-light.sh.

Examples:
  sudo ./bootstrap.sh --root --enable-networkmanager --with-lightdm
  ./bootstrap.sh --user --noconfirm
  ./bootstrap.sh --user-light --enable-linger --enable-login-wallpaper

Direct script entrypoints remain supported:
  sudo ./bootstrap-root.sh --enable-networkmanager --with-lightdm
  ./bootstrap-user.sh --noconfirm
  ./bootstrap-user-light.sh --enable-linger
EOF
}

if [[ $# -eq 0 ]]; then
  echo "Missing mode flag." >&2
  usage >&2
  exit 1
fi

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode_count=0
target_script=""
target_args=()

for arg in "$@"; do
  case "$arg" in
    --root)
      mode_count=$((mode_count + 1))
      target_script="$SCRIPT_DIR/bootstrap-root.sh"
      ;;
    --user)
      mode_count=$((mode_count + 1))
      target_script="$SCRIPT_DIR/bootstrap-user.sh"
      ;;
    --user-light)
      mode_count=$((mode_count + 1))
      target_script="$SCRIPT_DIR/bootstrap-user-light.sh"
      ;;
    *)
      target_args+=("$arg")
      ;;
  esac
done

if [[ $mode_count -eq 0 ]]; then
  echo "Missing mode flag: choose --root, --user, or --user-light." >&2
  usage >&2
  exit 1
fi

if [[ $mode_count -gt 1 ]]; then
  echo "Choose exactly one mode flag." >&2
  usage >&2
  exit 1
fi

exec "$target_script" "${target_args[@]}"
