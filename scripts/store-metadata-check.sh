#!/usr/bin/env bash
# Checks the store listings in tabcam_store/ against Google Play's and
# the App Store's limits: each file exists, isn't empty and fits its
# length (characters, or bytes for the iOS keywords; a trailing newline
# isn't counted); each image is a PNG of its store's size, with an alpha
# channel only where one is asked for (the Play icon). Exits 1 if any
# check fails.
#
#   bash scripts/store-metadata-check.sh [store dir]   default: tabcam_store
set -euo pipefail

cd "$(dirname "$0")/.."
store="${1:-tabcam_store}"
# Count characters, not bytes, in UTF-8.
export LC_ALL=en_US.UTF-8

failures=0

# check <file> <limit> [chars|bytes]
check() {
  local file="$store/$1" limit="$2" unit="${3:-chars}" text count
  if [[ ! -f "$file" ]]; then
    printf 'FAIL %s: missing\n' "$file"
    failures=$((failures + 1))
    return
  fi
  text="$(<"$file")"
  if [[ "$unit" == bytes ]]; then
    count="$(printf '%s' "$text" | LC_ALL=C wc -c | tr -d ' ')"
  else
    count="${#text}"
  fi
  if [[ "$count" -eq 0 ]]; then
    printf 'FAIL %s: empty\n' "$file"
    failures=$((failures + 1))
  elif [[ "$count" -gt "$limit" ]]; then
    printf 'FAIL %s: %s %s, limit %s\n' "$file" "$count" "$unit" "$limit"
    failures=$((failures + 1))
  else
    printf 'ok   %s: %s/%s %s\n' "$file" "$count" "$limit" "$unit"
  fi
}

# check_url <file>: one https URL.
check_url() {
  local file="$store/$1" text
  check "$1" 255
  [[ -f "$file" ]] || return 0
  text="$(<"$file")"
  if [[ ! "$text" =~ ^https://[^[:space:]]+$ ]]; then
    printf 'FAIL %s: not a single https URL\n' "$file"
    failures=$((failures + 1))
  fi
}

# check_png <file> <width> <height> <rgb|rgba>: the size and color type
# from the PNG's header (IHDR), read with od, so it runs anywhere.
check_png() {
  local file="$store/$1" want="$2x$3 $4" header w h type got
  if [[ ! -f "$file" ]]; then
    printf 'FAIL %s: missing\n' "$file"
    failures=$((failures + 1))
    return
  fi
  header="$(od -An -v -tu1 -j16 -N10 "$file" | tr -s ' \n' ' ')"
  read -r -a h <<<"$header"
  w=$(((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]))
  type="${h[9]:-}"
  case "$type" in 2) type=rgb ;; 6) type=rgba ;; *) type="type ${type:-?}" ;; esac
  got="${w}x$(((h[4] << 24) | (h[5] << 16) | (h[6] << 8) | h[7])) $type"
  if [[ "$(head -c 8 "$file" | od -An -tx1 | tr -d ' \n')" != 89504e470d0a1a0a ]]; then
    printf 'FAIL %s: not a PNG\n' "$file"
    failures=$((failures + 1))
  elif [[ "$got" != "$want" ]]; then
    printf 'FAIL %s: %s, want %s\n' "$file" "$got" "$want"
    failures=$((failures + 1))
  else
    printf 'ok   %s: %s\n' "$file" "$got"
  fi
}

# Google Play (fastlane supply layout)
check android/en-US/title.txt 30
check android/en-US/short_description.txt 80
check android/en-US/full_description.txt 4000
check android/en-US/changelogs/default.txt 500
check_png android/en-US/images/icon.png 512 512 rgba
check_png android/en-US/images/featureGraphic.png 1024 500 rgb
for n in 1 2 3 4 5 6; do
  check_png "android/en-US/images/phoneScreenshots/$n.png" 1080 1920 rgb
done

# App Store (fastlane deliver layout)
check ios/en-US/name.txt 30
check ios/en-US/subtitle.txt 30
check ios/en-US/description.txt 4000
check ios/en-US/keywords.txt 100 bytes
check ios/en-US/promotional_text.txt 170
check ios/en-US/release_notes.txt 4000
check_url ios/en-US/support_url.txt
check_url ios/en-US/marketing_url.txt
check_url ios/en-US/privacy_url.txt
check ios/review_information/notes.txt 4000
# Screenshots: the 6.9" iPhone and, as the app runs on iPads, the 13" iPad.
for n in 1 2 3 4 5 6; do
  check_png "ios/screenshots/en-US/iphone69_$n.png" 1320 2868 rgb
  check_png "ios/screenshots/en-US/ipad13_$n.png" 2064 2752 rgb
done

# Keywords: comma-separated, no spaces around the commas, no empty ones.
keywords="$store/ios/en-US/keywords.txt"
if [[ -f "$keywords" ]]; then
  kw="$(<"$keywords")"
  if [[ "$kw" =~ (^|,)[[:space:]]|[[:space:]](,|$)|,, ]]; then
    printf 'FAIL %s: spaces around commas, or an empty keyword\n' "$keywords"
    failures=$((failures + 1))
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
printf 'All store metadata checks passed\n'
