#!/usr/bin/env bash
# Continuous health monitor: every HEALTH_CHECK_INTERVAL seconds (15 by
# default), one line per run: the time, then each dependency as its icon,
# a short label and ✅/❌, e.g.
#   2026-10-10 14:02:10  🏠 index ✅  🎸 web ✅  🚚 cdn ✅  🔒 https ✅
# On start it prints, once, where to open the app locally.
# Runs via `devbox services up` (see process-compose.yaml) or standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

# get <timeout> <curl args...>: succeeds on a 2xx answer.
get() {
    local timeout=$1
    shift
    curl -fs -o /dev/null --max-time "$timeout" "$@"
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
FLOCI="http://localhost:${FLOCI_PORT:-2014}"
CDN_ALIAS="${TABSCANNER_CDN_ALIAS:-tabscan.localhost}"
PUBLIC_HOST="${TABSCANNER_PUBLIC_HOST:-local.tabscan.nu01.com}"
HTTPS_PORT="${FLOCI_HTTPS_PORT:-2443}"
HTTPS_URL="https://$PUBLIC_HOST:$HTTPS_PORT/app/"
MKCERT_CA="$(mkcert -CAROOT 2>/dev/null)/rootCA.pem"

# The CloudFront distribution in Floci, addressed by its alias in the Host
# header (so it works where *.localhost doesn't resolve).
cdn() { get 10 -H "Host: $CDN_ALIAS" "$FLOCI/app/"; }

# HTTPS through the CDN on the public local name, validating the certificate
# against mkcert's CA (not the system trust store, so it passes before
# `mkcert -install` too). --resolve pins the name to loopback, so it doesn't
# depend on DNS either.
https() {
    get 10 --cacert "$MKCERT_CA" \
        --resolve "$PUBLIC_HOST:$HTTPS_PORT:127.0.0.1" "$HTTPS_URL"
}

echo "🎸 TabScan: $WEB_URL"
echo "🏠 index:   $INDEX_URL (redirects to the app)"
echo "🔒 HTTPS:   $HTTPS_URL (through Floci's CloudFront)"

while true; do
    # Add more dependencies here, one status call each.
    checks=(
        "$(status 🏠 index get 5 "$INDEX_URL")"
        "$(status 🎸 web get 5 "$WEB_URL")"
        "$(status 🚚 cdn cdn)"
        "$(status 🔒 https https)"
    )
    line="$(date '+%Y-%m-%d %H:%M:%S')"
    for check in "${checks[@]}"; do line+="  $check"; done
    printf '%s\n' "$line"
    sleep "$INTERVAL"
done
