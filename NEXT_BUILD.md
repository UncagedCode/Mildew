# NEXT BUILD — Mildew

## Current voice-production task — 2026-10-03

1. In Termux, switch to `feature/qwen-voice-pipeline` and run `./mildew voice setup`.
2. `./mildew voice audition welcome_01 --takes 3`; listen with `voice preview ... --audition`.
3. Lock the chosen take: `./mildew voice lock welcome_01 --take <1..3>`.
4. Test directed production: `./mildew voice build correct_01 wrong_01`; listen to both.
5. Once the reference/acting is accepted, `./mildew voice build` generates the 284-line fixed library.
6. Approve selected takes after listening, commit the selected OGGs/index, then build the APK
   using the existing Android toolchain. Models/native source do not ship with the game.

See `tools/voice_pipeline/README.md` and `docs/testing/TEST_REPORT_QWEN_VOICE.md`.
The current CP9 game plan is retained below from the active game branch.

## Current game build plan

Checkpoint/build target: **CP9 — Persistence, polish, performance (serious PoC)** (`0.1.0-cp9`, versionCode 9)

Read first: docs/11 §CP9, docs/09 (persistence), docs/10 (debug/testing), PROGRESS.md, DECISIONS D027–D036.

## Goal

Turn the complete CP8 programme into something that plays well on the real TV with real phones: measured performance,
tuned pacing from a real session, persistence polish, and the content gaps closed.

## Blocking on the user (cannot be done from the build environment)

1. **Device smoke test of the CP8 APK** — checklist below. Report FPS (dev overlay), any phone browser failures,
   programme length, and anything that felt too frequent/rare (punishments, incidents, adverts).
2. **Photographic room plates (optional but recommended)** — same pipeline as the studio plates (D026). One empty,
   real-looking late-90s backstage photo per room, 4:3, no people, no text/logos:
   Green Room (sofa, small fridge, plant), Studio C dark (four podiums), service corridor (exists), prop store
   (shelves, boxes, a mannequin), archive/tape room (tape shelves, TV trolley), and later control room, staff kitchenette,
   loading area, Graham's dressing room, the locked room (door only). Plus, per room, one variant with the door open
   and one with the light off. They would replace the procedural CCTV look in `cctv_view.gd` room by room.
3. Guess the Genitals now has 15 items (5 added from Commons); more are welcome toward 20.
4. **Graham voice** for the new CP3–CP8 line packs (`content/graham/lines/cp3_*`…`cp8_*`), via the graham_factory pipeline (D024).

## Required technical outcomes (CP9)

- Performance: profile on the TV (procedural boards, plate compositing, CRT shader); cap draw work; verify 60 FPS on menus/boards.
- Pacing: adjust `show.games_per_episode`, rounds per game and timers from the first real session; keep the 45-minute target.
- Persistence: Graham cross-session traces (rare grudge/favourite carry-over, "loves a category" misunderstanding), profile
  history screen, reset options covering rooms/chains/announcer (Reset Mildew already wipes the installation).
- Legibility pass at 720p for all new boards; colour-blind check on option colours.
- Release validation run (`ContentValidator.validate(db, true)`) with a list of what blocks release.

## Test gates

- [ ] unit suite + content validation green; 300-programme soak 0 hangs
- [ ] integration suites green (LAN, phone UI, DNPT UI, dev panel, QR)
- [ ] APK export + verification
- [ ] **real Android TV + 2 real phones: one full programme** (user)

---

## On-device checklist (CP8 APK)

Install: `adb install -r mildew-0.1.0-cp8-debug.apk` (or sideload). Then:

1. Launch "Mildew" from the Android TV launcher; ident, title, BEGIN TRANSMISSION.
2. Two or more phones scan the QR on the same Wi-Fi; create contestants; floor captain presses BEGIN.
3. Play a whole programme (≈45 min). Things to look at:
   - every game's phone screen (multiple choice, Hole gamble, typing answers, voting, drawing with a finger, the
     Do Not Press That panel — read your instructions out loud — and Basement evidence cards);
   - the commercial break: everyone presses I'M BACK and the programme resumes early;
   - adverts, viewer poll, awards and star prize;
   - anything odd: a CCTV cutaway, banging, a private message flashing on one phone (they're rare — some programmes have none).
4. Press BACK on the remote mid-game → TRANSMISSION PAUSED → RESUME.
5. Turn one phone's Wi-Fi off for ~10 s mid-game, then on: honest reconnect banner, resume.
6. Dev panel: `http://<tv-ip>:8080/dev` + PIN from the TV — FPS pill, bots, forcing (first game, Easy Question, THE TEST, chain step).
7. Report: install result, FPS, programme length, phone browsers used, anything confusing, anything that made somebody say "what was that?".
