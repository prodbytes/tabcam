#!/usr/bin/env bash
# Streams the app's log from the Android phone attached by USB, readable:
# the app's own lines (tag flutter) and the system's errors that explain
# them (crashes, the document scanner and ML Kit), without the rest of the
# system's noise. `bash scripts/android-log.sh` or `devbox run android-log`;
# ANDROID_SERIAL=<serial> with several phones.
#
# Options: --clear starts from now; --all shows every line of the app's
# process instead (native and plugin logs too, until it restarts).
set -euo pipefail

clear=false
all=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clear) clear=true ;;
    --all) all=true ;;
    *) echo "usage: $0 [--clear] [--all]" >&2; exit 2 ;;
  esac
  shift
done

source "$(dirname "$0")/android-device.sh"
package=com.nu01.tabscan
adb_s() { "$adb" -s "$serial" "$@"; }

if $clear; then adb_s logcat -c; fi

if $all; then
  pid="$(adb_s shell pidof "$package" | tr -d '\r')" || {
    echo "error: $package isn't running" >&2
    exit 1
  }
  echo "Logging $package (process $pid) on $serial; Ctrl-C to stop" >&2
  exec "$adb" -s "$serial" logcat -v time --pid="$pid"
fi

echo "Logging $package on $serial; Ctrl-C to stop" >&2
# The app's own lines (tag flutter: print and debugPrint), and the system
# lines that explain them: the scanner and ML Kit (their own tags), crashes,
# and the app being started or killed.
tags='flutter|GmsDocumentScanning[A-Za-z]*|MLKit[A-Za-z]*|AndroidRuntime'
adb_s logcat -v time |
  grep --line-buffered -E " [VDIWEF]/($tags) *\(|FATAL|ActivityManager.*(Start proc|Killing|died|ANR).*$package"
