# CLAUDE.md — Mildew Master Build Brief

Repository: `Mildew`

## 0. Your role

You are the lead implementation agent for **Mildew**. Treat the documents in this repository as a production specification, not as loose brainstorming. Build the game in checkpoints, keep it playable after every checkpoint, maintain detailed status documentation, and do not silently alter locked design decisions.

Before coding:

1. Read this file completely.
2. Read `docs/01_NON_NEGOTIABLES.md`.
3. Read `docs/11_BUILD_CHECKPOINTS.md`.
4. Read the subsystem documents relevant to the checkpoint you are about to implement.
5. Inspect the existing repository before changing anything.
6. Create/update `PROGRESS.md`, `NEXT_BUILD.md`, `DECISIONS.md`, and test/status reports using the templates in `templates/`.

If implementation reality suggests changing a locked decision, **do not silently make the change**. Record the original requirement, the concrete problem, the proposed alternative, the expected impact, and bring that proposed design change to the user first. Implementation details that do not change the product experience may be chosen autonomously and documented.

Do not repeatedly ask the user questions already answered by this package. If a non-creative implementation detail is unspecified, choose the simplest robust option consistent with the design and document it as an implementation assumption. Ask only when a decision would materially change locked product behaviour, visual identity, platform requirements, content boundaries, or the user experience.

---

# 1. Product definition

**Mildew** is an adult local-multiplayer party game for **2–8 players**. One **Android TV** device runs the main broadcast. Players join using ordinary phone browsers on the **same local Wi-Fi network**. Core multiplayer gameplay must work **fully locally/offline** once the game is installed; no account or cloud service is required.

Primary host target: Android TV / Google TV class devices, designed around mid-range hardware.

Secondary/fallback host target: the user also has **Xbox Series X Developer Mode**. Do not make Xbox a dependency of the first build, but keep the Director, content, protocol, save logic and phone-controller architecture platform-agnostic so the broadcast host can later be ported to a stronger platform without rewriting the game.

Engine: **Godot 4.x**, with the exact project version pinned in the repository once the first successful Android TV toolchain/build is established. Do not casually upgrade engine version afterward.

Reference TV composition: **1920×1080, 16:9 output**, with the fictional live broadcast normally presented as an authentic **4:3 late-1990s television programme** inside it. System/lobby screens may use the full frame where appropriate. Maintain legibility at 720p and scale cleanly to 4K.

Phone controller orientation: **portrait-first**.

Target performance: **60 FPS for normal UI/broadcast presentation** on mid-range Android TV hardware; 30 FPS is acceptable for occasional heavy transition/video effects if necessary. Network responsiveness and input reliability take priority over decorative frame rate.

---

# 2. Core creative identity

The central experience is:

> A disgusting, inappropriate, funny, forgotten British game show from the late 1990s that somehow still broadcasts, and occasionally lets the players see pieces of something they were never meant to see.

The intended audience reaction is frequently:

> “What the fuck is going on?”

Mildew must remain a **good party game first**. Every launch minigame must be fun if all sinister events are disabled. Horror/unease is seasoning and structural atmosphere, not the main mechanic.

The programme itself behaves as if everything is normal. It does not say “you are in a haunted game.” It does not explain the weirdness. Graham normally continues presenting.

The key emotional rhythm is:

1. Funny / competitive / gross party gameplay.
2. Something slightly or deeply wrong happens.
3. Nobody explains it.
4. The programme immediately returns to something stupid, cheerful, gross or competitive.
5. The players are left discussing what they think they saw while the show continues.

Never let procedural horror density overwhelm the comedy. Never let pure comedy remain so uninterrupted that the broadcast identity disappears. The Director must create a deliberate **good mix**.

---

# 3. The fictional programme

Working fiction:

- `MILDEW`
- Produced by a fictional late-1990s company such as **Sallow Entertainment Ltd.**
- Appears to originate from roughly **1997–1999**, though dates and archive material sometimes conflict.
- The software presents itself more like a recovered interactive/home edition or continuing transmission than a modern party-game app.
- The true explanation for the irregularities is intentionally **undefined**.

Possible interpretations can all be supported by evidence, but none may become canonically confirmed:

- the original production was abusive, negligent and chaotic;
- the archive is combining incompatible footage/data;
- Graham knows more than he admits;
- the programme itself behaves like an entity;
- the Announcer is trying to control/stop something;
- an unidentified third factor is present.

Do **not** create a named “Mildew monster,” demon, villain reveal, clean ARG solution, lore codex explaining the truth, or final canonical answer unless the user explicitly changes this rule later.

---

# 4. Graham Mildew

Working presenter name: **Graham Mildew**.

He is a convincingly human late-1990s British TV presenter, not a monster, mascot or caricature. Approximate visual profile:

- late 40s to mid-50s;
- dated but plausible haircut;
- one iconic cheap-but-presentable suit/tie look;
- heavy studio makeup;
- strong studio lighting and visible perspiration;
- unnaturally practiced game-show smile;
- looks like someone who genuinely could have hosted low-budget regional television in 1998.

Presentation architecture: **hybrid FMV-style presenter**. Build reusable high-quality visual states/loops rather than requiring unique full-motion video for every line:

- idle;
- speaking;
- smile;
- amused;
- disappointed;
- irritated;
- angry;
- rattled;
- stare into camera;
- looking off camera;
- waiting/reconnect;
- laughing;
- reading cards/score;
- neutral transition.

His emotional state is **visible to players**, unlike most other Director variables. It should be expressed through performance, pose, face, delivery and small physical changes, not a UI meter.

Pressure may make him look more humanly stressed: loosened tie, increased sweat, hair/makeup slightly disturbed. Never mutate him into supernatural visual horror.

## Graham's default personality

- professional;
- upbeat;
- petty;
- experienced;
- comfortable discussing disgusting material with complete seriousness;
- rarely surprised;
- treats animal genital identification as respectable television;
- mostly uses ordinary presenter language rather than constant jokes.

The humour is often the mismatch between content and his professionalism.

Example tone:

> “That's right. You were looking at the reproductive organ of the Argentine lake duck.”
>
> “And what a specimen it was.”

## Graham's relationship with players

Graham may develop hidden, overlapping session-level attitudes:

- Favourite;
- Irritant;
- Disappointment;
- Pet project;
- Target;
- Interesting.

He may:

- praise favourites;
- openly hope someone wins;
- become curt with disliked players;
- hold session grudges;
- very occasionally retain a grudge/favourite trace across sessions;
- mock repeat mistakes;
- misunderstand a player and decide they “love” a category they do not actually like;
- rarely persist that false belief into a future session;
- defend a contestant from the audience;
- sometimes protect the player in last place;
- sometimes resent a dominant winner;
- disagree with official scoring without changing it;
- rarely misrepresent or alter an answer to punish/humiliate;
- occasionally put words in a player's mouth (“Aaron says he'd like another round”);
- rarely remove someone from one short segment, placing them in spectator mode;
- give them a ridiculous mini-challenge to re-enter;
- punish everyone because of one contestant;
- form a temporary clear “Graham vs Steve” dynamic, but not every session.

Humiliation is theatrical and game-show-like, never a real-world personal attack. It should target **in-game behaviour**, answers, performance, avatars, recurring jokes, gross knowledge, etc.

Example punitive segment:

> **AARON'S EASY QUESTION**
>
> Which of these is a cow?

If he fails:

> Graham removes his glasses.
>
> “Extraordinary.”

If he succeeds:

> absurd applause/confetti.
>
> “HE'S DONE IT!”

## Graham's anger

Anger is rare enough to matter. Most screams, glitches and mistakes do not break his presenter persona. Occasionally something does.

Example:

> distant noise
>
> Graham stops smiling and looks off-camera.
>
> “I said stop.”
>
> He notices the camera, smiles again.
>
> “Anyway!”

Do not make angry Graham routine.

---

# 5. The Announcer

A distinct off-screen continuity-announcer voice exists.

Initial presentation:

- calm;
- formal;
- reassuring;
- classic British TV continuity tone;
- initially sounds prerecorded/functional.

Long-term progression may persist slowly across sessions:

1. purely functional;
2. unusually specific comments;
3. disagreement with Graham;
4. attempts to end/control transmission;
5. rare private phone communication.

Examples:

> ANNOUNCER: “We'll be right back.”
>
> GRAHAM: “Will we?”

or later:

> ANNOUNCER: “Please end the transmission.”
>
> Graham ignores them.

Graham may suppress the Announcer. Do not make it clear that the Announcer is “good,” reliable, or the source of all private messages. Unknown sources can impersonate the Announcer.

---

# 6. Launch game roster — 6 core + 2 ambitious

All eight games are available from the start. Events/variants may progressively become eligible, but core games are not grind-unlocked.

1. **Guess the Genitals** — animal-only genital/anatomy identification; real facts; clinically presented.
2. **Hole** — progressive visual deduction with early-lock risk/reward.
3. **Mildew Survey** — player-written social answers, voting, archive responses.
4. **Real or Mildew?** — plausible fake vs real bizarre facts/images.
5. **Police Sketch** — crude touch drawing and interpretation chains.
6. **Do Not Press That** — real asymmetric cooperative coordination puzzles.
7. **The Basement** — authored cooperative mystery/deduction scenario system.
8. **Mouthfeel** — gross text/imagery creative-writing and voting game.

All must have legitimate 2-player support; some are better with 4+, but “supports 2” may not mean “just let two clients connect to a design that requires four.” Use the explicit adaptations in `docs/04_GAME_SPECS.md`.

---

# 7. Standard broadcast

Default standard episode target: **about 45 minutes**, usually around **5 of the 8 games**, not all eight, plus adverts, interstitials, possible punishment/interruption material, a midpoint commercial/bathroom break, awards and credits.

Mildew chooses the programme order. Players generally **do not know which game comes next**. The programme may occasionally show a schedule, but it is not guaranteed accurate.

A standard episode skeleton may be preplanned partly, not completely:

- opening;
- player introduction;
- accessible first game;
- advert/interstitial;
- second game;
- viewer poll/Graham fact/production beat;
- third game;
- midpoint commercial break (approx. 90 seconds, can resume early when all are ready);
- fourth game;
- possible punishment/interruption;
- final game worth roughly 1.5× normal points;
- awards/prize/credits.

The Director creates an initial skeleton, then can dynamically alter unresolved slots, insert punishment material, change the finale, extend/shorten future rounds, or run over by roughly **2–5 minutes**.

Players may manually pause for bathroom/snack needs. Pausing remains a real reliable system function, themed as `TRANSMISSION PAUSED`. Never obstruct pausing/exiting for fiction.

---

# 8. The Director

The Director is authoritative over:

- programme pacing;
- game selection;
- finale selection;
- game/round variants;
- scoring interpretation;
- Rot;
- Graham mood and relationships;
- audience reaction;
- adverts/interstitials;
- punishment eligibility;
- session callbacks;
- private phone interference;
- recurring room/event state;
- incident cooldowns and prerequisites;
- content familiarity;
- tonal balance;
- session overrun.

Core hidden axes/systems:

- **Broadcast Degradation** — instability/incorrectness of the programme. Broadly increases over time but is not a predictable “round 5 = horror” ramp. The show never visually becomes a different horror aesthetic.
- **Complicity** — how willingly the group has participated in suspicious/gross choices. Not a morality score and not directly gameable. It changes how the programme speaks to them.
- **Interference** — eligibility/intensity repertoire for private/controller/broadcast irregularities. The default player-facing “Standard Transmission” means the full intended repertoire, but **maximum repertoire does not mean constant frequency**.
- **Pressure** — current tension within the production/Graham/crew. Can rise and fall during a session.
- **Familiarity** — installation/category experience plus player-specific callback memory; enables obscure/extreme content gradually without hiding core games.
- **Director Mood/Tone mix** — comedy, competitive, gross, tense, quiet, chaotic, unsettling.

The Director must explicitly avoid both:

- too many sinister events clustered together;
- overly long stretches in which nothing feels like Mildew.

After a particularly sinister beat, favour a comedic/normal reset. Tonal whiplash is intentional.

Read `docs/03_DIRECTOR_SYSTEM.md` before implementing this subsystem.

---

# 9. Interference and sinister philosophy

The default experience uses the **full interference repertoire**. The player-facing setting should not spoil individual tricks. Suggested labels:

- `STANDARD TRANSMISSION` — intended/default full experience;
- `SUPERVISED TRANSMISSION` — reduced irregularities;
- `CLEAN TRANSMISSION` — irregularities suppressed where possible.

The detailed description under settings may honestly explain that this controls unexpected fictional broadcast interruptions, unusual controller messages and unsettling audiovisual events, but do not list every trick.

Private controller interference is critical:

- appears briefly and disappears;
- is usually not recoverable in a message history;
- screenshots work normally if a player is fast enough;
- may target one player, several, or different players with different fragments;
- may be warnings, pleas, production messages, nonsense, lies or impersonations;
- may occasionally reference another player;
- may sometimes predict future content and sometimes be wrong;
- may use controller vibration, including a pattern reminiscent of a phone ringing, but never impersonate the actual Android/iOS call UI;
- never requires unrestricted microphone access.

Examples:

- `WHY ARE YOU WATCHING THIS`
- `YOU NEED TO HELP ME`
- `CAM 4 AFTER BREAK`
- `WHO MOVED THE HAM`
- `DON'T LET THEM PICK RED`
- `PLEASE`
- `SORRY WRONG NUMBER`

Private messages should be sparse/unpredictable enough that players can genuinely argue about whether they saw something. Some full sessions may contain very little. A “maximum” setting means all event types are eligible, not that the game spams them.

Major incidents remain rare. Actual screams are rare. A scream followed by an off-camera `SHUT UP` is very rare. There are minor and major incident classes.

The programme may occasionally simply stop interacting for a short period while Graham stares into camera. This is rare.

Do not catalogue or award achievements for creepy incidents. Players should not see a completion percentage.

---

# 10. Recurring rooms and production world

Use approximately 8–10 internally consistent backstage locations in the final vision, with 4–5 fully realised in the first serious proof of concept. Initial location set:

- Green Room;
- Studio C;
- service corridor;
- prop store;
- Graham's dressing room;
- archive/tape room;
- loading area;
- control room;
- staff kitchenette;
- unidentified locked room.

Internally map their rough geography so cutaways feel like a real studio complex rather than random horror images.

Room states persist selectively across sessions and can change **non-linearly** or revert. Examples: chair moves, door opens, light turns off, somebody appears, then later the room is completely normal again.

Recurring crew members should have consistent appearances. A few names emerge organically in dialogue (“Neil?”, “Where's Carol?”) rather than via lore screens.

---

# 11. Networking and controller philosophy

The Android TV host is the authoritative server and broadcast client. Phones are untrusted input/controller clients.

Logical layers:

1. **Broadcast Client** — Android TV visual/audio presentation.
2. **Controller Client** — local browser app served to phones.
3. **Mildew Server/Director** — authoritative state, content, scoring, persistence, session logic.

These may physically live in one Android TV package where sensible, but keep them architecturally separated.

Phone sends actions such as `player 3 selected answer B`; the server determines scoring/state. Never trust a phone to award its own points.

Join flow:

- `BEGIN TRANSMISSION`;
- Graham appears in studio while waiting;
- QR code contains local join URL/session token;
- fallback local URL + short room code;
- QR users do not need to re-enter room code;
- no account/app installation;
- returning local profiles + `NEW CONTESTANT`;
- minimum two contestants;
- late joiners may enter between games; during a game they wait safely until next entry point.

If a new contestant enters a name matching an **inactive existing profile**, Graham can call it out and ask the other players `IS THIS ACTUALLY STACY?` before offering association with the returning profile. Do not automatically identity-match. Exact duplicate active/display profile names are disallowed.

Disconnect/reconnect:

- pause broadcast for up to **30 seconds** for a disconnected active player;
- if they reconnect earlier, resume immediately;
- preserve current state and unsent text/drawing where practical;
- Graham fills the wait with variable dialogue/silence;
- if player does not return, Graham comments and the show continues if at least two active players remain;
- if everybody disappears and does not return, Graham is visibly annoyed and ends transmission;
- do not fake real disconnect states; fictional “broadcast connection” weirdness may exist separately but must never obscure genuine networking status.

Read `docs/06_NETWORKING_AND_PLATFORM_ARCHITECTURE.md`.

---

# 12. Content and sourcing

All games and incidents must be **data-driven**, with very large expandable content libraries as a core architecture goal.

Factual content (biology, medicine, history, etc.) requires source metadata before approval. Real factual imagery requires:

- source;
- licence;
- attribution requirements;
- approval status.

Never silently scrape random web images and bake them into release content. Use clearly marked placeholders until suitable licensed/owned material is approved.

Player-facing gameplay shows short factual explanations, not citations. Citations/sources are available through an in-universe **Mildew Viewer Information Service** / Fact Archive. The archive contains legitimate factual material only; it must **not** catalogue sinister incidents.

Content quality states:

- `placeholder`
- `draft`
- `reviewed`
- `approved`

Release validation should be able to block inappropriate placeholder factual content.

Familiarity tiers:

1. accessible;
2. strange;
3. obscure;
4. seasoned-player material;
5. “why the fuck does this game contain this?”

Normal repetition should be avoided, but deliberate repetition is allowed for comedy or sinister effect.

Read `docs/07_CONTENT_SYSTEM_AND_SCHEMAS.md`.

---

# 13. Voice/audio architecture

The user does not have voice actors. Build a **hybrid voice pipeline**:

- common authored Graham lines, intros, reactions, adverts, rules and incident dialogue should be capable of being pre-rendered into consistent high-quality audio assets during production;
- dynamic lines such as player names, scores and procedural callbacks require a consistent offline/local runtime TTS path;
- player profile creation includes a local pronunciation-validation step (`Is this pronunciation correct?`) and stores the chosen pronunciation form;
- architecture must allow a better synthetic/dedicated Graham voice to replace the initial implementation later without rewriting dialogue/game systems.

Do not require runtime internet for ordinary speech.

Exact voice provider/model is an implementation/content-production choice and may change. Track licensing/redistribution implications before shipping generated audio.

---

# 14. Proof-of-concept philosophy

The user does **not** want a bare technical prototype. The serious proof of concept should be **as close to the intended finished experience as reasonably possible**:

- authentic Mildew styling from checkpoint 1;
- real broadcast camera grammar;
- Graham exists early;
- minimal Director exists early;
- temporary assets should follow art direction rather than programmer-art rectangles wherever feasible;
- vertical-slice polish beats rushing all eight games into ugly placeholder form;
- every checkpoint still ends with a playable installable Android TV APK.

First serious PoC content targets:

- Guess the Genitals: 15–20 items;
- Hole: 20–30;
- Real or Mildew?: 30–40;
- Mildew Survey: 40–60 prompts;
- Police Sketch: 30–40 prompts;
- Do Not Press That: 8–12 strong puzzles;
- The Basement: 6–8 strong cases;
- Mouthfeel: 40–60 prompts/components;
- Fake adverts: 8–12 polished adverts across at least five brands/styles;
- Recurring rooms: 4–5 fully realised with state variants;
- Tier 0–2 incidents + a small number of Tier 3;
- private interference;
- a couple of persistent room/event chains;
- one developer-testable Tier 4 machinery chain;
- one or two hidden Interruption Games such as `THE TEST`.

---

# 15. Progress discipline

Every checkpoint must update detailed repo status. At minimum maintain:

- `PROGRESS.md`
- `NEXT_BUILD.md`
- `DECISIONS.md`
- `TEST_REPORT.md` or timestamped reports under a testing/status folder

Status tracking should be in-depth enough that another Claude Code session can resume without reconstructing context from chat.

For each implemented feature record:

- state: planned / in progress / blocked / implemented / verified;
- files/components;
- tests run;
- known limitations;
- next action;
- design requirement it satisfies;
- any provisional asset/content status.

Do not declare a checkpoint complete unless the checkpoint gate in `docs/11_BUILD_CHECKPOINTS.md` passes.

---

# 16. Hard product success test

The proof of concept succeeds if:

> The user can install Mildew on Android TV, two or more people can join from phone browsers over local Wi-Fi without internet, the group can complete a full Director-generated broadcast, the games are genuinely funny/competitive/gross, at least one moment makes somebody say “what the fuck was that?”, the programme remains readable/reliable, and the group wants to immediately play another episode.

That is the target. Do not optimise the soul out of it.
