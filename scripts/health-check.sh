#!/usr/bin/env bash
# Continuous health monitor: every HEALTH_CHECK_INTERVAL seconds (15 by
# default), one line per check, each with the time, an emoji, ✅/❌ and a
# short reason. Runs via `devbox services up` (see process-compose.yaml) or
# standalone.
set -uo pipefail

INTERVAL="${HEALTH_CHECK_INTERVAL:-15}"

# report <emoji> <name> <status emoji> [detail]
report() {
    printf '%s %s %-5s %s%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" "${4:+ $4}"
}

# ok_if <emoji> <name> <detail> <command...>: ✅ when the command succeeds.
ok_if() {
    local emoji=$1 name=$2 detail=$3
    shift 3
    if "$@"; then report "$emoji" "$name" ✅ "$detail"; else report "$emoji" "$name" ❌ "$detail"; fi
}

# get <timeout> <curl args...>: succeeds on a 2xx answer.
get() {
    local timeout=$1
    shift
    curl -fs -o /dev/null --max-time "$timeout" "$@"
}

check_index() { ok_if 🏠 index "localhost:${INDEX_PORT:-2013}/" get 5 "http://localhost:${INDEX_PORT:-2013}/"; }

check_web() { ok_if 🎸 web "localhost:${FLUTTER_WEB_PORT:-2012}/app/" get 5 "http://localhost:${FLUTTER_WEB_PORT:-2012}/app/"; }

while true; do
    # Add more services here, one check_* function each.
    check_index
    check_web
    sleep "$INTERVAL"
done
