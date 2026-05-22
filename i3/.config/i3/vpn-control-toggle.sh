#!/usr/bin/env bash
set -euo pipefail

if command -v i3-msg >/dev/null 2>&1; then
    for criterion in '[title="^VPN Control$"]' '[title="^VPN Control Desktop$"]'; do
        result="$(i3-msg "$criterion focus" 2>/dev/null || true)"
        if printf '%s\n' "$result" | grep -q '"success":true'; then
            exit 0
        fi
    done
fi

exec vpn-control
