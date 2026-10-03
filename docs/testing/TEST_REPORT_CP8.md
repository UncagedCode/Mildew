# TEST REPORT — CP3 → CP8 (all eight games + full Director broadcast)

Date: 2026-10-03 · Build: `0.1.0-cp8` (versionCode 8), debug APK · Godot 4.7.2-stable (GL Compatibility)
Environment: cloud Linux container (no Android TV, no physical phones). Rendering via xvfb + software GL; phones via
Chromium (Playwright) in portrait phone emulation with touch.

## Summary against the checkpoint gates (docs/11)

| Gate | Result | Evidence |
|---|---|---|
| CP3: three real games; factual validator catches missing source/licence; 45-min playlist without crashing | PASS | test_rom, test_gtg, test_director_content; soak |
| CP4: text survives reconnect; server-authoritative votes; 2-player rounds complete; private message force-testable | PASS | test_write_vote, test_interference, phone_ui (reload keeps draft) |
| CP5: drawing on phone browsers; bounded bandwidth; 2- and 8-player chains | PASS (Chromium) / **real phones pending** | test_sketch, phone_ui (finger drawing, reload restores drawing) |
| CP6: no unsatisfiable layout 2–8; reconnect defined; latency tolerance | PASS | test_dnp (2,800 layouts), dnp_ui |
| CP7: all scenarios valid for 2–8; no missing evidence/theory path | PASS | test_basement, content validator |
| CP8: complete Director broadcast; hundreds of sessions without deadlock; pacing; all eight games appear | PASS (simulated) | test_broadcast, test_world, `tests/tools/soak.gd` 300 programmes |
| APK for each checkpoint | PASS (container) | `build/mildew-0.1.0-cp8-debug.apk` (CP4 interim build also produced) |
| Physical Android TV / phone smoke test | **PENDING USER DEVICE TEST** | checklist in NEXT_BUILD.md |

APK SHA-256: `6601113685c16439423640b89a3d3e9fc813b6fb4e8bf61ac83908cf32b0f424` (90.9 MB incl. room plates; v2 signature verified;
manifest LEANBACK + INTERNET; pack checks for every game's content, adverts, rooms, new audio). Published on branch `claude/apk-builds`.

## Unit / state tests — `tools/run_tests.sh`

114 tests, ~3,850 checks, 0 failures, no script errors; every script compiles with `--check-only`. New suites:

- `test_rom` (5), `test_gtg` (4): sourcing, per-asking option shuffle, confidence wager (×2 / forged flag ignored), animal-only validator, decoy pacing, final ×1.5.
- `test_write_vote` (9): content + validators, match normalisation, 3-player survey incl. WHO SAID THAT?, two-player archive filler, self-vote refusal, match bonus, forced answer tampering, Mouthfeel with Make It Worse, 2-player Mouthfeel, no two writing games back to back.
- `test_interference` (6): validator (no call-UI imitation), ≈2.5 deliveries per 45 min with ~25% near-silent sessions, SUPERVISED/CLEAN rules (CLEAN refuses even a dev force), distributed fragments, never names the recipient, never on the TV stream or in screen state.
- `test_sketch` (6): stroke bounds, chain rotation for 2–8, 2-player flow + fidelity scoring + self-vote refusal + exhibit archive, 8-player 4-step chains, 48 KB drawing frames vs 4 KB others, reconnect restores the task.
- `test_dnp` (5): 10 templates × 2–8 players × 40 seeds all valid; decoy/never/order/over-press consequences; duplicate presses ignored; bots complete games; jams, time penalty, culprit named; TV-only timer irregularity.
- `test_basement` (4): every case × 2–8 × 30 deals valid; partial credit; full case with bots; investigation budget/privacy, READY ends discussion early.
- `test_broadcast` (6): adverts/brands/polls; skeleton (one midpoint break after game 3 of 5, awards before final scores); full programme with break + awards; early resume; overrun trims future rounds only; all eight games scheduled.
- `test_world` (7): rooms drift and revert, persist across sessions; chains incl. Tier 4 prerequisites + dev force; Tier 2/3 rates and never mid-game; forced Tier 2/3 incidents play out; Easy Question; THE TEST; Announcer drift.

Measured (simulation): Tier 2 ≈ 0.3 per programme, Tier 3 ≈ 0.08 per programme from incidents alone.

## Soak — `godot --headless --path . -s res://tests/tools/soak.gd -- 300`

300 full Director-generated programmes, 2–8 bots each, random drops/returns and arrivals:
`ended 270, closed 30 (everyone left), hung 0`. Median programme length 32.4 min (bots answer instantly).
All eight games appeared (127–222 times each). Furniture: 1,112 adverts, 313 polls, 990 awards. Incidents by tier
(including chain steps): T0 1,210 · T1 188 · T2 378 · T3 16. After tuning, a 150-programme re-run: Easy Question ≈0.5 per
programme with deliberately bad bots, THE TEST ≈6%.

## Integration — `tools/run_integration.sh` → INTEGRATION GREEN

- LAN (real WebSocket clients, real headless host): 7 scenarios, 0 failed (static/security, 2-player full show,
  8 players + 9th rejected, reconnect, drop after timeout, invalid actions/everyone leaves, dev panel bots-only show).
- Phone controller (Chromium): 22 checks — join wizard, QR link, duplicate name, captain start, answering, reconnect banner,
  Hole gamble, **Survey typing with reload mid-typing, voting with own answer disabled**, **Police Sketch finger drawing,
  reload keeps the drawing, interpreting the other phone's drawing, voting**, end of transmission, no JS errors.
- Do Not Press That (Chromium, new): 8 checks — different panels and instructions per phone, nobody holds their own
  instruction, a tap changes authoritative TV state, decoy jams and is reported, tier result on phone.
- Dev panel (Chromium): 11 checks (incl. forcing the first game).
- QR encoder cross-check: 90 matrices, 0 mismatches.

## Visual checks (render tools under `tests/tools/`)

`docs/testing/cp8_screens/`: write/vote board (Survey + Mouthfeel), Police Sketch board, Do Not Press That board,
Basement case file and reveal, adverts (every scene), poll/awards/break cards, CCTV rooms, phone screens for Survey,
Sketch and Do Not Press That. Issues found and fixed while reviewing: overlapping vote labels, hyphenated words
overflowing evidence cards, mismatched lamp colours on colour-named switches, CCTV text under the channel bug,
doors drawn under props.

## Not tested / known gaps

- No real TV, no real phone browsers (iOS Safari / Android Chrome touch drawing, keyboards over text fields).
- No performance numbers on target hardware.
- All audio provisional and not human-auditioned; Graham lines from CP3–CP8 are unvoiced (subtitles).
- Programme length with humans unmeasured.
