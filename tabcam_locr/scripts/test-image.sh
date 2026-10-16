#!/usr/bin/env bash
# Runs the built image the way Lambda does (read-only, /tmp writable, not
# root) and has it read a made-up riff: python -m locr.selftest.
set -euo pipefail
image="${1:-tabcam-ocr:dev}"
docker run --rm --platform linux/amd64 --read-only --tmpfs /tmp:size=512m \
  --entrypoint python "$image" -m locr.selftest --min 0.8
