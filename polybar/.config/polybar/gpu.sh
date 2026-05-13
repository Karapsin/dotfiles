#!/usr/bin/env bash

set -euo pipefail

if ! command -v nvidia-smi >/dev/null 2>&1; then
  printf -- '--%%\n'
  exit 0
fi

gpu_stats="$(
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null |
    awk -F, '
      NR == 1 {
        usage = $1
        temperature = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", usage)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", temperature)
        print usage, temperature
        exit
      }
    '
)" || gpu_stats=

usage=
temperature=
if [[ -n "$gpu_stats" ]]; then
  read -r usage temperature <<<"$gpu_stats"
fi

case "$usage" in
  '' | *[!0-9]*)
    printf -- '--%%\n'
    ;;
  *)
    case "$temperature" in
      '' | *[!0-9]*)
        printf '%s%%\n' "$usage"
        ;;
      *)
        printf '%s%% (%s°C)\n' "$usage" "$temperature"
        ;;
    esac
    ;;
esac
