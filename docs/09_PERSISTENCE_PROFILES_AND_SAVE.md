# 09 — Persistence, Profiles and Save State

## Goals

Persistence should make Mildew feel like a long-lived local broadcast installation without turning the game into a grind, account system, or lore checklist.

Persist only what improves future sessions.

## Three persistence scopes

### 1. Session memory

Rich, temporary, reset when the current broadcast ends.

May include:

- current score;
- current Rot;
- answer history;
- repeated categories/animals;
- fast-answer streaks;
- wrong-answer streaks;
- games won;
- survey matches;
- drawing votes;
- puzzle mistakes;
- Graham relationship weights;
- current labels/titles;
- punishment cooldowns;
- session quirks;
- current Director tonal history;
- Pressure/Complicity/Degradation;
- current incident cooldowns;
- current content IDs used.

### 2. Player profile memory

Small, selected and persistent.

Recommended fields:

- stable local profile ID;
- display name;
- speech/pronunciation form;
- avatar configuration;
- games played;
- wins;
- lifetime Rot;
- selected memorable outcomes;
- selected recurring jokes/labels;
- selected prizes;
- selected Graham grudge/favourite trace;
- selected awards;
- last-seen date/version where useful.

Do not store every answer forever.

### 3. Installation/broadcast memory

Persistent world state shared by the household installation.

Recommended fields:

- installation seed;
- schema version;
- total broadcasts played;
- category Familiarity;
- recent content history;
- recurring room states/history;
- advert exposure history;
- Announcer progression;
- rare incident flags;
- persistent incident chain state;
- phantom contestant/recurring archive eligibility;
- unlocked/eligible progressive variants;
- hidden installation-specific quirks.

## Returning player recognition

Returning profile selection should make recognition feel casual, not invasive.

Examples:

> “Aaron. Back again.”

> “Still no luck with dolphins, then.”

> “Welcome back. How was the ham?”

Use sparingly.

## Profile matching

No cloud account. No biometric/device fingerprint identity matching.

Players manually select a local profile or choose New Contestant.

Exact display-name duplicates are not allowed among relevant local profiles without disambiguation.

If a new person enters a name that matches an inactive profile, the optional Graham group-verification bit can run. Never automatically merge based only on name.

A player is allowed to create a new profile rather than reuse their history.

## Memorable outcome selection

Persist only selected outcomes, e.g.:

- chose horse five times;
- fastest correct animal-genital identification ever on this profile;
- memorable confident failure;
- rare award/title;
- one particularly successful/awful drawing;
- broke studio power three times;
- repeatedly refused suspicious prompts;
- favourite archived Survey response.

Implement a bounded memory system with limits/expiry/priority so profile files do not grow without control.

## Lifetime Rot

Persist lifetime Rot separately from Tonight's Rot.

It is comic/statistical only. Do not use it to permanently lock players into harsher content. Installation/category Familiarity controls content progression more safely.

## Prize persistence

Most prizes are a one-night gag. A selected subset may:

- become a podium/studio prop next session;
- trigger one future line;
- enter profile history;
- disappear later with no explanation.

Do not make all prizes inventory items.

## Announcer progression

May persist slowly across sessions. Treat as an atmospheric thread, not a linear story campaign.

Possible stages:

0. purely functional;
1. unusually specific;
2. disagreement;
3. attempts to control/end transmission;
4. rare private contact.

Do not guarantee monotonic escalation every session. Stage unlocks can change eligible content; actual incidents remain probabilistic.

## Graham persistence

Graham generally resets to normal presenter professionalism each new broadcast.

Persist only traces:

- rare grudge callback;
- returning favourite callback;
- old joke label;
- prior prize;
- memorable category history.

Do not implement `evil Graham level 4`.

## Room state persistence

Rooms have persistent state history but may change non-linearly.

Store:

- current state ID;
- previously seen state IDs;
- eligibility flags;
- last-seen session;
- chain prerequisites.

Allow return to a normal state. Do not visually telegraph a simple progression tree.

## Installation seed

Generated on first run and stored persistently.

May affect a small subset of:

- legendary incident possibilities;
- session quirk weighting;
- room variation eligibility;
- rare archival oddities.

Never show it in normal UI.

## Save schema versioning

All persistent save structures must contain schema versioning and migration support from the start.

Requirements:

- no routine wipe on app update;
- migration tests;
- safe fallback/backup before migration where practical;
- log migration errors in development;
- preserve known data when a new field is added.

## Session recovery

Maintain a crash/restart recovery snapshot periodically and at major round transitions.

At minimum recover:

- roster/profile mapping;
- score/Rot;
- current segment/game;
- current/previous content IDs;
- Director snapshot;
- persistent flags already committed;
- in-progress recoverable input references where possible.

On restart:

> RESUME INTERRUPTED TRANSMISSION

The user may decline and start fresh.

## Reset controls

### Reset Players

Clears local player profiles/associated personal memory while preserving broadcast installation history where feasible.

### Reset Broadcast History

Clears installation Familiarity/event/room/Announcer progression while preserving player profiles where feasible.

### Reset Mildew

Full local reset:

- profiles;
- installation seed;
- Familiarity;
- room states;
- incident chain history;
- advert history;
- awards/prizes;
- all persistent broadcast memory.

Require a clear confirmation. This is a real settings operation, not a joke.
