# PROGRESS — Mildew

Last updated: 2026-10-02 (Europe/London)
Current checkpoint: **CP2 — Hole vertical slice** (CP0 complete; CP1 complete pending device test)
Current build/version: `0.1.0-cp2` (versionCode 2), debug APK
Current branch: `claude/cp2-hole` (see git log)
Godot version: **4.7.2-stable** (GL Compatibility) — pinned (D001)
Android toolchain: headless non-Gradle export + container v2 signer + TV-launcher patch (D007, D008). Build: `tools/build/build_apk.sh`.
Latest APK: `build/mildew-0.1.0-cp2-debug.apk` (77.6 MB; not committed). SHA-256 in `docs/testing/TEST_REPORT_CP2.md`.

## Executive status

CP2 is implemented and passes every automated gate. A broadcast now runs lobby → opening → introductions →
(two-question studio rehearsal on a new installation) → **HOLE** (sting, rules, 6 rounds with staged reveals of
real photographs, early-lock gambling on the phone, safety-net multiple choice, SCALE and NO SAFETY NET variants,
partial credit, audience reactions, Graham commentary) → scores → winner → sign-off, for 2–8 phones, with Tier 0
production mess and light Tier 1 irregularities scheduled by the Director's incident engine.
Graham is now a **photographic composited presenter** (alpha cut-outs over our own studio, D021/D022) with
blinks, breathing, mouth cycle and TV editing that cuts away while he keeps talking.
**Still not verified on hardware** (no TV/phones reachable from the build environment): CP1 and CP2 gate items
"APK runs on target" remain **PENDING USER DEVICE TEST** (checklist in NEXT_BUILD.md).

## Checkpoint status — CP2

| Requirement | Status | Implementation/files | Verified how | Notes |
|---|---|---|---|---|
| 20–30 Hole items | VERIFIED | `content/games/hole/core_cp2.json` (27; 25 enabled) | validator, tests | real Commons photos, `reviewed`; 2 disabled pending photos |
| Real photos + licence metadata | VERIFIED | `tools/content/commons_media.py`, `tools/content/hole_photos.json` (+`.media.json`), `assets/content/hole/*.jpg` | stage previews, tour | PD/CC0/CC BY only; credits `docs/CREDITS_MEDIA.md` + Viewer Information Service |
| Multi-stage reveal | VERIFIED | `seg_hole.gd`, `hole_board.gd` | unit + tour | 3 looks + safety net; log-space dolly pull-back |
| Early lock / pass / grace | VERIFIED | `seg_hole.gd`, `protocol.gd` (`lock`, `pass`) | unit + LAN + Chromium | irreversible, confirm step on phone |
| Scoring values + partial credit | VERIFIED | `seg_hole.gd`, `config/design_constants.json` hole.* | unit | 1500/1100/750/500; 20% for right category on looks 1–3 |
| Variants | VERIFIED | SCALE, OPEN (familiarity-gated), studio hole (tier 3, rare) | unit | dev-forceable via `director.force` |
| Two-player support | VERIFIED | unchanged rules, head-to-head | unit + LAN | |
| Short game sting | IMPLEMENTED | `graphics_layer.gd` `_draw_sting_hole`, `sting_hole` audio | tour | audio synthesized, not auditioned |
| Graham line pools | IMPLEMENTED | `content/graham/lines/hole_cp2.json` (56) | sims | draft copy |
| Audience reactions | IMPLEMENTED | `audio_desk.gd` crowd ooh/aww/laugh/gasp, applause sizes, deliberate silence | tour | synthesized |
| Content quality metadata + validator | VERIFIED | `content_validator.gd` `_validate_hole`, `_validate_media`, `_validate_incident` | unit | |
| Tier 0 + light Tier 1 incidents | VERIFIED | `incident_engine.gd`, `seg_incident.gd`, `content/incidents/*`, presenter `_incident` | `test_incidents` (rates, cooldowns, settings, safeguards) | Hole doorway "Not that one." hook |
| Photographic Graham (D021/D022) | VERIFIED (render) | `tools/art/import_graham_cutouts.py`, `config/graham_cutouts.json`, `graham_presenter.gd`, `studio_set.gd` | `test_graham`, gallery `docs/testing/graham_gallery.jpg`, tour | 25 semantic states; dev gallery (F11/F12) |
| TV editing grammar | IMPLEMENTED | `presenter.gd` `_shot_graham_line`, `config/graham_shots.json` | tour | speech continues over cutaways/graphics |
| Subtitle placement over game graphics | VERIFIED | `graphics_layer.gd` `bottom_busy` | tour | |
| APK | IMPLEMENTED | `build/mildew-0.1.0-cp2-debug.apk` | signature, manifest, pack listing | **device install pending** |

**CP2 gate:** full Hole game lobby→scoreboard ✅ · 2–8 simulation ✅ · no repeat within game ✅ · APK ✅ (container) ·
on-device ⏳ **pending user device test**. → CP2 is complete pending the on-device smoke test.

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
- Everything from CP1 (lobby, profiles, reconnect, late join, pause/settings/reset, dev tools).
- Full Hole game for 2–8 players over real sockets; phones gamble/pass/lock; server-side scoring; reveal chips per contestant.
- Incident engine: Tier 0 (mic pop, typo lower third, early applause, late cut, wrong camera, off-mic cue, signal tear, captions) and Tier 1 (empty corridor, Hole doorway, wrong name, odd caption, wrong audience reaction, floor shot) with rarity, cooldowns, temperament, interference setting and tone safeguards.
- Photographic Graham in the 3D studio on all cameras; dev Graham gallery.
- Viewer Information Service: picture credits for every real photo.

## Partially working
- Graham voice: device offline TTS (untested on device).
- Graham motion excerpts only in plate mode (cut mode has stills + compositing animation).
- Same-name verification vote (D014). Android TV banner art (D008).

## Known broken / blockers
- No physical-device verification possible from the cloud container.
- No licensed real photos yet for bowling-ball finger holes and a golf cup (items disabled).
- Generated-image service terms for the Graham cut-outs must be checked before any commercial release.

## Networking status
Unchanged from CP1 (verified in container); Hole adds `lock`/`pass` actions. Real phones tested: none yet.

## Games status
| Game | 2P | 3–8P | Scoring | Content | Broadcast polish | Tests |
|---|---|---|---|---|---|---|
| Hole | ✅ | ✅ | ✅ stage + partial | 25 real photos (reviewed) | sting, monitor board, dolly, reveal chips, crowd | ✅ unit/LAN/phone |
| Real or Mildew? | – | – | engine ready (SegQuestion) | – | – | CP3 |
| Guess the Genitals | – | – | engine ready | – | – | CP3 |
| Mildew Survey | – | – | – | – | – | CP4 |
| Mouthfeel | – | – | – | – | – | CP4 |
| Police Sketch | – | – | – | – | – | CP5 |
| Do Not Press That | – | – | – | – | – | CP6 |
| The Basement | – | – | – | – | – | CP7 |
| *(Studio Rehearsal — warm-up, new installs only)* | ✅ | ✅ | ✅ | 8 draft | ✅ | ✅ |

## Director status
- Format registry; `plan_episode` (warm-up for new installs, then Hole via `plan_game`); Hole item picking (weighted, no repeat, studio-hole cap) and variant choice; decision log.
- Incident engine (above); show-time clock freezes on holds.
- Mood/relationships/axes as CP1; Tier 2+ incidents, private interference, rooms: not yet (CP4/CP8).

## Content status
- Hole: 25 enabled items with real photos (`reviewed`), 2 disabled placeholders. Incidents: 8 Tier 0, 6 Tier 1 (draft). Graham lines: CP1 pools + 56 Hole + incident lines (draft).
- Approved factual items: 0 (Hole reveal facts are light; CP3 brings sourced factual content). Validation errors: 0.

## Art/audio status
- Graham: photographic alpha cut-outs (user-supplied, generated), composited — provisional pending licence review.
- Hole imagery: real licensed photos. Studio: restyled set (sage/blue panels, chrome, curved MILDEW sign) — procedural.
- Audio: synthesized sting/crowd/servo/mic pop — provisional, not human-auditioned.

## Testing performed this checkpoint
See `docs/testing/TEST_REPORT_CP2.md`: 51 GDScript tests (2394 checks), 6 real-socket scenarios, 13 Chromium phone checks, 90 QR matrices, APK verification, TV + phone screenshots in `docs/testing/cp2_screens/`.

## Performance observations
- Device: not measured. New load: one 1600×1200 photo texture at a time (threaded load), Graham Sprite3D (815×1086 lossy texture swaps). Levers as CP1.

## Design compliance notes
- Hole follows docs/04 §2; incidents follow docs/03 tiers (no Tier 2+ yet); programme never explains irregularities; real connection status never faked.
- Graham presentation follows the user's low-budget direction (D021) and approved compositing (D022).

## Next immediate actions
1. **User:** install the CP2 APK on the Android TV and run the device checklist in `NEXT_BUILD.md`.
2. Optionally supply/approve real photos for bowling-ball finger holes and a golf cup.
3. Start CP3 (Real or Mildew? + Guess the Genitals) per `NEXT_BUILD.md`.
