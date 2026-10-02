# 03 — Director System Specification

## Purpose

The Director makes Mildew feel like a live television programme with a personality rather than a shuffled list of games. It is authoritative, stateful, data-driven, debuggable and deliberately resistant to simple player pattern recognition.

The Director must be capable of making a *good normal episode* before it is capable of making a strange one.

## High-level responsibilities

The Director controls or influences:

- episode skeleton;
- next-game choice;
- game round variants;
- finale selection;
- advertisement/interstitial placement;
- commercial break timing;
- runtime adjustments;
- tonal pacing;
- Graham emotional state;
- Graham relationship tags;
- audience reaction;
- punishment segments;
- player callbacks;
- private interference targeting;
- incident eligibility and cooldowns;
- room state progression;
- Familiarity progression;
- persistent rare chains;
- Rot awards;
- selected fake/phantom contestant behaviour;
- session-specific quirks/false correlations.

## Episode planning model

At `BEGIN TRANSMISSION`, build a **partial episode skeleton**, not a fully fixed playlist.

Example internal slots:

- Opening game — resolved now.
- Game slot 2 — candidate pool.
- Interstitial/ad slot.
- Game slot 3 — unresolved.
- Midpoint commercial break — fixed approximate location.
- Game slot 4 — unresolved.
- Punishment/Interruption window — optional.
- Finale — candidate pool, allowed to change.
- Awards/prize/credits.

This provides pacing control without preventing Graham from reacting to players.

## Game tags

Each game/variant must expose tags used by the Director. Example tag vocabulary:

- trivia;
- visual;
- social;
- writing;
- drawing;
- cooperation;
- deduction;
- discussion;
- gross;
- high-energy;
- low-energy;
- chaotic;
- tense;
- unsettling-capable;
- good-opener;
- good-middle;
- good-finale;
- good-reset;
- long;
- short;
- 2-player-safe;
- high-content-dependency.

Normal selection should avoid repetitive mechanical clusters. Deliberate violations are allowed for punishment/comedy.

## Director tonal/mood model

Track recent-session tone, not just a single scalar. Suggested channels:

- Comedy
- Competitive
- Gross
- Tense
- Quiet
- Chaotic
- Unsettling

Maintain rolling recent-density values. Selection logic should consider what the episode **needs next**, not simply what has the highest random weight.

### Horror saturation safeguard

If recent sinister density is too high:

- block/strongly suppress Tier 2+ incidents temporarily;
- reduce private pleas/warnings;
- favour a comedy reset, straightforward game, silly advert or normal presenter segment;
- do not immediately escalate because `degradation` is high.

### Comedy saturation safeguard

If the show has been completely normal for too long, allow a low-cost Mildew reminder such as:

- wrong lower-third;
- mistimed applause;
- odd production note;
- brief corridor cut;
- player name glitch;
- Graham stare;
- mundane but incorrect cue.

Do not automatically jump to screams/major incidents.

## Core state axes

### Broadcast Degradation

Represents instability/incorrectness of the programme.

Properties:

- hidden;
- rises broadly with session length/round completion but includes randomness;
- does not map linearly to scare level;
- can unlock more event eligibility;
- never just applies a darker visual skin;
- should not make the broadcast unreadable.

Conceptual bands:

- low: bad chroma key, tracking, mistimed applause;
- medium: wrong lower thirds, crew noise, damp changes, odd camera cuts;
- higher: impossible dates, odd callbacks, room anomalies, announcer conflict;
- extreme eligibility: rare major/legendary incidents.

Do not expose these bands to players.

### Complicity

Represents how much the programme treats the group as willing participants.

Potential contributing behaviours:

- choosing to continue;
- accepting suspicious prompts;
- repeatedly selecting more extreme content;
- pressing suspicious controls;
- choosing vile options;
- long session duration;
- participating enthusiastically in punitive material.

Complicity is not a visible morality score and must not be easily farmable or reduced intentionally.

Possible language shifts:

Low:

> “Shall we continue?”

Higher:

> “We knew you'd continue.”

Very high:

> “No need to ask anymore.”

It changes presentation/eligibility, not real consent or the ability to quit.

### Interference

Represents what kinds of irregularity are allowed/eligible in the current settings/session.

Player-facing default `STANDARD TRANSMISSION` allows the entire repertoire. Frequency remains separately controlled.

Interference targets:

- TV video;
- TV audio;
- one phone;
- multiple phones;
- all phones;
- Graham;
- audience;
- Announcer;
- scoreboard/lower third;
- recurring room;
- game content injection.

### Pressure

Represents current production tension.

Can rise from:

- technical incidents;
- backstage conflict;
- Announcer/Graham conflict;
- Graham sensitivities;
- repeated player antagonism;
- long/overrunning broadcast;
- selected persistent chains.

Can fall after:

- ad break;
- normal segment;
- comedic reset;
- successful puzzle;
- time.

Pressure should affect human behaviour more than generic “spooky effects.”

### Familiarity

Two layers:

1. **Installation/category Familiarity** — what content tiers/variants the household installation has seen enough to handle.
2. **Player Familiarity** — names, selected question outcomes, recurring jokes and Graham callbacks.

Do not require every player to have identical history. Game content eligibility should use installation/category familiarity for stability; player familiarity is primarily presentation/personalisation.

## Graham relationship model

Each player may hold several weighted traits simultaneously:

- favourite;
- irritant;
- disappointment;
- target;
- pet_project;
- interesting;
- pity/protective;
- grudge.

Inputs include:

- answer accuracy;
- streaks;
- repeated failure;
- mocking Graham in written answers;
- beating Graham's favourite;
- winning too much;
- high Rot;
- recurring weird choices;
- triggers/sensitivities;
- audience reaction;
- prior persistent trace.

Do not let one target be relentlessly abused. Punishments require cooldowns. Most sessions spread humiliation around, while occasional sessions are allowed to develop a stronger Graham-vs-player thread.

## Graham sensitivities

A session or installation may have hidden sensitivity hooks. Examples:

- `Studio C`;
- a particular name;
- an advertiser;
- the programme running late;
- Announcer interruption;
- a repeated sound;
- backstage-camera intrusion.

A sensitivity should not always produce the same outcome. Players may deliberately antagonise Graham once they identify one; the system should anticipate this but not provide a predictable reward loop.

Example:

Survey answers include `Studio C`.

Graham reads the preceding answers, reaches `Studio C`, stops smiling, then says:

> “Moving on.”

No lore explanation.

## Punishment eligibility

Track a hidden punishment score/context based on in-game behaviour such as:

- repeated easy failures;
- provoking Graham;
- high-confidence wrong answers;
- ignoring instructions;
- repeatedly pushing suspicious controls;
- unusual dominance;
- explicit in-game insults;
- sensitivity triggers.

Punishment segment selection must consider:

- recent punishments;
- target cooldown;
- episode runtime;
- current tone;
- whether the target is present/active;
- mechanical fairness.

Punishments may offer strong points sometimes. Never make `punished = mechanically always bad`.

## Interruption Games

Hidden short formats that do not appear in the core game menu.

Characteristics:

- Director-inserted;
- no normal unlock screen;
- can be comedic, strange or unsettling;
- typically 30 seconds–3 minutes;
- most do not become permanently selectable;
- can act as punishment, incident delivery or broadcast anomaly.

Example working title: `THE TEST`.

Do not overuse. First serious PoC should contain 1–2.

## Private interference engine

Each interference payload has an internal source, even when the player cannot know it:

- production;
- announcer;
- Graham;
- unknown;
- unknown_impersonating_source;
- corruption/system;
- archive.

Possible behaviours:

- brief text replacement;
- overlay message;
- temporary incorrect player name;
- countdown discrepancy;
- wrong game title;
- backstage still;
- unexplained controller vibration;
- button appears briefly;
- text field temporarily displays a message then restores input;
- drawing canvas receives/appears to receive one foreign mark;
- message changes on touch (`YOU NEED TO HELP ME` -> `TOO LATE`), extremely rare.

Messages can be:

- true;
- false;
- irrelevant;
- contradictory;
- predictive;
- falsely predictive;
- mundane production data;
- direct plea;
- nonsense.

Do not build them into a secret strategy system.

## Distributed incidents

Rare high-tier incidents may target multiple players with complementary or conflicting fragments.

Example:

- Player A: `GREEN ROOM`
- Player B: `DON'T LET HIM`
- Player C: `OPEN IT`
- Player D: nothing

Later TV briefly shows Green Room. The game does not say the fragments were a puzzle.

These must be uncommon enough to feel remarkable.

## Incident tiers

### Tier 0 — normal production mess

Common/low-cost:

- cue mistakes;
- mic pop;
- bad applause;
- lower-third typo;
- Graham looking at wrong camera.

### Tier 1 — odd

Common-ish:

- empty corridor;
- wrong name;
- strange production message;
- incorrect audience reaction;
- unexpected camera floor shot.

### Tier 2 — unsettling

Uncommon:

- private plea;
- unexplained banging;
- figure in recurring room;
- Announcer behaving oddly;
- meaningful room-state callback.

### Tier 3 — major

Rare:

- scream/production shutdown;
- Graham genuinely loses temper;
- distributed incident;
- phantom contestant involvement;
- impossible footage;
- prolonged silent stare.

### Tier 4 — legendary

Extremely rare, conditional, often persistent/multi-session eligible. No achievement. No incident log. Some Tier 4 chains may be installation-specific.

Tier 4 should require conditions in addition to random chance. Potential prerequisites:

- certain room previously seen;
- returning players;
- familiarity threshold;
- specific advert encountered;
- relevant game currently active;
- persistent Announcer stage;
- compatible installation seed.

A small subset may be installation-seed specific so different households genuinely have different folklore.

## Installation-specific world seed

Generate a hidden installation seed. It may affect:

- rare incident eligibility;
- subtle recurring quirks;
- a small subset of room/event possibilities;
- session quirk pools.

Do not expose seed to players. Reset Mildew creates a fresh seed unless save data is restored.

## Session-specific false correlations

At session start, optionally assign one or more hidden quirks that create temporary correlations, e.g. repeated red answers mildly increase Camera 4 incident weighting. Next session, that relationship may not exist.

This helps real players form contradictory folk theories.

## Game selection constraints

Normal behaviour:

- mechanical variety;
- avoid back-to-back long games;
- avoid too many image/trivia games in sequence;
- respect opener/middle/finale suitability;
- use good-reset tags after tense material;
- consider player count;
- consider remaining runtime;
- avoid immediate repeated core game.

Deliberate exceptions:

- punishment marathon;
- Graham stubbornness;
- “again” segments;
- weird broadcast schedule;
- very rare deliberate repeated question.

## Finale selection

Finale usually worth ~1.5× normal score.

Director may consider standings and choose a format capable of creating drama, but must not transparently rig the outcome. Rarely, irritated Graham may pick a game a disliked player historically performs poorly at. Rules/scoring remain legitimate unless a clearly authored rare Graham-cheating bit is active.

## Runtime control

Each game exposes expected/min/max duration. If episode runs late:

- reduce future round count;
- choose shorter variant;
- skip optional interstitial;
- never abruptly cut an active meaningful round.

Occasionally allow intentional 2–5 minute overrun, especially for an Announcer-vs-Graham beat.

## Director logging (development only)

Every selection decision should be explainable in logs, e.g.:

`Selected HOLE: visual/high-energy reset required; previous game social/long; sinister_density=0.72 triggered comedy reset weighting +40%; player_count=4; no recent Hole occurrence.`

The point is not to expose this to players. It is to make procedural behaviour debuggable.
