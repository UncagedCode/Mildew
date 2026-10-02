# TEST REPORT — CP2 (Hole vertical slice)

Date: 2026-10-02 · Build: `0.1.0-cp2` (versionCode 2), debug APK · Godot 4.7.2-stable (GL Compatibility)
Environment: cloud Linux container (no Android TV, no physical phones). Rendering via xvfb + software GL.

## Summary

| Gate (docs/11 CP2) | Result | Evidence |
|---|---|---|
| Full Hole game from lobby to scoreboard | PASS | unit `test_hole_full_game_*`, LAN `two_players_full_show` (2 rehearsal Qs + 6 Hole rounds over real sockets), phone UI suite, TV tour |
| 2–8 simulation passes | PASS | `test_hole_full_game_two_players`, `..._eight_players`, 60-session soak (`test_soak`), LAN 8-player scenario |
| No content repeat within a game | PASS | `test_director_hole_variants_and_studio_gating`, weighted no-repeat picker |
| APK | PASS (container) | `build/mildew-0.1.0-cp2-debug.apk`, 77.6 MB, v2 signature verified, manifest LEANBACK + INTERNET, pack contains Hole content/photos, Graham cut-outs + map |
| Physical Android TV / phone smoke test | **PENDING USER DEVICE TEST** | checklist in NEXT_BUILD.md |

APK SHA-256: `744bec576c9e514a8ba1188e2ea2468053db00e4e64c693489058cb27165b724`
(Size is dominated by the Godot engine for two ABIs, ~54 MB compressed; content is a few MB.)

## Unit / state tests — `tools/run_tests.sh`

51 tests, 2394 checks, 0 failures, no script errors (every script also compiled with `--check-only`).

New/changed this checkpoint:
- `test_hole.gd` (13): stage scoring 1500/1100/750/500, partial credit (20%, category match, rounded to 50), lock irreversibility, stale-stage 0.5 s grace, pass rules, all-locked skip, silent players never deadlock, reconnect mid-round keeps the lock, late join waits for game end, SCALE variant, OPEN variant (no safety net), Director variant choice + studio-hole gating, validator catches bad items.
- `test_incidents.gd` (7): content validates; 60 simulated 45-minute shows → Tier 0 avg 8.8, Tier 1 avg 1.6, 7/60 shows with no Tier 1; per-tier and per-incident cooldowns; Tier 1 never closer than 240 s; SUPERVISED < STANDARD for Tier 1; CLEAN = zero Tier 1 and only `clean_safe` Tier 0; horror-saturation block; forced incident + Hole doorway hook only in Hole; busy-incident shows still complete all rounds; typo plausibility.
  - Bug found and fixed: SUPERVISED only changed relative weights, not firing chance (70 = 70). Now damps Tier 1 chance ×0.35.
- `test_graham.gd` (3, 266 checks): every cut-out frame imported; every semantic state, mood state and shot hint resolves; no fallback cycles; unknown states fall back to neutral.
- Updated `test_session`, `test_persistence`, `test_director_content`, `test_soak` for the 2-question warm-up and Hole.

## Integration — `tools/run_integration.sh`

- LAN (Node WebSocket phones, real host, timescale 8): 6/6 scenarios. Phones now play Hole (random gamble/pass, lock on final look); server score == sum of rehearsal + Hole result screens; 6 Hole reveals; `hole_lock` seen.
- Phone UI (Chromium, portrait): 13/13 checks, incl. Hole pick tiles → confirm → locked → result, and play-through to END OF TRANSMISSION.
- QR cross-check: 90 matrices, 0 mismatches.

## Visual review (TV tour, `tools/run_tour.sh`) — `docs/testing/cp2_screens/`

Reviewed by eye: ident, title, Viewer Information (picture credits, scrolling), settings (now scrolls; previously ran off-frame), lobby, opening, intro, rehearsal question, Hole sting, Look 1 / lock-in / Look 3 / safety net / reveal, Graham after reveal. Phone: `phone_13…16`.

Fixes made from visual review:
- Teletext subtitles overlapped the Hole answer panels → subtitles move to the top of the picture while the Hole board is up.
- Reveal banner kept full opacity while fading (ghosting over Graham) → banner respects fade alpha; the board now leaves on a hard cut.
- Settings menu (7 rows) overflowed the 4:3 frame → menus scroll in a 6-row window.

## Content

- Hole: 27 items, **25 enabled**, all with real photographs from Wikimedia Commons (PD / CC0 / CC BY only), per-item media metadata (source page, original URL, creator, licence, attribution, crop notes); stage crops authored and previewed against each photo; reveal lines rewritten to match the actual photos. Credits: `docs/CREDITS_MEDIA.md` and in-game Viewer Information Service.
- Disabled until a licensed photo exists: `hole.bowling_ball`, `hole.golf_hole` (procedural placeholders, `quality_status: placeholder`).
- Graham lines: 56 Hole lines + incident lines (draft). Incidents: 8 Tier 0, 6 Tier 1 (draft).
- Content validator: 0 errors.

## Not verified (needs hardware)

Install on Android TV; FPS on mid-range TV (programme viewport + Graham Sprite3D + photo decode); offline TTS; real phone browsers; physical QR scan; Wi-Fi drop/rejoin; audio levels of synthesized crowd/sting (not human-auditioned).
