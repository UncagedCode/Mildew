# PROGRESS — Mildew

Last updated: 2026-10-02 12:20 (Europe/London)
Current checkpoint: **CP1 — Real LAN lobby + first playable slice** (CP0 toolchain complete)
Current build/version: `0.1.0-cp1` (versionCode 1), debug APK
Current branch: `claude/cp1-lan-slice` (see git log for commit)
Godot version: **4.7.2-stable** (GL Compatibility) — pinned (DECISIONS D001)
Android toolchain status: headless non-Gradle export + container v2 signer + TV-launcher template patch (D007, D008). Reproducible via `tools/build/setup_container_toolchain.sh`; build via `tools/build/build_apk.sh`.
Latest APK: `build/mildew-0.1.0-cp1-debug.apk` (61 MB, arm64-v8a + armeabi-v7a; not committed — delivered separately; rebuild with the script). SHA-256 recorded in `docs/testing/TEST_REPORT_CP1.md`.

## Executive status

The CP1 slice is implemented end to end and passes every automated gate: one Android TV app hosts the broadcast,
serves the phone controller over local Wi-Fi (HTTP 8080 + WebSocket 8081, no internet), and runs a complete
Director-planned "Studio Rehearsal" programme for 2–8 phones: Sallow ident → home-edition title menu →
BEGIN TRANSMISSION → studio lobby with Graham waiting, QR + URL + room code → contestant wizard on the phone
(name, pronunciation check spoken by the TV, avatar) → podiums appear → opening titles → introductions →
sting → 3 questions answered on phones with server-side scoring → scoreboard → winner → sign-off → END OF
TRANSMISSION, with the 30-second reconnect flow, pause/settings/end on the remote, and dev tooling.
**Not yet verified on real hardware**: no Android TV or physical phone is reachable from the build environment.
The CP1 gate item "APK runs on target" therefore remains **PENDING USER DEVICE TEST** (checklist in NEXT_BUILD.md).

## Checkpoint status — CP0

| Requirement | Status | Implementation/files | Verified how | Notes |
|---|---|---|---|---|
| Inspect repo / import package | VERIFIED | repo had only README; package imported at root (`CLAUDE.md`, `docs/`, `config/`, `schemas/`, `templates/`) | git | handoff README/prompt moved into `docs/` |
| Pin Godot version | VERIFIED | `project.godot`, D001 | headless import/export | 4.7.2-stable |
| Android export toolchain | VERIFIED (container) | `tools/build/*` | APK exported, signature verified, manifest dumped | device install pending |
| Package id / version naming | IMPLEMENTED | `export_presets.cfg`, D003 | manifest dump | |
| Folder structure / progress docs / constants / test harness | VERIFIED | `src/`, `tests/`, `tools/run_tests.sh` | test runs | |

## Checkpoint status — CP1

| Requirement | Status | Implementation/files | Verified how | Notes |
|---|---|---|---|---|
| Mildew boot/ident styling | IMPLEMENTED | `studio_set.gd` (ident rig), `main.gd` | tour screenshots | Sallow gold 3D ident + chime |
| `BEGIN TRANSMISSION` flow | VERIFIED | `main.gd` title menu | tour + manual review | remote: arrows/OK |
| Placeholder-but-on-brand Graham | IMPLEMENTED | `graham_puppet.gd`, `presenter.gd` | mood sheet + tour | 7 moods + activities, sweat/tie vs Pressure; provisional art |
| 4:3 broadcast in 16:9 output | VERIFIED | `programme_view.gd`, `broadcast_crt.gdshader` | screenshots | lobby uses wider layout (monitor + join page) |
| Minimal camera grammar | IMPLEMENTED | `studio_set.gd` cut_to(), presenter | screenshots | cam1–4 + podium CUs; occasional late cuts; operator drift |
| Local HTTP controller hosting | VERIFIED | `http_static_server.gd`, `mildew_host.gd` | integration (incl. exported Linux pack) | path traversal/POST rejected |
| QR / local URL + room code fallback | VERIFIED | `qr_encoder.gd`, `system_layer.gd` | 90-matrix cross-check vs independent encoder; browser test | physical scan pending |
| 2–8 real/fake clients join | VERIFIED | session/host | unit sim + real WebSocket (2, 8, ninth rejected) + browser | |
| Returning/new profile structure | IMPLEMENTED | `save_store.gd`, session `_on_select_profile/_on_create_profile` | unit tests | group "IS THIS ACTUALLY X?" vote PLANNED (D014) |
| Display name + pronunciation scaffolding | VERIFIED | phone wizard, `say_name`, `VoiceService` | browser test (TV speech events) | TTS audibility on TV pending device |
| Simple avatar selection | VERIFIED | `config/avatar_parts.json`, `avatar_painter.gd`, `app.js` | screenshots | identical TV/phone renderers |
| TV podium/contestant representation | IMPLEMENTED | `studio_set.gd` podiums + `podium_screen.gd` | screenshots | CRT screens, answer lamps, real NO LINK |
| Minimal authoritative server | VERIFIED | `session_server.gd`, segments | 27 unit tests, soak, integration | |
| Minimal Director object/state | VERIFIED | `director.gd` | unit tests, dev overlay | axes, tone, mood, relationships, skeleton, decision log |
| One simple test question | VERIFIED | `content/games/studio_rehearsal/questions.json`, `seg_question.gd` | sims + browser | 3 per show from 8 |
| Answer submission / score update | VERIFIED | `seg_question.gd` | phone result sums == server standings | |
| Disconnect/reconnect 30 s flow | VERIFIED | session holds, phone resume token | unit + real sockets + browser | Graham lines at 0s/15s/return/fail |
| Phone portrait UI as Home Response Unit | VERIFIED | `controller/*` | Chromium phone viewport screenshots | real-phone browsers pending |
| Basic fake player support | VERIFIED | `fake_player_bot.gd`, `sim_harness.gd`, host dev menu | tests, tour | 6 personalities |
| Dev network/Director diagnostics | IMPLEMENTED | `dev_overlay.gd` (F3 / pause → DEVELOPER TOOLS) | tour screenshots | FPS/frame/memory line for device profiling |
| Installable APK | IMPLEMENTED | `build/mildew-0.1.0-cp1-debug.apk` | v2 signature verify, manifest, pack listing | **install on TV pending** |
| Manual pause / settings / end | VERIFIED | `main.gd`, `system_layer.gd` | tour + unit (freeze) | Android BACK/MENU/Esc open it |
| Reset Players / History / Mildew | IMPLEMENTED | `save_store.gd`, settings menu | unit tests | double-OK confirmation |

**CP1 gate:** 2 and 8 clients join ✅ · phone input changes TV state ✅ (browser + WebSocket; physical phone pending) ·
reconnect works ✅ · server rejects invalid actions ✅ · APK runs on target ⏳ **pending user device test** · status docs ✅.
→ CP1 is **not yet declared complete**; it is complete pending the on-device smoke test.

## Working now
- Full rehearsal broadcast, 2–8 players, accelerated simulation and real-socket play.
- Reconnect within 30 s resumes the same contestant (resume token in phone localStorage); failure to return drops the player and the show continues with ≥2; everyone gone → Graham "Fine." → transmission ends; one player left → honest "waiting for contestants" hold, new joiners admitted.
- Late joiners wait in spectator mode until a game boundary.
- Versioned saves with migration/backup, installation seed, reset scopes, profile stats updated after each show.
- Content validator (duplicates, answers, tiers, tags, player counts, factual sources/licences, release-mode placeholder block).

## Partially working
- Graham voice: depends on the TV's offline TTS voices (untested on device); subtitles always on by default.
- Same-name verification vote (D014).
- Android TV banner art (D008).

## Known broken / blockers
- No physical-device verification possible from the cloud container (Android TV, phone browsers, Wi-Fi, TTS, performance).
- APK signing uses a project-written v2 signer (D007): if the TV rejects the install with a signature/parse error, report it — fallback is to build on a PC with the Android SDK (`tools/build/build_apk.sh` works there with the real apksigner).

## Networking status
- TV host: pure GDScript; binds all interfaces; LAN IP chosen by `LanInfo` (prefers 192.168/10.x Wi-Fi/Ethernet).
- Controller HTTP: verified (source + exported pack).
- WebSocket/realtime: verified (Node clients + Chromium).
- QR join: encoder verified module-for-module; physical scan pending.
- Real phones tested: **none yet** (Chromium phone emulation only).
- Fake players: yes (in-process loopback using the real protocol).
- Reconnect: verified. Late join: verified.

## Games status
| Game | 2P | 3–8P | Scoring | Content | Broadcast polish | Tests |
|---|---|---|---|---|---|---|
| Hole | – | – | – | – | – | CP2 next |
| Real or Mildew? | – | – | engine ready (SegQuestion) | – | – | CP3 |
| Guess the Genitals | – | – | engine ready | – | – | CP3 |
| Mildew Survey | – | – | – | – | – | CP4 |
| Mouthfeel | – | – | – | – | – | CP4 |
| Police Sketch | – | – | – | – | – | CP5 |
| Do Not Press That | – | – | – | – | – | CP6 |
| The Basement | – | – | – | – | – | CP7 |
| *(Studio Rehearsal — CP1 test segment)* | ✅ | ✅ | ✅ | 8 draft items | sting, board, reveal chips | ✅ |

## Director status
- Episode skeleton: partial skeleton with resolved/unresolved slots (CP1 resolves only the rehearsal).
- Mood/tone balance: tone channels tracked + decay; balancing logic arrives with real formats (CP2+/CP8).
- Graham state: visible mood (relaxed/pleased/amused/irritated/angry/embarrassed/rattled) driven by results/disconnects, drifts back.
- Relationships: favourite/irritant/disappointment/interesting/pity/grudge weights updated from answers/standings.
- Degradation / Complicity / Pressure / Familiarity: state + snapshot; Pressure rises on disconnects and drives sweat/tie; Familiarity gates content tiers.
- Punishments, incidents, private interference, recurring rooms: not yet (CP2+ / CP4 / CP8).
- Announcer: stage-0 line pool (functional continuity voice) wired.

## Content status
- Approved factual items: 0. Placeholder factual items: 0.
- Rehearsal questions: 8 (draft, fictional). Graham lines: ~90 in 35 categories (draft). Announcer lines: 7 (draft).
- Fake adverts / rooms / incidents: 0 (CP8). Validation errors: 0.

## Art/audio status (all provisional, project-owned — `assets/LICENSES.md`)
- Graham: procedural puppet, 7 moods, speaking/blink/stare/look-off/reading/waiting.
- Studio: 3D set — carpet, gradient MDF panels, chrome MILDEW logo, curtains, trusses, plants, lectern, podiums with CRTs.
- Cameras: cam1 Graham MCU, cam2 wide, cam3 podiums, cam4 roaming, podium CUs, title/ident rigs.
- Opening: tunnel + chrome logo + flying ?s + flares, 9 s synthesized theme. Game sting: ray-burst card + brass sting.
- Audience audio: small/medium/big applause layers; deliberate silence on all-wrong.
- Announcer: subtitled (cyan) + TTS. TTS/voice: device offline TTS with pre-rendered hook.

## Testing performed this checkpoint
See `docs/testing/TEST_REPORT_CP1.md`: 28 GDScript tests (incl. 60-session soak), 6 real-socket scenarios, 11 Chromium phone checks, 90 QR matrices, APK verification, 16 TV + 13 phone screenshots in `docs/testing/cp1_screens/`.

## Performance observations
- Device: not measured (no hardware). Rendering budget risk: programme viewport 1440×1080 + 2×MSAA + broadcast shader (5 taps) + Graham 512×640 + up to 8 podium 320×240 viewports, all updating every frame. If the TV is below 60 FPS, first levers: podium viewports update on change only, MSAA off, lower programme viewport scale, fewer lights.

## Design compliance notes
- Graham, studio, audio are provisional procedural placeholders following the art bible (not final assets).
- Studio Rehearsal is a CP1 test segment, not a launch game.
- No interference/incidents yet; "Standard Transmission" setting is stored but has nothing to modulate until CP2+.

## Next immediate actions
1. **User:** install the APK on the Android TV and run the device checklist in `NEXT_BUILD.md`; report results (photos of dev overlay FPS line welcome).
2. Fix anything found on device; then mark CP1 VERIFIED.
3. Start CP2 (Hole vertical slice) per `NEXT_BUILD.md`.
