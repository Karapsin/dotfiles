#!/usr/bin/env bash

set -euo pipefail

usage="$(
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { available = $2 }
    END {
      if (total > 0 && available >= 0) {
        printf "%d", ((total - available) * 100 / total) + 0.5
      }
    }
  ' /proc/meminfo
)"

temperature="$(
  sensors -u 2>/dev/null |
    awk '
      function round(value) { return int(value + 0.5) }

      /^[^[:space:]]/ {
        if ($0 ~ /:$/) {
          sensor = $0
          sub(/:$/, "", sensor)
        } else if ($0 !~ /^Adapter:/) {
          chip = ($0 ~ /^spd5118-/) ? "memory" : ""
          sensor = ""
        }
      }

      chip == "memory" && /^[[:space:]]+temp[0-9]+_input:/ {
        value = round($2)
        if (!seen || value > max) {
          max = value
          seen = 1
        }
      }

      END {
        if (seen) {
          print max
        }
      }
    '
)" || temperature=

if [[ -n "$usage" && -n "$temperature" ]]; then
  printf '%s%% (%s°C)\n' "$usage" "$temperature"
elif [[ -n "$usage" ]]; then
  printf '%s%%\n' "$usage"
else
  printf -- '--%%\n'
fi
