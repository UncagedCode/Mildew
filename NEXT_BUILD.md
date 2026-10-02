# NEXT BUILD — Mildew

Checkpoint/build target: **CP2 — Hole vertical slice** (`0.1.0-cp2`, versionCode 2)

## Goal

A complete broadcast in which **Hole** is a real, funny, risk/reward game: a mystery opening is revealed in
stages on the TV, contestants decide on their phones when to gamble and LOCK IN, scoring is server-side, Graham
reacts to bold/foolish locks, the audience reacts, and the programme occasionally makes small production
mistakes (Tier 0) or something slightly odd happens (light Tier 1).

## Required user-visible outcomes

- Hole sting ("ridiculous mystery sting + zooming circular motif") and Graham rules explanation.
- Each round: extreme close-up → partial zoom-out → broader context → 4-option safety net, then full reveal
  with the answer, who locked what and when, points/partial credit chips.
- Phone: candidate list on reveals 1–3 (tap → confirm LOCK IN, irreversible), "SHOW ME MORE" pass, 4 big
  coloured keys on the safety net, honest result screen (stage locked at, points, partial credit).
- At least one variant: **SCALE** round (how big is this hole?) and **ADVANCED OPEN GUESS** (no safety net; Familiarity-gated, dev-forceable).
- Graham line pools for every Hole beat; audience reactions (applause sizes, ooh, aww, silence).
- Tier 0 production mess (mic pop, typo lower third, early applause, late/wrong cuts, off-mic cue, signal tear) and
  light Tier 1 (empty corridor cut, wrong name, odd production caption, wrong audience reaction), plus the Hole
  hook: wrong-camera cut to a dark service doorway → Graham: "Not that one."
- Works for 2 players unchanged (head-to-head), and for 8.

## Required technical outcomes

- `content_kind: "hole"` packs with quality/familiarity/tags/player counts, candidates with broad categories,
  safety-net options, stage crops, scale, image + media metadata. 20–30 items.
- Project-owned procedural hole illustrations (`tools/art/gen_holes.py`), shipped raw (keep importer), decoded off the main thread.
- `SegHole` authoritative segment: stage timers, early lock, pass, stale-stage grace, partial credit, all-locked skip, reconnect-safe.
- Director: format registry with tags, skeleton with Hole as the opening game (+ rehearsal warm-up for new installations),
  Hole content selection without repeats, variant selection, incident engine (tiers, cooldowns, rarity, interference
  setting, tone safeguards) with decision logging.
- Validator: hole schema checks (answer in candidates, safety net ⊂ candidates + contains answer, stages, image exists, media licence fields), incident checks.
- Bots: Hole personalities (risk-taker, cautious, high-accuracy, terrible, horse, AFK).
- Tests: Hole scoring per stage, partial credit, lock irreversibility, stale stage, pass/skip, no repeat in game, 2- and 8-player full shows,
  reconnect mid-round, deadlock soak, incident cooldown/suppression; integration + phone UI updated for Hole.

## Files/systems expected to change

- `src/core/session/segments/seg_hole.gd` (new), `basic_segments.gd`, `session_server.gd`, `protocol.gd`
- `src/core/director/director.gd`, `src/core/director/incident_engine.gd` (new)
- `src/core/content/content_validator.gd`, `config/content_tags.json`, `config/mildew_config.json` (if present)
- `src/broadcast/hole_board.gd` (new), `presenter.gd`, `graphics_layer.gd` (Hole sting), `studio_set.gd` (service corridor), `audio_desk.gd`
- `controller/app.js`, `controller/style.css`
- `content/games/hole/*.json`, `content/graham/lines/hole_cp2.json`, `content/incidents/tier0|tier1/*.json`
- `assets/content/hole/*.jpg`, `tools/art/gen_holes.py`, `tools/audio/gen_audio.py`
- `src/dev/fake_player_bot.gd`, tests, integration scripts

## Content/assets required

- 24–30 Hole items with procedurally generated, project-owned illustrations (provisional art; licence: project-owned).
- New audio: Hole sting, crowd ooh / aww / gasp, mic pop.

## Test gates

- [ ] project/import succeeds
- [ ] unit/state tests pass
- [ ] content validation passes
- [ ] 2-player simulation passes
- [ ] 8-player simulation passes
- [ ] reconnect test passes (mid-Hole)
- [ ] no deadlock in affected game/session path (soak)
- [ ] no content repeat within a game
- [ ] APK export succeeds
- [ ] physical Android TV/phone smoke test (pending: environment has no device)

## Design requirements being satisfied

docs/04 §2 Hole; docs/11 CP2; docs/12 Hole ledger; docs/05 scoring philosophy; docs/03 incident tiers, tone
safeguards, Director logging; docs/02 wrong-camera grammar + audience; docs/08 Hole sting; docs/07 content metadata/validators; config/design_constants.json `hole`.

## Explicit non-goals for this build

- Other launch games (CP3+), adverts, commercial break, awards, recurring-room state persistence (CP8).
- Tier 2+ incidents and private phone interference (CP4/CP8).
- Real photography (needs licensed sourcing; illustrations are owned placeholders-in-style).

## Risks / fallback implementation choices

- Image memory/decoding on mid-range TV: 1600×1200 JPEG decoded on a worker thread, one texture alive at a time.
- Procedural illustrations may read as "illustrated" rather than photographic: acceptable for PoC; content items stay `draft`.

## Definition of done

A 2–8 player broadcast runs lobby → opening → intros → Hole (sting, rules, 5–6 rounds incl. a variant round) →
scores → sign-off, on real sockets and in simulation, with no deadlock, no repeat, correct stage scoring, and an APK built and verified.

---

## Pending from CP1 — on-device checklist for the user

Install: `adb install -r mildew-0.1.0-cpN-debug.apk` (or sideload via a file manager on the TV). Then:

1. App tile "Mildew" appears in the Android TV launcher (it may show the icon instead of a banner). Launch it.
2. SALLOW ident plays with a chime; title menu responds to the remote arrows/OK.
3. BEGIN TRANSMISSION → lobby shows QR, URL (`http://<tv-ip>:8080`) and a 4-letter code. Graham talks.
4. Scan the QR with two phones on the same Wi-Fi. Both should reach the contestant wizard without typing the code.
5. Enter a name → the TV speaks it (if the TV has an offline TTS voice; otherwise subtitles only) → pick a likeness.
6. Floor captain presses BEGIN. Play the full broadcast. Turn one phone's Wi-Fi off mid-question for ~10 s, then on:
   the TV should hold with an honest banner and resume.
7. Press BACK on the remote at any time → TRANSMISSION PAUSED menu → RESUME / END TRANSMISSION.
8. Pause → DEVELOPER TOOLS → TOGGLE DIAGNOSTICS OVERLAY: note the FPS line during the question and the scoreboard.
9. Report: install result (any signature/parse error?), FPS, whether TTS spoke, any phone browser that failed.
