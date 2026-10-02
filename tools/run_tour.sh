#!/usr/bin/env bash
# Renders the scripted TV screenshot tour under a virtual display (software GL).
#   tools/run_tour.sh [OUT_DIR] [extra user args, e.g. --bots 2 --tour hole]
# Output PNGs land in OUT_DIR (default tests/output/tour).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$(pwd)/tests/output/tour}"
shift || true
mkdir -p "$OUT"
godot --headless --import --path . >/dev/null 2>&1 || true
timeout 600 xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --path . --rendering-driver opengl3 --resolution 1920x1080 --audio-driver Dummy \
  -- --mildew-tour "$OUT" "$@" 2>&1 | grep -E "TOUR_|SCRIPT ERROR|ERROR" | head -60
