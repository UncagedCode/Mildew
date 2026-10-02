# 07 — Content System and Authoring Specification

## Core rule

Content must be separable from game code. Mildew is intended to grow into very large libraries; adding a question, advert, incident, Basement case or Graham line should not require rewriting gameplay logic.

## Suggested repository layout

```text
content/
  games/
    guess_the_genitals/
    hole/
    mildew_survey/
    real_or_mildew/
    police_sketch/
    do_not_press_that/
    basement/
    mouthfeel/
  incidents/
    tier0/
    tier1/
    tier2/
    tier3/
    tier4/
  adverts/
  interruption_games/
  graham/
    lines/
    reactions/
    pronunciation/
  announcer/
  audience/
  rooms/
  archive_responses/
assets/
  ...
```

Exact structure may evolve, but maintain conceptual separation.

## Content quality states

Every authored item should support:

- `placeholder`
- `draft`
- `reviewed`
- `approved`

Release policy can differ by content type, but factual release items should not silently ship in placeholder status.

## Enable/disable

Every item should be disableable without deletion. Reasons include:

- licensing unresolved;
- factual source disputed;
- broken asset;
- poor quality;
- duplicate content;
- temporary testing issue.

## Familiarity tiers

All normal content supports a Familiarity tier where relevant:

1. Accessible
2. Strange
3. Obscure
4. Seasoned-player
5. Extreme/“why does Mildew contain this?”

Installation/category Familiarity gates higher tiers gradually.

Avoid making tier 5 synonymous with explicit gore. It can also mean obscure facts, harder puzzles, stranger animals or deeply niche knowledge.

## Content tags

Suggested general tags:

- grossness 0–5;
- animal_anatomy;
- sexual_anatomy_animal;
- parasites;
- blood;
- medical;
- death;
- scatological;
- food;
- insects;
- eyes;
- teeth;
- mould/fungi;
- body_fluids;
- drawing;
- social;
- high_energy;
- low_energy;
- long;
- short;
- factual;
- fictional;
- unsettling_capable.

Tags primarily help pacing/content filtering and advanced settings. Do not expose a giant filter UI by default.

## Factual content requirements

Factual content requires source metadata before `approved`.

Store at minimum:

- source title;
- source publisher/organisation;
- source URL or bibliographic reference where applicable;
- date accessed/verified where useful;
- concise claim supported;
- fact-check status;
- reviewer/verification note.

For image/media:

- source;
- creator/rights holder if known;
- licence;
- attribution requirement;
- derivative-use notes;
- approval status;
- local asset path.

Do not silently use random online imagery.

## Viewer Information Service

Player-facing in-universe archive for legitimate facts shown recently.

Suggested title:

> MILDEW VIEWER INFORMATION SERVICE

May show:

- question/fact summary;
- common/scientific animal names;
- source/citation;
- factual context;
- viewed date/session.

Must **not** show:

- incident list;
- private interference history;
- rare-room discoveries;
- Director variables;
- lore completion.

## Repetition control

Track content IDs used recently at installation and session level.

Normal policy:

- avoid repeats within a session;
- strongly avoid repeats across recent sessions when library size permits;
- deliberate repeats can override this when authored for effect.

Examples of deliberate repetition:

> “We've done this one.”
>
> “Again.”

or a previously seen image returns with a new crop and Graham says:

> “You remember this one, don't you?”

## Memorable player outcomes

Do not persist every answer forever. Mark selected content items as `memory_candidate` or write rules that nominate memorable outcomes, e.g.:

- repeated specific wrong answer;
- extremely fast correct answer;
- notable confident failure;
- recurring Survey line;
- special award;
- unusual puzzle mistake.

This prevents save-state bloat and noisy callbacks.

## Archive response system

Used heavily by Survey and Mouthfeel, especially with two players.

Archive sources:

- authored fake historical contestant response;
- recurring fictional contestant;
- old local player response explicitly eligible for archive reuse;
- Graham-authored response;
- incident-specific anomalous response.

Metadata should distinguish internal source without necessarily exposing it to the player.

## Content target sizes

### Serious PoC

- Guess the Genitals: 15–20
- Hole: 20–30
- Real or Mildew?: 30–40
- Survey: 40–60
- Police Sketch: 30–40
- Do Not Press That: 8–12 strong puzzles
- Basement: 6–8 cases
- Mouthfeel: 40–60 prompts/components
- Fake adverts: 8–12 across at least five brands/styles
- Recurring rooms: 4–5 with variants

### Long-term target

- Guess the Genitals: 60–100+
- Hole: 80–120+
- Real or Mildew?: 150+
- Survey: 200+
- Police Sketch: 150+
- Do Not Press That: 30–50 puzzle templates/scenarios
- Basement: 25–40+
- Mouthfeel: 200+
- Fake adverts: 20–30+ minimum before a mature release

## Content validators

Create a command/tool/test suite that can fail CI/dev checks for:

- duplicate IDs;
- missing referenced asset;
- unsupported quality state;
- malformed player-count constraints;
- missing correct answer;
- answer count mismatch;
- missing factual source;
- factual image without licence metadata;
- invalid Familiarity tier;
- unknown tag;
- broken incident prerequisite;
- impossible follow-up ID;
- circular incident dependency where not explicitly allowed;
- missing pronunciation entry for required spoken dynamic content;
- Basement scenario with no scoreable theory;
- Do Not Press That puzzle with unsatisfied role allocation for supported player counts.

## Development Content Browser

Non-release tooling must provide searchable preview of:

- game content;
- images;
- factual metadata;
- Graham lines;
- Announcer lines;
- adverts;
- incidents;
- room state variants;
- archive responses;
- interruption games.

Features:

- filter by quality/Familiarity/tag;
- force-run item;
- show metadata/source/licence;
- see recent usage counts;
- flag/disable item;
- validate item.

## Creative vs factual separation

Keep fictional creative content structurally distinguishable from sourced factual material. A MEAT-O advert should not require a scientific citation; a claim about duck reproductive anatomy does.

## Voice line content

Graham lines should be data-driven with metadata such as:

- category;
- emotional state eligibility;
- target type;
- player-name insertion slots;
- familiarity requirements;
- relationship requirements;
- pressure range;
- cooldown;
- whether pre-rendered audio exists;
- dynamic-TTS fallback allowed;
- profanity/intensity tag.

## Interference content

Store source internally even when hidden from player:

- production;
- announcer;
- graham;
- unknown;
- impersonation;
- corruption;
- archive.

Messages can deliberately lie. Truthfulness should be metadata or event logic, never assumed from source label.
