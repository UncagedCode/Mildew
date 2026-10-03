# DECISIONS — Mildew Implementation Log

Records implementation decisions and any proposed design deviations (template: `templates/DECISIONS.md`).
**Rule:** anything that would alter locked product behaviour, creative direction, platform expectations,
content boundaries, player count, networking model or major UX is marked *User approval required: yes*
and is **not** implemented until approved.

**Open design-change proposals awaiting the user: none.**

---

### 2026-10-02 — D001 Engine pinned: Godot 4.7.2-stable
**Type:** toolchain · **Requirement:** CLAUDE.md §1 "pin exact Godot 4.x version once the first Android TV build is established".
**Decision:** Godot **4.7.2-stable** (latest stable at time of work), GL Compatibility renderer on all platforms (mid-range Android TV GPUs, max portability). `project.godot` `config/features` = 4.7.
**Impact:** do not casually upgrade. **Approval:** not required.

### 2026-10-02 — D002 Repository layout: repo root is the Godot project
**Type:** implementation · **Requirement:** docs/07 suggested layout (`content/`, `assets/`, `config/`, `schemas/`).
**Decision:** `project.godot` at repo root so `content/`, `config/` are `res://` paths. Code in `src/` split by logical layer: `src/core/**` (platform-agnostic server, Director, content, persistence — pure RefCounted, no scene tree), `src/net/**` (sockets), `src/broadcast/**` (TV presentation), `src/dev/**` (dev tools), `src/app/` (entry). `docs/`, `tools/`, `templates/` carry `.gdignore`; export excludes docs/tools/tests/templates/schemas. Handoff files `README_HANDOFF.md` / `PROMPT_TO_CLAUDE_CODE.md` live in `docs/` (CLAUDE.md stays at root).
**Approval:** not required.

### 2026-10-02 — D003 Application identity & version naming
**Decision:** package `com.uncagedcode.mildew`, display name "Mildew". Version name `0.1.0-cp<N>` per checkpoint, versionCode = monotonically increasing integer (CP1 = 1). APK file `build/mildew-<version>-<debug|release>.apk`.
**Approval:** not required (can be renamed before any public release).

### 2026-10-02 — D004 Networking: pure-GDScript HTTP + WebSocket, JSON protocol v1
**Requirement:** docs/06 "choose the simplest reliable path that can later be implemented on another host behind the same protocol".
**Decision:** `HttpStaticServer` (TCPServer, GET/HEAD, Connection: close) serves `res://controller` on **8080**; `WsServer` (TCPServer + WebSocketPeer.accept_stream) on **8081**; both search up to 10 ports upward if busy. No Kotlin/Android code. Protocol messages documented in `src/core/net/protocol.gd` (versioned, `Protocol.VERSION = 1`). Payload limit 4 KB, 30 msgs/s rate limit, app-level ping every 2 s, silent socket closed after 9 s. The QR encodes `http://<lan-ip>:<port>/?k=<ephemeral join key>` (no code entry); manual path = URL + 4-letter room code (consonants only, avoids accidental words).
**Why:** identical code runs on Android TV, desktop and any future stronger Godot host (e.g. Xbox path); fully testable headless.
**Approval:** not required.

### 2026-10-02 — D005 Server-driven timeline with freezable "show time"
**Decision:** `SessionServer` owns all timing; segments advance on *show time*, which freezes during manual pause, the 30 s reconnect window, and "fewer than 2 connected contestants". The TV only renders events. This makes accelerated headless simulation run the real logic and guarantees nothing advances while a player is missing.
**Approval:** not required.

### 2026-10-02 — D006 Real status is presented outside the fiction
**Requirement:** docs/01 #88–89, docs/13 networking boundaries.
**Decision:** genuine connection/hold information is drawn only by `SystemLayer` (pillarbox / full-width banner, plain styling) on the TV and by the phone's `#sysbar` + link LED. Fictional effects (shader, future interference) live only inside the 4:3 programme viewport, so they *cannot* overlay or disguise real status. Podium "NO LINK" is shown only for real disconnects.
**Approval:** not required.

### 2026-10-02 — D007 APK signing in the cloud container (no Android SDK access)
**Type:** toolchain. **Problem:** the build container cannot reach dl.google.com / Maven / PyPI / npm, so the Android SDK (apksigner, zipalign, Gradle deps) is unavailable.
**Decision:** use Godot's prebuilt (non-Gradle) Android template, which Godot aligns itself, and supply an apksigner-CLI-compatible **APK Signature Scheme v2** signer (`tools/build/apksigner_v2.py`) through a stub SDK layout (`tools/build/setup_container_toolchain.sh`). v2-only is valid for minSdk 24 (also what the official apksigner does at that level). Signed with Godot's auto-generated **debug keystore** for CP1.
**Verification:** the signer's verifier recomputes the content digest and signature; every APK is checked by `tools/build/build_apk.sh`. There was no reference v2-signed APK available offline to cross-check against the official tool, so **first install on a real device is the decisive check** (listed in NEXT_BUILD.md).
**Impact:** on a machine with the Android SDK, use the real apksigner/Gradle; nothing in the project depends on the stub. A release keystore must be created and kept by the user before any distribution (not needed for sideloaded PoC builds).
**Approval:** not required (toolchain only).

### 2026-10-02 — D008 Android TV launcher entry via patched template
**Problem:** Godot 4.7's non-Gradle export ignores `package/show_in_android_tv`, so the APK lacked `LEANBACK_LAUNCHER` (would not appear on the Android TV home screen).
**Decision:** `tools/build/patch_tv_template.py` adds the `LEANBACK_LAUNCHER` category to the export templates' binary manifest once (applied by the setup script); Godot then exports/aligns/signs normally. Verified in every build by `build_apk.sh`.
**Known limitation:** no `android:banner` yet (Google TV shows the app icon/name tile). A proper 320×180 banner needs a Gradle build — planned when an SDK-capable build environment exists.
**Approval:** not required.

### 2026-10-02 — D009 Bundled fonts
**Decision:** InterDisplay Black/BlackItalic (OFL 1.1), Liberation Sans/Serif (OFL 1.1), DejaVu Sans Mono Bold (Bitstream Vera licence). Copied into `assets/fonts/`; controller copies use Godot's "keep" importer so the raw `.ttf` ships in the pack and is served to phones. See `assets/LICENSES.md`.
**Approval:** not required.

### 2026-10-02 — D010 Provisional Graham: procedural puppet behind a presenter API
**Requirement:** CLAUDE.md §4 hybrid FMV presenter; docs/08 required PoC states.
**Decision:** `GrahamPuppet` draws a believable (non-mascot) late-40s/50s presenter bust — side-parted greying hair, big gold glasses, burgundy suit, loud tie, heavy makeup, sweat that rises with Pressure, tie loosening under high Pressure — composited into the 3D studio on a quad and softened by the broadcast shader. API: `set_mood`, `set_activity` (idle/speaking/waiting/stare/look_off/reading/laughing), `speak(seconds)`, `set_pressure`. A future FMV-loop renderer replaces the node without touching Director/session/presenter.
**Status:** provisional art; real filmed/rendered loops remain a production task.
**Approval:** not required.

### 2026-10-02 — D011 Voice: device offline TTS + teletext subtitles
**Requirement:** CLAUDE.md §13 hybrid voice pipeline, no runtime internet.
**Decision:** `VoiceService` plays a pre-rendered asset when a line declares `audio`, else uses the TV's offline TTS (`DisplayServer.tts_*`, Android TextToSpeech), else stays silent. Subtitles in Ceefax style are **on by default** (speaker colours: Graham white, Announcer cyan, pronunciation test yellow) so lines always land even with poor/no TTS. Pronunciation check: the TV speaks the name; the phone confirms or lets the player spell it phonetically; `speech_name` is stored separately from `display_name`.
**Approval:** not required.

### 2026-10-02 — D012 CP1 "one simple test question" = Studio Rehearsal
**Decision:** a data-driven multiple-choice "Studio Rehearsal" segment (3 questions per show from a pool of 8, fictional/non-factual) using the generic server-authoritative question engine that CP3 will reuse for Real or Mildew? / Guess the Genitals. It is **not** one of the eight launch games and will be retired or demoted to a warm-up once real games exist. Scoring uses the normal scale (1,000 + speed bonus capped at 15%, small streak bonus, wrong = 0).
**Approval:** not required.

### 2026-10-02 — D013 Starting the show / floor captain
**Decision:** the earliest-joined connected contestant is "floor captain" and gets the BEGIN button (needs ≥2 connected). The TV remote's OK also starts (normal gameplay never *requires* the remote). Captain also triggers "Another broadcast".
**Approval:** not required.

### 2026-10-02 — D014 Same-name returning profile: self-claim now, group vote later
**Requirement:** CLAUDE.md §11 / docs/06: Graham "We've had a Stacy before", other phones vote `IS THIS ACTUALLY STACY?`.
**Implemented now:** exact active duplicates rejected (case/space-insensitive); a new name matching an *inactive* profile is never auto-merged — the phone asks "WE'VE HAD A STACY BEFORE. IS THIS YOU?" (claim → association; no → must choose a distinguishable name). Graham line pool `name_match` exists.
**Not yet:** the other-phones verification vote. Tracked as **PLANNED** (profiles polish, CP9 or earlier). This is a staged implementation of the locked behaviour, not a change to it.
**Approval:** not required.

### 2026-10-02 — D015 Late join and lobby grace
**Decision:** late joiners wait in spectator mode and are integrated only at a game boundary (never between questions of a game). If the show is held for lack of players, a newcomer is admitted immediately. Lobby players whose phones vanish keep their podium for 45 s.
**Approval:** not required.

### 2026-10-02 — D016 Name character set
**Decision:** names 1–16 characters (speech form ≤40), Latin/Latin-Extended/Greek/Cyrillic letters, digits, spaces and basic punctuation; must contain a letter/digit. Reason: guarantees the TV fonts and TTS can render/speak them. Adult profanity is allowed. Reserved names (e.g. "Graham") are accepted but trigger a Graham reaction.
**Approval:** not required.

### 2026-10-02 — D017 Familiarity tier formula (provisional)
**Decision:** installation familiarity tier = clamp(1 + broadcasts_played / 3, 1, 5). Content queries are gated by tier. To be tuned with CP3 content.
**Approval:** not required.

### 2026-10-02 — D018 Dev tooling inclusion
**Decision:** developer tools (overlay, fake players, simulated drops, timescale) are available only when `OS.is_debug_build()`; CP1 ships a *debug* APK so the user can use them on the TV (pause menu → DEVELOPER TOOLS). Release builds hide them. Bots may use an answer "oracle" — dev only, never exposed to phones.
**Approval:** not required.

### 2026-10-02 — D019 Provisional procedural assets
**Decision:** carpet, curtains, flare, icon (`tools/art/gen_textures.py`) and the whole audio kit (`tools/audio/gen_audio.py`: opening theme, lobby bed, sting, ident chime, UI sounds, three applause layers) are generated procedurally — owned, no licensing risk, on-brand. All are **provisional** and tracked in PROGRESS.md.
**Approval:** not required.

### 2026-10-02 — D020 Art direction clarified by the user: assets must look real
**Type:** user direction (creative). **Source:** user, 2026-10-02: "Most things should appear real even if they are generated"; Hole images in particular should be real photos.
**Decision:** the target look for content imagery, Graham, studio and audio is *photographic/realistic* (then degraded by the 1998 broadcast treatment), not illustrated or cartoon. Generated assets are acceptable only if they read as real footage/photos.
**Consequences:**
- Hole / Guess the Genitals / Real or Mildew? imagery: real licensed photographs (Wikimedia Commons, PD/CC0/CC-BY preferred; licence + attribution metadata required) fetched by a reproducible script. Procedural illustrations from D019/`gen_holes.py` are **placeholders only** and must be replaced. Blocker: build environment needs `commons.wikimedia.org` (search + licence metadata) in addition to `upload.wikimedia.org`.
- Graham: the procedural puppet (D010) is a placeholder. Target is a photoreal presenter (filmed actor, or AI-generated photoreal stills/loops produced outside this environment). Implementation: a frame/loop-based presenter renderer that loads per-state media (idle, speaking, moods...) behind the existing presenter API, so real assets can be dropped in.
- Studio/rooms: move toward realistic PBR materials, photo-sourced textures and lighting.
- Audio: synthesized crowd/music remain placeholders; real recorded/licensed audio preferred.
**Approval:** given by user.

### 2026-10-02 — D021 Low-budget production strategy: still-image / broadcast compositing (user direction)
**Type:** user direction (production/creative). **Supersedes parts of:** D010 (procedural puppet), D020 (Graham target).
**Direction:** do not assume large amounts of AI-generated FMV. `references/graham/graham_reference_performance_v1.mp4` is the canonical Graham reference. Normal Graham presentation = reusable photoreal **still-image performance states** animated/composited in Godot: breathing, blinks, small eye-direction changes, restrained mouth states, tiny head/body drift, cue-card movement — concealed by authentic TV editing (cuts, reaction cutaways, graphics, scoreboards, analogue effects, audience audio, framing). Graham must never sit static for long. His speech frequently continues over scoreboards, questions, podium shots, avatars, archive footage and game graphics.
**Reserve real FMV for:** openings/major introductions, important backstage reactions, Graham losing his temper, rare off-air material, major Broadcast Incidents.
**Adverts:** cheap late-90s motion graphics (stills, typography, jingles, VO, simple animation). **Backstage feeds:** stills + fluorescent flicker, camera noise, subtle zoom/drift, moving shadows, audio, small animated elements.
**Intent:** a deliberate strange 1990s TV / interactive CD-ROM hybrid — not a downgrade. Priority: PoC looks and feels like Mildew without further paid generation.
**Pending:** a reference pack (being produced by the user) will supply Graham stills; the GrahamStills renderer is built to consume it. The BBC bug in the reference video must be cropped/removed from anything derived from it.
**Approval:** given by user.

### 2026-10-02 — D022 Graham as composited alpha cut-outs over the Mildew studio (user approved "option 1")
**Type:** implementation of D021, approved by user. **Supersedes:** full-frame plate playback as the primary Camera 1 path.
**Problem:** the ChatGPT reference-pack plates have a baked-in generated studio (and the reference video a BBC bug), so they cannot sit in our own art-bible set, and wide/podium shots could not include Graham.
**Decision:**
- Graham states are supplied as transparent PNG cut-outs (`references/graham/cutouts_v1`, `cutouts_v2`, `cutouts_v2/alternates`; masters never modified).
- `tools/art/import_graham_cutouts.py` registers every frame to the base body `talk_closed` (phase correlation). Talking frames contribute only a feathered lower-face patch and blink frames only an eye-band patch, so the body never shimmers. Output: `assets/graham/cut/*.png` (scaled 0.75, lossy WebP import) + `config/graham_cutouts.json` (frames, semantic states, blinks, variants, camera_motion, talk_cycle, registration report).
- `GrahamPresenter` drives a `Sprite3D` standing at the lectern inside the 3D studio, so all cameras (cam1 close-up, wides, podium reverses) see the same Graham. Semantic states + fallback chains; Director code never sees filenames. Plate mode (`graham_states.json`) remains the fallback renderer; pack motion excerpts work only in plate mode.
- Studio restyled after the reference composition but owned: sage/blue panels, chrome trim, curved green MILDEW sign behind Graham, low lectern. No broadcaster branding anywhere.
- Speech: mouth cycle is capped to short visible bursts (≤3 s) then the edit cuts away while the voice continues (`config/graham_shots.json`).
- Tests: `tests/unit/test_graham.gd` validates frames exist, every semantic state resolves, no fallback cycles, shot hints reference known states.
**Known limits:** two cut-outs are misframed (`*_single`) and never used in loops; generated-image service terms must be checked before commercial release.
**Approval:** given by user ("I agree with 1").

### 2026-10-02 — D023 Phone dev panel (debug builds only)
**Type:** user direction (tooling). **Source:** user: the debug tools needed a keyboard; wants to connect a phone as a debugger, add bots and watch them play.
**Decision:** the TV host serves `http://<tv>:<port>/dev` **only when `OS.is_debug_build()`**. The page asks for a 4-digit PIN shown on the TV (under the lobby join panel, in the corner during the show, and in pause → DEVELOPER TOOLS); the PIN is random per app run (`--dev-pin` fixes it for tests). After the PIN, the phone's WebSocket is detached from the game session (never a player, never counted) and accepts dev commands: add/remove/drop/reconnect bots (with personality), start show, pause/resume (opens the real TV pause menu), timescale, force next Hole variant / item / incident, transmission setting, TV overlay pages, Graham gallery/talk, restart transmission. The TV pushes state twice a second: phase, segment, holds, players, FPS, Director axes, recent decisions, incidents and a live event feed.
**Rules kept:** dev tools are never required (everything also on the remote/keyboard); release builds register no `/dev` route; three wrong PINs close the socket; a forced Hole variant now lands on the first eligible round (it previously waited until round 3+).
**Tests:** LAN scenario `dev_panel_drives_bots_only_show` (20 checks) and Chromium `tests/integration/dev_panel_ui.mjs` (10 checks).
**Approval:** not required (dev tooling; no product behaviour change).

### 2026-10-02 — D024 Graham voice: local authored audio + name bank (user direction)
**Type:** user direction (`tools/graham_factory/CLAUDE_INTEGRATION.md` on main). **Supersedes for Graham:** CLAUDE.md §13's runtime-TTS path for dynamic lines.
**Decision:** Graham's voice is pre-rendered audio shipped in the game. `GrahamVoiceService` (autoload `GrahamVoice`) plays clips by semantic id through `GrahamVoiceIndex` (`config/graham_voice_index.json`, rebuilt by `tools/graham_factory/sync_godot.py` from `manifest.json`). API: `say(id)`, `say_name(name)` (case-insensitive name bank: Aaron, Elijah, Grace, Josh, Donna → `name_*`), `say_intent(intent, {mood})` (`config/graham_voice_intents.json`), `say_sequence(ids)`, `wait_finished()`; all asynchronous; a new line interrupts the old. Dedicated `Graham` audio bus (HPF → EQ6 → LPF → compressor) in `default_bus_layout.tres`.
**Rules:** no ElevenLabs/cloud call anywhere in the game; missing clips log a clear warning (debug) and the subtitle carries the line; Android/system TTS is a *debug-build-only* developer fallback, on-screen as `[DEV TTS]`, switchable in settings, and unreachable in release (tested). Clip status `missing | development | approved`; the current 19-line library + 5 names are **development** audio; release validation reports anything not approved.
**Game wiring:** voiced lines in `content/graham/lines/voice_dev.json` reuse manifest text exactly (validator enforces subtitle == recording) and are preferred by the Director when their clips exist; name-led lines speak the recorded name; the phone pronunciation check only runs for names Graham can say (debug builds may use the flagged fallback); rejecting the recording stores a non-matching speech form. Announcer keeps device TTS for now.
**Dev tools:** Voice Browser on the TV overlay (pause → DEVELOPER TOOLS → VOICE BROWSER) and in the phone `/dev` panel (play id / name / intent, stop, reload index).
**Pending:** the audio files themselves are not in the repository (factory output is git-ignored); import with `sync_godot.py` once supplied.
**Approval:** given by user.

### 2026-10-02 — D025 Studio restyle after the Graham reference video (user direction)
**Type:** user direction ("make the whole studio feel closer to the reference video"). Refines D022's set.
**Decision:** Camera 1 is now the reference's medium shot (head near the top, cue cards at the bottom). Behind Graham: a wrap-round sponge-painted sign with chrome bands and soft-serif lettering + orange swoosh, a row of coloured PAR cans under a black pelmet at the top of frame, angled green flats left, a cream pillar with a red-framed monitor right, a chrome-rimmed round table at his waist, painted blue wall, navy ring-pattern carpet. Graham's desk lowered to 0.72 m (thin edge at the bottom of frame). Whole studio repainted to match (sponge-green flats with chrome trim, matching contestant sign, PAR cans on the truss); CG-looking foam spores, blob plants, curtains and the giant chrome logo removed. Warmer, softer grade with mild glow. Textures generated by `tools/art/gen_studio_ref.py` (owned; Fraunces OFL font for the sign lettering). No broadcaster branding.
**Approval:** given by user.

### 2026-10-02 — D026 Studio as photographic plates (user approved; supersedes D025's 3D-set look)
**Type:** user direction + approval. User: the studio must look like a real game-show studio, "a full new approach", not a repaint. Option chosen: photographic plates.
**Decision:** every studio camera angle is a still photograph (plate) of an empty, real-looking late-90s studio, produced outside the build (ChatGPT, like Graham's cut-outs; request in `references/studio/REQUEST_plates_v1.md`). `PlateStage` (in the programme viewport) composites live elements on top: podium screens perspective-mapped onto the photographed CRTs (unused podiums stay switched off), Graham's cut-out at his mark with breathing/sway, an optional foreground layer (desk/table edge in front of him), additive answer-lamp glows and rig-light flicker, and slow operator drift. While a plate is on air the 3D studio is not rendered (`disable_3d`), which also cuts GPU cost on the TV. Cameras without a plate (titles, ident) fall back to 3D. Plates and hotspots are data (`config/studio_plates.json`); the camera grammar (`cut_to`, `frame_podium`, cutaways, incidents) is unchanged.
**Now:** stand-in plates rendered from the 3D set by `tests/tools/render_plates.gd`, which also computes hotspots, so the pipeline runs end to end today. Real plates replace them entry by entry; hotspots for photographs are authored by hand (dev panel → PLATE HOTSPOTS shows the overlay on the TV).
**Consequences:** fixed angles (no free 3D moves); multiple contestants are represented on podium screens as before; consistency across plates depends on the generated batch.
**Approval:** given by user ("Photographic plates").
**Update 2026-10-02 — batch v1 integrated.** The user's ChatGPT plate batch (11 plates, `references/studio/plates_v1/`, masters untouched) replaced the stand-ins. `tools/art/prepare_plates.py` removes contact-sheet artefacts (duplicated strips, baked filename labels, black edges) and restores 4:3 (width crop for Camera 1; wide shots extended upward into the dark lighting grid). `tools/art/author_plates.py` writes `config/studio_plates.json`: Graham's mark measured from the with/without pair (the pair is offset ~14 px, so it was registered first) and carried to the wide plates by table scale; feathered table foreground masks; 8 podium screen quads + lamp strips (wide, row), 5 (presenter_wide), 1 (close-up); rig-light flicker points. New cameras `cam_audience` / `cam_audience_meh` (plates only): Hole reveals sometimes cut to the audience clapping or unimpressed before returning to Graham. Stand-in generator now writes to `config/studio_plates_standin.json` / `assets/studio/plates_standin/` so it can never overwrite the real map. Known limits (from the batch notes): Graham in the generated with-Graham plate is not our Graham (used only for alignment); small set-detail drift between plates; the generated plates' terms must be checked before release.

### 2026-10-03 — D027 Programme length and game selection (implementation; CP3–CP5)
**Type:** implementation choice within docs/03 (no locked decision changed).
**Decision:** with six games implemented, the Director schedules **5 games per standard episode** (`show.games_per_episode`), the last as the finale (×1.5 scoring). Selection is weighted rather than fixed: role tag (+1.5), random spread (0–1.4), a heavy penalty for two *writing* games back to back (tonal/mechanical variety), and a mild penalty for games the last broadcasts used (`installation.recent_games`). A game is only eligible when it has enough content at the installation's familiarity tier. Measured with bots: 25–28 simulated minutes for 2–8 players; real players are slower, and CP8 adds adverts, the midpoint break and interstitials toward the 45-minute target.
**Dev/test:** `force.game` forces only the first game; `force.playlist` (CLI `--force-games a,b,c`, used by integration tests) forces the order.

### 2026-10-03 — D028 Real or Mildew? confidence wager + Viewer Information Service v1 (CP3)
**Decision:** a confidence round is offered at most once per game (familiarity ≥2, 60%). Phone flow: pick → I'M CERTAIN / NORMAL / CHANGE MY ANSWER. Certain + right = ×2; certain + wrong = 0 (no negative scores, consistent with docs/05) plus Graham's "Certain, were you?". The server ignores a forged certainty flag outside confidence rounds. Every factual reveal is recorded locally (`installation.facts_seen`) and listed with its sources in the Viewer Information Service; incidents are never listed.
**Content state:** all 34 Real or Mildew? items are `draft` until a human checks each source; release validation blocks them.

### 2026-10-03 — D029 Guess the Genitals sourcing (CP3)
**Decision:** images only from Wikimedia Commons under PD/CC0/CC BY/CC BY-SA, chosen from open-access journal figures, museum specimens and public-domain natural-history plates (clinical, never sexualised). Animal-only is enforced by the validator (taxon required, *Homo* rejected, forbidden tags `human`/`people`/`sexual_activity`/`explicit`). "Genital or Something Else?" decoys (stinkhorn fungus, geoduck) are capped at two per game and never first. **Only 10 items exist (target 15–20)**: Commons has few usable clinical images; more need sourcing or user-supplied licensed imagery.

### 2026-10-03 — D030 Write-then-vote engine for Mildew Survey and Mouthfeel (CP4)
**Decision:** one server-authoritative segment (`seg_write_vote.gd`) runs Survey popularity / ARCHIVE / WHO SAID THAT? rounds and Mouthfeel describe / Make It Worse rounds. Answer boards are anonymous until the reveal; small groups are padded with authored archive answers (and old local winning answers, never attributed) so two players always vote on 3+ answers. Self-votes are refused server-side and disabled on the phone. Match bonus uses local normalisation only (case, punctuation, articles, simple plurals). Graham enters one anonymous answer in Mouthfeel and can win ("Naturally."). Rare answer tampering (rename to GRAHAM MILDEW / discard) at 2% when 3+ answers, dev-forceable. Mouthfeel's reverse format reuses the multiple-choice engine. WHO SAID THAT? needs 3+ players. Text drafts persist in the phone's local storage per question.
**Deferred:** Survey "None of these"; Mouthfeel optional imagery and Horrible Choice bonus.

### 2026-10-03 — D031 Private phone interference (CP4)
**Decision:** `PrivateInterference` (Director) fires only at phone-facing moments (question/write/vote open, a Hole look, segment boundaries). Payloads are data (`content/interference/`) with an internal source never shown to players. Delivery is a single server→phone message that is not part of any screen state, not stored, not resent on reconnect, never on the TV event stream and never touching scores/timers. Phone styles: a brief hard-cut text band that never intercepts touches; temporary text in the answer field (the draft is restored); a wrong unit label; vibration only (including a ring-like pattern — the OS call UI is never imitated; the validator rejects call-UI wording). Frequency (tested): ≈2.5 deliveries per 45 simulated minutes in STANDARD, ~25% of sessions near-silent, hard cap 6 per show, global cooldown 150 s, horror-saturation guard. SUPERVISED: tier-1 production/archive notes only, at a third of the rate. CLEAN: none, even when dev-forced. Distributed fragments (tier 3) send different words to different phones and leave someone out.

### 2026-10-03 — D032 Police Sketch chains (CP5)
**Decision:** every player starts a case; all cases advance together by rotation (player *i* works on case *(i − step) mod n*), so nobody touches the same case twice. Chain length 2 (draw → interpret) for 2–3 players, with two rounds so roles swap with new prompts (the explicit 2-player flow); 4 (draw → describe → draw → describe) for 4+. Missing work never deadlocks: an absent description falls back to the last statement; an absent drawing tells the next player to make something up. Scoring: describers earn up to 400 by content-word overlap with the original prompt; the original artist gets +500 when the chain reconstructs ≥50% of it; FUNNIEST MUTATION votes pay every contributor 200 each; BEST DRAWING votes (first drawing of each case) pay the artist 400; Graham's Choice +250. Drawings are normalised stroke lists (≤300 strokes, ≤6000 points, 0..1000) sent only to the phone that needs them and the TV; drawing frames may be up to 48 KB, every other frame stays at 4 KB. The most-voted drawing joins a local exhibit archive that the programme occasionally shows before a later game ("EXHIBIT · PREVIOUS INTERVIEW").

### 2026-10-03 — D033 Do Not Press That engine (CP6)
**Decision:** 10 data templates (`content/games/do_not_press_that/`), one generic engine (`dnp_puzzle.gd`) that randomises values per play. A puzzle has k = clamp(players, 3, 6) controls (switches, dials 1–9 or press-count buttons) whose correct values come from instructions held by *other* players, referring to the TV display (lit lamps, a pressure gauge or a canteen stock card) or to another control ("one more than VALVE B"), plus an optional ORDER rule, a NEVER control and an irrelevant DO-NOT-PRESS decoy. Dealing: controls round-robin; each instruction goes to the least-loaded player who doesn't operate that control. `DnpPuzzle.validate()` checks every player has a job, nobody holds their own control's instruction, targets are in range, the puzzle isn't pre-solved and following the instructions solves it without a mistake; the content validator and `test_dnp` run it for every template × 2–8 players (2,800 layouts) — 0 failures.
**Rules:** phones send absolute values (switch/dial) or press counts (buttons), so duplicates/latency can't double-apply. Mistakes (decoy, NEVER, ORDER, over-pressing) jam that control 5 s, cost 5 s, lower the tier, and Graham names the culprit (very rarely the wrong person, only someone he already targets). Tiers: PERFECT (0 mistakes) 1200, COMPLETED (≤2 and >15% time left) 900, BARELY 500, FAILED SPECTACULARLY 0 — shared by the team; +100 for each player with no mistakes. Punishment hook: the last puzzle's culprit is handed the next decoy. Timer irregularity (4% in STANDARD at familiarity ≥2, dev-forceable): the TV clock runs 12 s early and sits on 00 while play continues; phones always show the real time. Reconnect: the phone gets its live panel back with current values. Bots use a dev-only oracle to play.

### 2026-10-03 — D034 The Basement (CP7)
**Decision:** 7 authored cases (`content/games/basement/`; tones mundane, gross, criminally weird, apparently supernatural, ridiculous, disturbing — hidden from players; 2 partially unresolved). Each case: setup, 9–10 evidence cards typed key / support / red_herring / unreliable (players are never told which; "sensitive" cards are marked privately as ONLY YOU KNOW THIS), 3 optional investigations, 2–3 multiple-choice questions with per-option partial credit, reveal text and a case-specific Graham line. Dealing (`basement_case.gd`): every key clue is dealt and spread across as many players as possible, then support/unreliable cards, at most one red herring per hand; 2-player hands hold several clues each. `validate()` checks every player has evidence, every key clue is dealt, every question's best answer is supported by a dealt key clue, ≤1 red herring per hand; the content validator and `test_basement` run it for every case × 2–8 players.
**Flow:** setup → discussion (120 s + 10 s per player; ends early when everyone presses READY) with a team investigation budget of max(2, ⌈players/2⌉), one per player, findings private to the investigator → each player files their own theory (no forced consensus) → TV shows how the group split per question (AGREED/SPLIT), the best-supported answers and WHAT HAPPENED (UNRESOLVED stamp where applicable). Scoring: 600 × credit per question; +100 per unused investigation for players with ≥⅔ credit. Sharing evidence is never enforced.
**Deferred:** Graham commenting on obvious silence; incident hooks inside cases; investigations that unlock further investigations.

### 2026-10-03 — D035 Programme furniture: adverts, commercial break, viewer polls, awards, run-over (CP8 part 1)
**Decision:** a standard programme is now opening → intros → game 1 → scores → advert → game 2 → scores → viewer poll or advert → game 3 → scores → **COMMERCIAL BREAK** → game 4 → scores → poll/advert → finale (×1.5) → MILDEW AWARDS → final scores → sign-off.
- **Adverts:** 11 fake late-90s adverts across 9 fictional brands (`content/adverts/`), drawn procedurally by `AdvertPlayer` (gradient backdrops, sunbursts/stripes/checks, procedural packshots, bouncing headlines, small print). Voice-over is subtitled and spoken by the device voice — never Graham. No real brands. A couple carry quiet Mildew-world small print ("CALLS MAY BE RETURNED").
- **Commercial break** (midpoint, ~90 s): END OF PART ONE bumper → two adverts → interval card with countdown → PART TWO. Phones show STRETCH. WEE. SNACK. with a READY button; once everyone is back the interval is skipped (adverts are never cut mid-scene). The real TRANSMISSION PAUSED system is untouched and always available.
- **Viewer polls:** 15 silly polls, no points; the TV shows the split and Graham judges it.
- **Awards:** up to three of MOST ROT / GRAHAM'S FAVOURITE / FASTEST FINGER / GRAHAM'S DISAPPOINTMENT, then the winner's dreadful star prize.
- **Run-over:** target 45 min + up to 4 min overrun. Before each segment the Director estimates the remainder; if late, *future* games lose rounds (never the game in progress, never below two rounds, the final round kept). Logged as `Overrun`.
- **Announcer:** new break/advert continuity lines with stage gates (0 functional → 3 "Please end the transmission."); stage progression machinery is CP8 part 2.

### 2026-10-03 — D036 The world behind the programme: rooms, chains, Tier 2–4, Announcer drift, specials (CP8 part 2)
**Decision:**
- **Recurring rooms** (5 PoC: Green Room, Studio C, service corridor, prop store, tape room; data in `content/world/rooms.json` with adjacency). Shown as **procedural CCTV cutaways** (`CctvView`: monochrome security footage, camera number, REC, timestamp) built from each room's props and persistent state (door open/closed/ajar, chair position, light on/off/flicker, a figure). Photographic plates can replace any room later without changing the logic. States persist per installation and change **non-linearly** (they drift, and sometimes quietly go back to normal).
- **Event chains** (`content/world/chains.json`): at most one step per broadcast, at a pre-chosen boundary between games. Tier 2/3 chains roll; the **Tier 4** chain needs prerequisites beyond chance (rooms seen, familiarity ≥4, Announcer stage ≥2, returning players, installation-seed bucket) and is dev-forceable (`force.chain_step`, phone dev panel). A step may carry a private phone message or a line. Nothing is catalogued or explained.
- **Tier 2** incidents: CCTV cutaway, room callback, distant banging (Graham glances off and carries on), the Announcer saying something odd (Graham: "Will we?"). **Tier 3**: Graham snaps at something off camera ("I said stop." … "Anyway!") and the silent stare (≈8 s of nothing). Never between rounds of a game, never over a game graphic, at most 2 × Tier 2 and 1 × Tier 3 per show, horror-saturation guard; 60% of the time a cheerful reset line follows. SUPERVISED: Tier 2 at 20%, no Tier 3. CLEAN: none. Measured (300-programme soak): Tier 3 ≈ 0.05 per programme.
- **Announcer drift:** every third broadcast, 60% chance to advance one stage (cap 3); stage gates which continuity lines are eligible. Never in CLEAN.
- **{NAME}'S EASY QUESTION** (punishment): between games, at most once a show, for the contestant Graham is most fed up with (irritant + disappointment + target + wrong streak ≥ 0.5, then 25%); only their phone answers; +100 and confetti, or "Extraordinary."
- **THE TEST** (hidden Interruption Game): after the commercial break, seasoned installations only (familiarity ≥3, STANDARD, ≥5 broadcasts since the last one, 12%). Colour bars (generic, no real broadcaster's card), phones get three unexplained questions each (different per phone), unscored, kept locally, never shown back; Graham: "Sorry about that. Technical fault."
- New synthesized audio: advert jingle, break bumper, distant banging, room tone, distant door (provisional).
**Imagery request:** photographic plates for the rooms would improve the cutaways; see NEXT_BUILD.

### 2026-10-03 — D037 Backstage room plates (user-supplied batch)
**Type:** user-supplied assets, integrated per D026/D036.
**Decision:** the user's ChatGPT batch (22 images, 10 rooms: Green Room ×4, Studio C ×3, prop store ×4, tape room ×3, corridor ×3, control room, kitchenette, loading bay, dressing room, the locked room "B4"; masters in `references/rooms/plates_v1`, untouched) replaces the procedural CCTV drawing. `tools/art/prepare_room_plates.py` crops each to its clean band (the batch has a duplicated top strip and a mirrored bottom strip), restores 4:3 by extending into darkness or trimming width, and grades it as cheap security video (monochrome, faint green, crushed blacks, softness, vignette, grain) → `assets/studio/rooms/*.jpg`. `CctvView` picks the plate from the room's persistent state (door open/ajar, chair by the door, light off, mannequin turned round or gone, podium 4 lit); a dim, soft figure overlay is used where no plate shows it; live scanlines/noise/REC/timestamp stay on top. Rooms without a variant fall back to the base plate (darkened for light off). Ten rooms now exist; deeper rooms unlock with familiarity (control room/loading ≥2, dressing room ≥3, B4 ≥4). The procedural drawing remains the fallback if a plate is missing.
**Known limits:** one master (dressing room) is a truncated PNG — the usable top part is kept; generated-image terms to check before commercial release.
