#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STOW_FILE="$DOTFILES_DIR/packages/stow.txt"
IGNORED_TOP_LEVEL_DIRS=(
  .agents
  .codex
  .git
  packages
  root
  scripts
)

read_manifest() {
  local file=$1
  [[ -f "$file" ]] || return 0
  sed -E 's/[[:space:]]+#.*$//; s/#.*$//; /^[[:space:]]*$/d' "$file"
}

contains() {
  local needle=$1
  shift
  local item

  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

run_bash_syntax_checks() {
  local script
  local failed=0

  echo "[1/5] Checking shell syntax..."
  while IFS= read -r -d '' script; do
    if ! bash -n "$script"; then
      failed=1
    fi
  done < <(find "$DOTFILES_DIR" -path "$DOTFILES_DIR/.git" -prune -o -type f -name '*.sh' -print0)

  [[ $failed -eq 0 ]]
}

verify_stow_package_dirs() {
  local package
  local failed=0

  echo "[2/5] Verifying listed stow package directories..."
  for package in "${STOW_PACKAGES[@]}"; do
    if [[ ! -d "$DOTFILES_DIR/$package" ]]; then
      echo "Missing stow package directory: $package" >&2
      failed=1
    fi
  done

  [[ $failed -eq 0 ]]
}

find_unlisted_stow_like_dirs() {
  local dir
  local name
  local failed=0

  echo "[3/5] Checking for unlisted top-level stow-like directories..."
  while IFS= read -r -d '' dir; do
    name="$(basename -- "$dir")"

    contains "$name" "${IGNORED_TOP_LEVEL_DIRS[@]}" && continue
    contains "$name" "${STOW_PACKAGES[@]}" && continue

    if find "$dir" -mindepth 1 -maxdepth 2 \( -name '.config' -o -name '.local' -o -name '.*' \) -print -quit | grep -q .; then
      echo "Top-level directory looks like a stow package but is not listed in packages/stow.txt: $name" >&2
      failed=1
    fi
  done < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  [[ $failed -eq 0 ]]
}

run_stow_dry_runs() {
  local package
  local failed=0
  local tmp_target

  echo "[4/5] Running stow dry-runs..."
  require_command stow
  tmp_target="$(mktemp -d)"
  trap 'rm -rf "$tmp_target"' RETURN

  for package in "${STOW_PACKAGES[@]}"; do
    if ! stow --no-folding --simulate -d "$DOTFILES_DIR" -t "$tmp_target" -R "$package"; then
      failed=1
    fi
  done

  if ! stow --no-folding --simulate -d "$DOTFILES_DIR" -t "$tmp_target" -R "${STOW_PACKAGES[@]}"; then
    failed=1
  fi

  trap - RETURN
  rm -rf "$tmp_target"

  [[ $failed -eq 0 ]]
}

run_shellcheck_if_available() {
  local script
  local failed=0

  echo "[5/5] Running shellcheck if available..."
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "Skipping shellcheck: shellcheck is unavailable."
    return 0
  fi

  while IFS= read -r -d '' script; do
    if ! shellcheck "$script"; then
      failed=1
    fi
  done < <(find "$DOTFILES_DIR" -path "$DOTFILES_DIR/.git" -prune -o -type f -name '*.sh' -print0)

  [[ $failed -eq 0 ]]
}

mapfile -t STOW_PACKAGES < <(read_manifest "$STOW_FILE")

if [[ ${#STOW_PACKAGES[@]} -eq 0 ]]; then
  echo "Missing or empty stow manifest: $STOW_FILE" >&2
  exit 1
fi

run_bash_syntax_checks
verify_stow_package_dirs
find_unlisted_stow_like_dirs
run_stow_dry_runs
run_shellcheck_if_available

echo
echo "Dotfiles validation complete."
