# 14 — Proof-of-Concept Acceptance Criteria

The user's priority is a **working proof of concept as close to the intended finished experience as possible**, not a throwaway prototype.

## Serious PoC success statement

The proof of concept succeeds when:

> Mildew installs on the user's Android TV, at least two people join from ordinary phone browsers over local Wi‑Fi without internet, they complete a Director-generated broadcast, the games themselves are genuinely fun/gross/social, the presentation convincingly feels like Mildew rather than generic software, at least one unpredictable event creates a real “what the fuck was that?” reaction, the game remains technically trustworthy/readable, and the group wants another episode.

## Mandatory functional criteria

- Android TV APK installs and launches.
- 2–8 phone clients can join locally.
- No cloud/account requirement for normal play.
- QR/local URL join works.
- New/returning profile flow works.
- Name/pronunciation architecture exists.
- Real authoritative session server works.
- Reconnect pause up to 30 seconds works.
- Late join between games works.
- All eight launch games are playable end-to-end.
- Explicit 2-player adaptations work.
- 45-minute Director-generated broadcast works.
- Midpoint commercial break works.
- Manual pause/end works.
- Finale/awards/prize/credits work.
- Score and Rot systems work.
- Player/install persistence works at PoC level.
- Viewer Information Service can show sourced factual content.

## Mandatory Mildew identity criteria

- broadcast visually reads as late-1990s British TV;
- fictional 4:3 frame is used;
- Graham is visible and has multiple emotional states;
- real camera grammar/cuts exist;
- audience audio exists;
- game stings/music exist;
- analogue treatment exists without harming readability;
- at least 8–12 polished fake adverts across 5+ identities/styles;
- at least 4–5 recurring backstage rooms with state variants;
- Announcer exists;
- private phone interference exists;
- Tier 0–2 incidents exist;
- small Tier 3 sample exists;
- persistent room/event chain examples exist;
- one developer-testable Tier 4 chain proves framework;
- 1–2 hidden Interruption Games exist;
- Graham favourites/dislikes/punishment basics exist;
- Familiarity progression exists.

## PoC content minimums

- Guess the Genitals: 15–20 usable items
- Hole: 20–30
- Real or Mildew?: 30–40
- Survey: 40–60 prompts
- Police Sketch: 30–40 prompts
- Do Not Press That: 8–12 good puzzles
- Basement: 6–8 good cases
- Mouthfeel: 40–60 prompts/components

Content may contain approved placeholders where licensing/art production is incomplete, but placeholders must be clearly tracked and the visible presentation should remain on-brand.

## Quality criteria

- no routine programmer-art rectangles in the main player experience where an on-brand temporary asset is feasible;
- no game relies on external AI/cloud at runtime;
- active gameplay text remains readable under broadcast effects;
- phone controls fit supported portrait screens;
- core session cannot deadlock from one AFK player;
- no real disconnect is obscured by fiction;
- save migrations are versioned;
- release/dev tooling separation exists.

## Automated reliability criteria

Before calling serious PoC ready:

- content validator passes;
- 2-player accelerated full sessions pass;
- 8-player accelerated full sessions pass;
- hundreds of accelerated Director sessions run without deadlock/crash attributable to session state;
- reconnect simulation passes;
- late-join simulation passes;
- all supported games allocate valid low/high player layouts;
- no uncontrolled incident clustering beyond configured guardrails;
- final segment/credits reachable;
- APK export succeeds.

## Performance criteria

Target:

- normal presentation near 60 FPS on mid-range Android TV;
- occasional transition-heavy 30 FPS acceptable;
- controller response should feel immediate on normal home Wi‑Fi;
- no significant sustained memory leak across a full 45-minute session;
- adverts/Graham/room assets should not cause disruptive stalls.

If the user's actual Android TV cannot sustain the intended experience after sensible optimisation, document the measured bottleneck and bring the platform fallback (including Xbox Series X Developer Mode) to the user before changing the experience.

## What is not required before serious PoC

- full 60–100+ / 200+ mature content libraries;
- full 20–30+ advert mature library;
- large Tier 4 catalogue;
- final voice-actor-quality Graham audio;
- audience mode for additional non-contestants;
- online internet multiplayer;
- live content download service;
- Xbox host build.

The architecture should leave room for these where applicable.
