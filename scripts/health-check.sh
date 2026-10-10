#!/usr/bin/env bash
# Continuous health monitor: every HEALTH_CHECK_INTERVAL seconds (15 by
# default), one line per run: the time, then each dependency as its icon,
# a short label and ✅/❌, e.g.
#   2026-10-10 14:02:10 🏠 index ✅  🎸 web ✅
# On start it prints, once, where to open the app locally.
# Runs via `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

# get <timeout> <url>: succeeds on a 2xx answer.
get() {
    curl -fs -o /dev/null --max-time "$1" "$2"
}

# status <icon> <label> <command...>: "icon label ✅" when the command
# succeeds, else ❌.
status() {
    local icon=$1 label=$2
    shift 2
    if "$@"; then printf '%s %s ✅' "$icon" "$label"; else printf '%s %s ❌' "$icon" "$label"; fi
}

WEB_URL="http://localhost:${FLUTTER_WEB_PORT:-2012}/app/"
INDEX_URL="http://localhost:${INDEX_PORT:-2013}/"

echo "🎸 TabScan: $WEB_URL"
echo "🏠 index:   $INDEX_URL (redirects to the app)"

while true; do
    # Add more dependencies here, one status call each.
    checks=(
        "$(status 🏠 index get 5 "$INDEX_URL")"
        "$(status 🎸 web get 5 "$WEB_URL")"
    )
    line="$(date '+%Y-%m-%d %H:%M:%S')"
    for check in "${checks[@]}"; do line+="  $check"; done
    printf '%s\n' "$line"
    sleep "$INTERVAL"
done
