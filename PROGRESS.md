# PROGRESS — Mildew

Last updated: 2026-10-03 (Europe/London)
Current checkpoint: **CP8 — Full Director / standard broadcast** (CP3–CP7 implemented in this session; CP0–CP2 earlier)
Current build/version: `0.1.0-cp8` (versionCode 8), debug APK
Current branch: `claude/cp3-factual` (contains CP3 → CP8; see git log). APKs: branch `claude/apk-builds`.
Godot version: **4.7.2-stable** (GL Compatibility) — pinned (D001)
Android toolchain: headless non-Gradle export + container v2 signer + TV-launcher patch (D007, D008). Build: `tools/build/build_apk.sh`.
Latest APK: `mildew-0.1.0-cp8-debug.apk` on branch `claude/apk-builds` (SHA-256 `00e612b6…24c5`, see `docs/testing/TEST_REPORT_CP8.md`).

## Executive status

All **eight launch games** are implemented and the Director builds a whole programme:
opening → intros → (rehearsal on new installs) → 5 games chosen by role/variety with an advert, viewer polls, a
**90-second commercial break** at the midpoint (early resume when everyone's back), a ×1.5 finale, the MILDEW AWARDS and
a star prize, then sign-off. Around it: private phone interference, Tier 0–3 incidents, recurring backstage rooms seen
on CCTV whose state persists between sessions, event chains up to Tier 4 machinery, a slowly drifting Announcer, the
{NAME}'S EASY QUESTION punishment and the hidden THE TEST interruption game.

Automated: 114 GDScript test functions (~3,850 checks) green; 300-programme soak, 0 hangs; LAN/phone/Do-Not-Press-That/dev-panel Chromium
suites all green (see TEST_REPORT_CP8). **Still not verified on a real TV or phones** (no devices reachable from the build
environment): every checkpoint's "runs on target hardware" item is **PENDING USER DEVICE TEST**.

## Checkpoint status

| CP | Scope | State | Notes |
|---|---|---|---|
| CP0 | repo/toolchain | VERIFIED | |
| CP1 | LAN lobby, phones, reconnect | IMPLEMENTED (device test pending) | |
| CP2 | Hole | IMPLEMENTED (device test pending) | 25 real photos |
| CP3 | Real or Mildew? + Guess the Genitals, fact archive | IMPLEMENTED | GTG 15 items |
| CP4 | Mildew Survey + Mouthfeel, private interference | IMPLEMENTED | |
| CP5 | Police Sketch | IMPLEMENTED | drawing tested in Chromium touch emulation, not on real phones |
| CP6 | Do Not Press That | IMPLEMENTED | 2,800 generated layouts validated |
| CP7 | The Basement | IMPLEMENTED | 7 cases |
| CP8 | Full Director broadcast | IMPLEMENTED | rooms are procedural CCTV (photographic room plates requested) |
| CP9 | persistence/polish/performance | NOT STARTED | needs device profiling |

### CP3 — Real or Mildew? + Guess the Genitals
| Requirement | State | Files | Verified | Notes |
|---|---|---|---|---|
| 30–40 ROM items, sourced | IMPLEMENTED | `content/games/real_or_mildew/core_cp3.json` (34) | test_rom | all `draft` pending human fact-check; release validation blocks them |
| Text/image formats, factual reveal, confidence wager | VERIFIED | `seg_question.gd`, `quiz_board.gd` | test_rom | D028 |
| Viewer Information Service v1 | IMPLEMENTED | `main.gd` `_viewer_items`, `installation.facts_seen` | test_persistence | sources + picture credits |
| GTG 15–20 items, animal-only, licensed | IMPLEMENTED | `content/games/guess_the_genitals/core_cp3.json` (15 incl. 3 decoys) | test_gtg | D029; validator enforces animal-only |
| Clinical presentation, fact reveal, variants, Rot, fast-answer reactions | IMPLEMENTED | `quiz_board.gd` image layout, Director pacing | test_gtg | decoys ("Genital or Something Else?") |

### CP4 — Mildew Survey + Mouthfeel
| Requirement | State | Files | Verified |
|---|---|---|---|
| 40–60 survey prompts, archive answers, two-player fill | VERIFIED | `content/games/mildew_survey/core_cp4.json` (52), `seg_write_vote.gd` | test_write_vote |
| No self-vote, match normalisation, WHO SAID THAT? / ARCHIVE rounds | VERIFIED | `seg_write_vote.gd` | test_write_vote, Chromium |
| Rare Graham answer alteration (dev-forceable) | VERIFIED | `force.alter_answer` | test_write_vote |
| 40–60 Mouthfeel components, categories, Make It Worse, Graham's anonymous answer, reverse format | VERIFIED | `content/games/mouthfeel/core_cp4.json` (48) | test_write_vote |
| Text survives reconnect/reload | VERIFIED | phone local drafts | Chromium (phone_ui) |
| Private phone interference, force-testable | VERIFIED | `private_interference.gd`, `content/interference/` (22) | test_interference, D031 |
| Mouthfeel optional imagery, Survey "None of these" | PLANNED | | deferred (D030) |

### CP5 — Police Sketch
| Requirement | State | Files | Verified |
|---|---|---|---|
| 30–40 prompts, Body Part variant scaffolding | VERIFIED | `content/games/police_sketch/core_cp5.json` (38) | test_sketch |
| Crude canvas (thin/thick/rub/undo/clear), 45–60 s | VERIFIED | `controller/app.js` scrPSDraw | Chromium |
| 4+ chains, explicit 2-player flow, multi-category voting, fidelity scoring | VERIFIED | `seg_sketch.gd` | test_sketch (2 & 8 players) |
| Bounded bandwidth | VERIFIED | ≤300 strokes/6000 pts, 48 KB drawing frames, others 4 KB | test_sketch |
| Reconnect preserves drawing, local exhibit reuse | VERIFIED | local draft, `installation.sketch_archive` | Chromium reload, test_sketch |

### CP6 — Do Not Press That
| Requirement | State | Files | Verified |
|---|---|---|---|
| 8–12 puzzles, role allocation 2–8, per-phone panels/instructions | VERIFIED | `content/games/do_not_press_that/core_cp6.json` (10), `dnp_puzzle.gd` | test_dnp (2,800 layouts), validator |
| Partial failure consequences, tiers, team + individual bonus, irrelevant controls, blame | VERIFIED | `seg_dnp.gd` | test_dnp, Chromium dnp_ui |
| Timer irregularity (dev-forceable), reconnect, latency tolerance | VERIFIED | `seg_dnp.gd` | test_dnp |

### CP7 — The Basement
| Requirement | State | Files | Verified |
|---|---|---|---|
| 6–8 cases, private evidence, investigations, individual theories, partial credit | VERIFIED | `content/games/basement/core_cp7.json` (7), `basement_case.gd`, `seg_basement.gd` | test_basement |
| Definitive + unresolved, recurring places/people, unreliable clues, 2-player multi-clue | VERIFIED | | validator: every case × 2–8 players |

### CP8 — Full Director
| Requirement | State | Files | Verified |
|---|---|---|---|
| Partial skeleton, tag/variety game selection, finale | VERIFIED | `director.gd` plan_episode/choose_game | test_broadcast |
| Midpoint break, adverts (11 / 9 brands), polls, awards, run-over | VERIFIED | `seg_advert.gd`, `seg_interstitial.gd`, `advert_player.gd` | test_broadcast (D035) |
| Degradation/Complicity/Pressure/Familiarity/mood/relationships | IMPLEMENTED | `director.gd` (since CP1) | unit; behavioural tuning needs play-testing |
| Tier 0–2 incidents + small Tier 3 set | VERIFIED | `incident_engine.gd`, `content/incidents/tier0–3` | test_world, soak |
| Private interference targeting | VERIFIED | D031 | |
| Recurring rooms (5) with persistent state, chains, Tier 4 machinery | VERIFIED | `world_state.gd`, `cctv_view.gd`, `content/world/` | test_world (D036) |
| Announcer progression | VERIFIED | session end_show, stage-gated lines | test_world |
| Punishments + 1 Interruption Game (THE TEST) | VERIFIED | `seg_special.gd` | test_world |
| 45-minute broadcast | IMPLEMENTED | | bots: median 32 min (they answer instantly); humans expected ~45 — needs a real play-test |
| Hundreds-of-sessions simulation | VERIFIED | `tests/tools/soak.gd` | 300 programmes, 0 hangs |
| All 8 games appear | VERIFIED | | test_broadcast, soak |

## Content status
| Library | Count | Quality | Target |
|---|---|---|---|
| Hole | 25 (+2 disabled) | reviewed, real licensed photos | 20–30 ✅ |
| Real or Mildew? | 34 | draft (sources to check) | 30–40 ✅ |
| Guess the Genitals | 15 | draft, licensed images | 15–20 ✅ |
| Mildew Survey | 52 | draft | 40–60 ✅ |
| Mouthfeel | 48 | draft | 40–60 ✅ |
| Police Sketch | 38 | draft | 30–40 ✅ |
| Do Not Press That | 10 templates | draft | 8–12 ✅ |
| The Basement | 7 cases | draft | 6–8 ✅ |
| Adverts | 11 / 9 brands | draft, procedural | 8–12 / 5+ ✅ |
| Viewer polls / easy questions / THE TEST | 15 / 8 / 1 | draft | |
| Incidents | T0 8, T1 6, T2 4, T3 2, chains 4 (one Tier 4) | draft | |
| Private interference | 22 | draft | |
| Rooms | 5 (CCTV procedural) | draft | 4–5 ✅ (photographic plates wanted) |
| Graham lines | CP1–CP8 packs, ~400 lines | draft, **unvoiced** except the 19-line dev library | voice production pending |

## Art/audio status
- Graham: photographic cut-outs (D021/D022). Studio: photographic plates (D026). Hole/GTG: licensed photos.
- New this session: quiz board, write/vote board, evidence board, control-room board, Basement case file, adverts and bumpers,
  viewer poll, awards, CCTV rooms — all drawn procedurally in the programme's 90s style.
- Audio: all synthesized and provisional (incl. new jingle/bumper/banging/room tone/door). Not human-auditioned.
- Graham voice: only 19 development clips + 5 names exist; all new CP3–CP8 lines are subtitle-only until voiced (D024).

## Known limitations / risks
- No device verification. Performance on Android TV unknown (many procedural `_draw` boards; each only draws while visible).
- Programme length measured with instant bots (≈32 min median); human play will be longer — tune `show.games_per_episode`/round counts after a real session.
- Punishment frequency measured with deliberately bad bots (≈0.5/show); expect less with humans.
- Factual content is `draft`; release validation blocks it until reviewed.
- Generated imagery (Graham, plates) licence terms to check before commercial release.

## Next immediate actions
1. **User:** install `mildew-0.1.0-cp8-debug.apk` and run the device checklist in `NEXT_BUILD.md` (now including all eight games).
2. **User (in progress):** photographic room plates, Qwen voice for the new lines.
3. CP9: device profiling, persistence polish (profile history, cross-session Graham grudges), accessibility/legibility pass at 720p.
