#!/usr/bin/env bash
set -euo pipefail

if command -v i3-msg >/dev/null 2>&1; then
    result="$(i3-msg '[title="^VPN Control Desktop$"] focus' 2>/dev/null || true)"
    if printf '%s\n' "$result" | grep -q '"success":true'; then
        exit 0
    fi
fi

exec vpn-control
