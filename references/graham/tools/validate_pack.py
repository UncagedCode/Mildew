#!/usr/bin/env python3
"""Validate the Mildew Graham reference pack without external dependencies."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

for name in [
    "config/graham_states.json",
    "config/graham_animation_profile.json",
    "config/extracted_asset_manifest.json",
]:
    path = ROOT / name
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Invalid JSON {name}: {exc}")

try:
    states = json.loads((ROOT / "config/graham_states.json").read_text(encoding="utf-8"))
    for state_id, data in states.get("states", {}).items():
        asset = data.get("asset")
        if asset and not (ROOT / asset).exists():
            errors.append(f"State {state_id} missing asset: {asset}")
        for item in data.get("speech_cycle", []):
            if not (ROOT / item).exists():
                errors.append(f"State {state_id} missing speech frame: {item}")
    for motion_id, motion in states.get("motion_reference_only", {}).items():
        if not (ROOT / motion).exists():
            errors.append(f"Missing motion reference {motion_id}: {motion}")
except Exception as exc:
    errors.append(f"Could not validate state paths: {exc}")

required = [
    "reference/video/graham_canonical_reference_clean_4x3.mp4",
    "assets/contact_sheets/graham_curated_states.jpg",
    "docs/GRAHAM_GODOT_IMPLEMENTATION.md",
    "CLAUDE_CODE_UPDATE_PROMPT.md",
]
for name in required:
    if not (ROOT / name).exists():
        errors.append(f"Required file missing: {name}")

if errors:
    print("Graham pack validation FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("Graham pack validation OK")
