#!/usr/bin/env bash

set -euo pipefail

read_cpu_totals() {
  awk '
    /^cpu / {
      idle = $5 + $6
      total = 0
      for (i = 2; i <= NF; i++) {
        total += $i
      }
      print total, idle
      exit
    }
  ' /proc/stat
}

read -r total_a idle_a < <(read_cpu_totals)
sleep 0.12
read -r total_b idle_b < <(read_cpu_totals)

usage="$(
  awk -v total_a="$total_a" -v idle_a="$idle_a" -v total_b="$total_b" -v idle_b="$idle_b" '
    BEGIN {
      total_delta = total_b - total_a
      idle_delta = idle_b - idle_a
      if (total_delta > 0) {
        printf "%d", (((total_delta - idle_delta) * 100) / total_delta) + 0.5
      }
    }
  '
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
          chip = ($0 ~ /^k10temp-/) ? "cpu" : ""
          sensor = ""
        }
      }

      chip == "cpu" && sensor == "Tctl" && /^[[:space:]]+temp[0-9]+_input:/ {
        print round($2)
        exit
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
