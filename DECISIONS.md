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
