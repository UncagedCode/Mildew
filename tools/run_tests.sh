#!/usr/bin/env bash
# Runs the headless GDScript test suite and fails on ANY script error, even if the
# in-script checks passed (GDScript runtime errors abort a test function silently).
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p tests/output
godot --headless --import --path . >/dev/null 2>&1
# 1) Every script must compile.
fail=0
while IFS= read -r f; do
  out=$(timeout 60 godot --headless --path . --check-only --script "$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error" || true)
  if [ -n "$out" ]; then echo "COMPILE FAIL: $f"; echo "$out" | head -5; fail=1; fi
done < <(find src tests -name "*.gd" | sort)
# 2) Run tests.
timeout 1200 godot --headless --path . --script res://tests/run_tests.gd -- "$@" 2>&1 | tee tests/output/unit_log.txt | grep -E "^(PASS|FAIL)|^\s{6}|tests, .* checks"
rc=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" tests/output/unit_log.txt; then
  echo "SCRIPT ERRORS DURING TESTS:"; grep -A3 "SCRIPT ERROR" tests/output/unit_log.txt | head -40; fail=1
fi
[ $rc -ne 0 ] && fail=1
[ $fail -eq 0 ] && echo "ALL GREEN" || echo "TEST RUN FAILED"
exit $fail
