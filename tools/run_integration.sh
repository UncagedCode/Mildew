#!/usr/bin/env bash
# Runs every integration suite against the real headless host (real sockets) and Chromium.
#   tools/run_integration.sh
# Requires: godot, node 22, Playwright Chromium (PLAYWRIGHT_BROWSERS_PATH, pre-installed in the cloud container).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p tests/output
fail=0
echo "== LAN (real WebSocket clients)"; node tests/integration/lan_integration.mjs | grep -E "SCENARIO|PASS|FAIL|scenarios" || fail=1
echo "== Phone controller (Chromium portrait)"; node tests/integration/phone_ui.mjs | tail -3 || fail=1
echo "== Do Not Press That on phones (Chromium portrait)"; node tests/integration/dnp_ui.mjs | tail -2 || fail=1
echo "== Phone dev panel (Chromium portrait)"; node tests/integration/dev_panel_ui.mjs | tail -2 || fail=1
echo "== QR encoder cross-check"
timeout 120 godot --headless --path . --script res://tests/integration/qr_dump.gd >/dev/null 2>&1
node tests/integration/qr_crosscheck.mjs tests/output/qr_dump.json || fail=1
[ $fail -eq 0 ] && echo "INTEGRATION GREEN" || echo "INTEGRATION FAILED"
exit $fail
