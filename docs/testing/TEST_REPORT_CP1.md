# TEST REPORT — Mildew

Date/time: 2026-10-02 12:40 (Europe/London)
Checkpoint/build: CP1 — Real LAN lobby + first playable slice
Commit: CP1 commit on `claude/cp1-lan-slice` (follows d9a2201)
Godot version: 4.7.2-stable (GL Compatibility)
APK/version: `build/mildew-0.1.0-cp1-debug.apk` (61.2 MB, arm64-v8a + armeabi-v7a, debug keystore, APK Signature Scheme v2)
SHA-256: `f24314fd0715e65f3608e2feb20965da38f56f0335c26b575c435031acbbeb4f` (rebuild after the lobby-text fix will differ; latest hash is printed by `tools/build/build_apk.sh`)
Test environment/device: Anthropic cloud Linux container (no Android device, no physical phones, no Wi-Fi). Phones emulated with Playwright Chromium in a portrait phone viewport.

## Summary

**PARTIAL** — every automated/container gate passes; physical Android TV + phone verification is pending (cannot be performed from the build environment).

## Automated tests

| Suite | Result | Notes |
|---|---|---|
| Project/import + compile all scripts | PASS | `tools/run_tests.sh` compiles every `.gd` under `src/` and `tests/` |
| Unit/state | PASS | 28 tests, 504 checks, 0 failures |
| Content validation | PASS | 0 errors (rehearsal questions, Graham/Announcer lines); validator negative tests pass |
| 2-player simulation | PASS | unit `test_two_player_full_show` + real-socket `two_players_full_show` |
| 8-player simulation | PASS | unit `test_eight_player_full_show` + real-socket `eight_players_and_ninth_rejected` (ninth refused) |
| Reconnect | PASS | resume within 30 s (unit + sockets + Chromium tab reload); drop after timeout and show continues |
| Late join | PASS | `test_late_join_waits_for_boundary` |
| Invalid/state actions rejected | PASS | unit `test_invalid_actions_rejected`, socket `invalid_actions_and_everyone_leaves` |
| Save/migration | PASS | roundtrip, v0 migration, newer-schema preservation, reset scopes |
| Director pacing | PARTIAL | skeleton/log/mood/determinism tests; real pacing arrives with real games (CP2+) |
| Incident cooldowns | N/A | no incidents until CP2 |
| Deadlock (soak) | PASS | 60 randomized accelerated sessions (bots, drops, rejoins): 56 ended normally, 4 closed because everyone left; 0 stuck |
| HTTP controller hosting/security | PASS | 14 checks incl. path traversal and POST rejection |
| Phone controller UI (Chromium) | PASS | 11 checks: QR join w/o code, wizard, pronunciation spoken on TV, duplicate name, reconnect banner, resume, end screen, no JS errors |
| QR encoder cross-check | PASS | 90 matrices identical to an independent encoder (Arase/qrcode-terminal) |
| APK export | PASS | v2 signature verifies; manifest has LEANBACK_LAUNCHER + INTERNET; pack contains controller, fonts, content |

Commands: `tools/run_tests.sh`, `tools/run_integration.sh`, `tools/build/build_apk.sh`, `tools/run_tour.sh`.

## Full-broadcast simulation

- Number of accelerated sessions: 60 (soak) + 6 real-socket scenarios
- Player-count distribution: 2–8 (random)
- Deadlocks: 0 · Crashes: 0 · Missing finale/credits: 0 (every non-closed session reached sign-off)
- Excess incident clustering: n/a (no incidents in CP1)
- Content repeat anomalies: 0 within a show

## Manual device tests

### Android TV
- launch / frame rate / audio / remote pause+settings / QR display: **NOT RUN — no device reachable.** Checklist in `NEXT_BUILD.md` ("Pending from CP1").

### Phone controller
Browsers/devices tested: Chromium (Playwright) at 390×844 portrait only. Real iOS Safari / Android Chrome: **not run**.

## Visual review (this session)
- Re-rendered the 16-shot TV tour (`tools/run_tour.sh`); reviewed lobby, question, intro, Graham mood sheet.
- Fixed: the lobby "FLOOR CAPTAIN" hint overflowed the join panel at 1080p; now two lines inside a taller panel.
- Fixed: offline-TTS re-probe no longer retries forever on devices with no TTS voice (was logging an error every 5 s).

## Performance
- Not measurable without hardware. The debug overlay (F3 / pause → DEVELOPER TOOLS) shows FPS, frame time, memory and draw calls for on-device profiling.

## Failures / regressions
None in automated suites.

## Known acceptable provisional limitations
1. Graham, studio, audio are procedural provisional assets (art direction respected; not final).
2. APK signed by a project-written v2 signer with the Godot debug keystore (D007); first real install is the decisive check.
3. No Android TV banner art (D008).
4. Same-name group verification vote not yet built (D014, planned).

## Checkpoint gate
- [x] 2 and 8 clients can join
- [~] real phone input changes TV state — verified with real WebSocket clients and Chromium; physical phone pending
- [x] reconnect works
- [x] server rejects invalid state action
- [ ] APK runs on target — **pending user device test**
- [x] status docs updated (`PROGRESS.md`, `NEXT_BUILD.md`, `DECISIONS.md`, this report)
