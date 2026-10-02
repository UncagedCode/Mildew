# NEXT BUILD — Mildew

Checkpoint/build target: **CP3 — Real or Mildew? + Guess the Genitals** (`0.1.0-cp3`, versionCode 3)

Read first: docs/11 §CP3, docs/04 (Real or Mildew?, Guess the Genitals), docs/07 (factual metadata, image approval),
docs/13 (animal-only enforcement), DECISIONS D020 (real photos), D021/D022 (Graham presentation).

## Goal

Three real games in the programme. Prove the sourced-factual content architecture: every factual claim and every
real image carries source/licence/approval metadata, the validator blocks anything missing, and the Viewer
Information Service lists the sources players saw.

## Required user-visible outcomes

- **Real or Mildew?** — 30–40 items, text and image formats (real bizarre fact vs plausible fake), factual reveal with a
  short explanation, a confidence variant (stake points on how sure you are), Graham reactions.
- **Guess the Genitals** — 15–20 items, *animal-only*, clinical presentation (Graham treats it as respectable
  television), biological fact reveal, fast-answer reactions, themed/variant scaffolding, Rot hooks.
- Viewer Information Service v1: facts broadcast on this installation with their sources (not incidents).
- Director picks game order using mechanical variety and opener/middle/finale tags; a 3-game programme.

## Required technical outcomes

- Content kinds `real_or_mildew` and `genitals` (schemas in `schemas/`), factual source fields (citation, URL, retrieved),
  image approval fields; release-mode validation blocks placeholder factual content.
- Animal-only enforcement in the validator (species/taxon field required; human anatomy rejected).
- Real photos via `tools/content/commons_media.py` (PD/CC0/CC BY; standard thumbnail widths; resumable manifest).
  Genital imagery must be scientific/clinical (museum specimens, field-guide style), never sexualised.
- Director: format tags (opener/middle/finale, mechanic), playlist across 3 games, 45-minute synthetic playlist soak.
- Bots: answer behaviour for both games; integration + phone UI updated.

## Content/assets required

- 30–40 Real or Mildew? items with sources; 15–20 Guess the Genitals items with sources + licensed images.
- Graham line pools for both games; stings for both (cheap 90s motion graphics).

## Test gates

- [ ] project/import succeeds; unit tests pass; content validation passes
- [ ] factual validator catches missing source/licence metadata (negative tests)
- [ ] 2- and 8-player simulations of each game; no repeat within a game
- [ ] 45-minute synthetic playlist with the three games completes without crashing (soak)
- [ ] LAN + phone UI integration for both new games
- [ ] APK export succeeds
- [ ] physical Android TV/phone smoke test (pending: no device in environment)

## Explicit non-goals

Survey/Mouthfeel (CP4), Police Sketch (CP5), adverts and commercial break (CP8), Tier 2+ incidents, private interference.

## Risks

- Licensed clinical animal-anatomy photography on Commons is sparse: fall back to museum specimen photos and
  scientific illustrations that are PD (clearly marked), never AI-generated "real" anatomy presented as fact.
- Fact accuracy: every item needs a citation a reviewer can check; items stay `draft` until reviewed.

## Carried over from CP2

- **Graham audio:** import the 19-line development library + 5 names: put the mp3s in
  `tools/graham_factory/generated_audio/` (or any folder) and run `python tools/graham_factory/sync_godot.py [--source DIR]`;
  approve reviewed takes with `--approve id…`. Audition on the TV via the Voice Browser. Re-generate drifting takes
  only with `generate.py regenerate <id>` (no full-library regeneration).

- Find licensed photos for `hole.bowling_ball` (finger holes) and `hole.golf_hole` (cup), then re-enable.
- Human audition of synthesized stings/crowd audio.
- Check the generated-image service terms for Graham cut-outs before any commercial release.

---

## Pending from CP1/CP2 — on-device checklist for the user

Install: `adb install -r mildew-0.1.0-cp2-debug.apk` (or sideload via a file manager on the TV). Then:

1. App tile "Mildew" appears in the Android TV launcher. Launch it.
2. SALLOW ident plays with a chime; title menu responds to the remote. VIEWER INFORMATION lists picture credits and scrolls.
3. BEGIN TRANSMISSION → lobby shows QR, URL (`http://<tv-ip>:8080`) and a 4-letter code. Graham is on screen and talks.
4. Scan the QR with two phones on the same Wi-Fi. Both reach the contestant wizard without typing the code.
5. Enter a name → the TV speaks it (if it has an offline TTS voice; otherwise subtitles only) → pick a likeness.
6. Floor captain presses BEGIN. Play through the rehearsal and the HOLE game: try locking on Look 1, try SHOW ME MORE,
   use the multiple choice. Check the photos look sharp and the pull-back is smooth.
7. Mid-game, turn one phone's Wi-Fi off for ~10 s, then on: the TV holds with an honest banner and resumes.
8. Press BACK on the remote → TRANSMISSION PAUSED → RESUME / END TRANSMISSION.
9. Open `http://<tv-ip>:8080/dev` on a phone, enter the PIN shown under the TV's join panel: add bots, start a show,
   watch the FPS pill during Graham's close-up, the Hole board and the scoreboard. (Pause → DEVELOPER TOOLS still works on the remote.)
10. Report: install result (any signature/parse error?), FPS, whether TTS spoke, any phone browser that failed, anything that looked wrong.
