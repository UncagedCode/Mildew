# 11 — Build Checkpoints and Required Order

## Governing rule

Every major checkpoint must leave Mildew **playable and buildable**, with an installable Android TV APK whenever the environment supports building/signing. Do not spend multiple checkpoints creating invisible infrastructure with no playable slice.

Prefer vertical-slice quality and Mildew identity over rapid generic breadth.

Before each checkpoint:

1. inspect current state;
2. read this checkpoint;
3. update `NEXT_BUILD.md`;
4. implement;
5. run checkpoint tests;
6. build APK;
7. update `PROGRESS.md`, `DECISIONS.md`, test report;
8. only then mark complete.

## Checkpoint 0 — Repo/bootstrap reconciliation

Goal: establish stable project/toolchain and documentation without changing product scope.

Tasks:

- inspect existing repo;
- pin Godot 4.x version once verified;
- establish Android TV export/toolchain;
- establish package/application identifiers;
- create core folder structure;
- import this package into repo if not already present;
- create progress/status docs;
- create design constants config;
- create basic test harness;
- establish build/version naming;
- ensure app can launch on Android TV target.

Gate:

- simple Godot APK installs/launches;
- repo status docs accurately reflect toolchain.

## Checkpoint 1 — Real LAN lobby + first playable slice

This must be a **real Android TV host**, not a desktop-only prototype.

Required:

- Mildew boot/ident styling;
- `BEGIN TRANSMISSION` flow;
- placeholder-but-on-brand Graham present;
- 4:3 broadcast composition inside TV output;
- minimal camera grammar;
- local HTTP controller hosting;
- QR/local URL + room code fallback;
- 2–8 real/fake phone clients can join;
- returning/new profile structure;
- display name + pronunciation scaffolding;
- simple avatar selection;
- TV podium/contestant representation;
- minimal authoritative server;
- minimal Director object/state;
- one simple test question;
- answer submission;
- score update;
- disconnect/reconnect 30-second flow;
- phone portrait UI styled as Mildew Home Response Unit;
- basic fake player support;
- dev network/Director diagnostics;
- installable APK.

Style requirement:

Do not use generic programmer UI as the visible player experience. Approximate final late-90s Mildew styling now.

Gate:

- 2 and 8 clients can join;
- real phone input changes TV state;
- reconnect works;
- server rejects invalid state action;
- APK runs on target;
- status docs updated.

## Checkpoint 2 — Hole vertical slice

Purpose: prove real content loading, staged TV reveal, timers, locking, scoring and Graham commentary.

Required:

- 20–30 PoC items or placeholder-approved subset sufficient for testing;
- multi-stage reveal;
- early lock;
- scoring values;
- broad-category partial credit framework;
- at least one variant;
- two-player works;
- short game sting;
- basic Graham line pools;
- basic audience reaction;
- content quality/status metadata;
- content validator begins.

Also begin Tier 0 production errors and very light Tier 1 irregularities.

Gate:

- full Hole game from lobby to scoreboard;
- 2–8 simulation passes;
- no content-repeat bug within game;
- APK.

## Checkpoint 3 — Real or Mildew? + Guess the Genitals

Purpose: prove sourced factual content architecture and larger trivia library.

Required:

### Real or Mildew?

- 30–40 PoC questions;
- text/image formats;
- factual reveal;
- confidence variant;
- source metadata;
- Viewer Information Service first version.

### Guess the Genitals

- 15–20 PoC items;
- animal-only content enforcement;
- image/licence approval fields;
- clinical presentation;
- biological fact reveal;
- themed/variant scaffolding;
- fast-answer Graham reactions;
- Rot award hooks.

Director now considers mechanical variety and opener/middle/finale tags.

Gate:

- three real games available;
- factual validator catches missing source/licence metadata;
- 45-minute synthetic playlist can use these games without crashing;
- APK.

## Checkpoint 4 — Mildew Survey + Mouthfeel

Purpose: prove text input, anonymous answers, voting, archive responses, social content and two-player filler.

Required:

### Survey

- 40–60 prompts;
- no self-vote standard rule;
- archive response system;
- two-player fill;
- Match normalization;
- Who Said That / Archive variant scaffolding;
- rare Graham answer alteration hook (dev-forceable; not frequent).

### Mouthfeel

- 40–60 prompts/components;
- text-first responses;
- multiple vote categories;
- Make It Worse chain;
- Graham anonymous answer;
- archive answer support;
- optional imagery.

Begin private phone interference framework after controller stability is proven.

Gate:

- text survives brief reconnect where practical;
- votes/server scoring authoritative;
- two-player rounds feel complete;
- private message can be force-tested;
- APK.

## Checkpoint 5 — Police Sketch

Purpose: prove drawing transport/state restore and chain mechanics.

Required:

- 30–40 prompts;
- crude canvas tools;
- 45–60 sec timers;
- 4+ interpretation chains;
- explicit 2-player flow;
- multi-category voting;
- chain fidelity scoring;
- sparse Graham commentary;
- reconnect preserves drawing state where practical;
- local historical drawing reuse hook.

Gate:

- drawing works on target phone browsers;
- no unbounded bandwidth use;
- 2-player and 8-player chain simulation;
- APK.

## Checkpoint 6 — Do Not Press That

Purpose: prove real-time asymmetric cooperative state.

Required:

- 8–12 strong PoC puzzles;
- explicit role allocation for 2–8;
- panels/instructions differ per phone;
- partial failure consequences;
- team + individual bonus scoring;
- success tiers;
- irrelevant controls;
- Graham blame/punishment hooks;
- dev-force rare timer irregularity;
- automated role-allocation validation.

Gate:

- no puzzle layout unsatisfiable for supported counts;
- reconnect behaviour defined for active puzzle;
- latency tolerance tested;
- APK.

## Checkpoint 7 — The Basement

Purpose: prove authored private-information deduction scenarios and longer discussion pacing.

Required:

- 6–8 strong cases;
- private evidence allocation;
- optional investigations;
- individual final theory submission;
- partial-credit theory scoring;
- definitive and partially unresolved case support;
- recurring location/character framework;
- 2-player multi-clue allocation;
- false/unreliable clue support without mandatory liar role.

Gate:

- all scenarios validate for 2–8;
- no missing evidence/theory path;
- APK.

## Checkpoint 8 — Full Director / standard broadcast integration

Purpose: turn the game collection into Mildew.

Required:

- partial episode skeleton planning;
- game tag selection;
- mood/tone balancing;
- Degradation;
- Complicity;
- Pressure;
- Familiarity;
- visible Graham emotional state;
- relationships/favourites/dislikes;
- punishments/cooldowns;
- midpoint commercial break;
- run-over support;
- end awards/prizes;
- scoreboards;
- Tier 0–2 incidents;
- small Tier 3 set;
- private interference targeting;
- recurring rooms (4–5 PoC rooms);
- 8–12 polished adverts / five+ brands;
- Announcer baseline/progression scaffolding;
- 1–2 Interruption Games;
- persistent room/event chain examples;
- developer-testable Tier 4 chain machinery.

Gate:

- complete 45-minute Director-generated broadcast;
- accelerated hundreds-of-sessions simulation without deadlock;
- pacing tests;
- all eight games can appear appropriately;
- APK.

## Checkpoint 9 — Persistence/polish/performance serious PoC

Required:

- versioned saves/migrations;
- player profiles;
- lifetime Rot;
- Familiarity persistence;
- Announcer progression;
- installation seed;
- room states;
- selected prizes/titles;
- crash recovery snapshot;
- Reset Players / Broadcast History / Mildew;
- hybrid Graham voice architecture;
- name pronunciation flow;
- improved camera/broadcast polish;
- post-process optimisation;
- Android TV profiling;
- content browser;
- Director overlay;
- release-mode separation from dev tools.

Gate = `docs/14_ACCEPTANCE_CRITERIA.md` serious PoC criteria.

## Future checkpoint themes

After serious PoC validation:

- expand content toward long-term targets;
- more adverts/brands;
- more room states;
- more interruption/punishment formats;
- deeper Tier 3–4 catalogue;
- improved Graham voice/visual assets;
- audience mode / larger observer counts if desired;
- host performance optimisation;
- investigate Xbox Series X Developer Mode / other host path if Android TV profiling justifies it;
- optional content-pack architecture.
