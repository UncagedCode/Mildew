# 10 — Debug, Testing and Development Tooling

Mildew is too stateful/procedural to test manually with eight physical phones for every change. Development tooling is a first-class requirement, not optional polish.

## Fake player system

Developer builds must be able to create 2–8 fake players without physical phones.

Bot personality presets:

- fast/random;
- high-accuracy;
- terrible;
- gross-answer writer;
- contrarian voter;
- passive/AFK;
- risk-taker;
- cautious;
- repeated-category bot (e.g. Horse Bot);
- coordination mistake bot.

Bots should trigger enough realistic behaviour to test Graham relationship/Director logic.

## Director debug overlay

Development-only overlay should display and allow controlled editing of:

- current game/round;
- episode skeleton/candidate slots;
- Graham visible state;
- Graham relationship weights by player;
- punishment eligibility/cooldowns;
- Pressure;
- Complicity;
- Degradation;
- Interference mode;
- recent tonal-density values;
- Familiarity;
- installation seed (dev only);
- incident cooldowns/prerequisites;
- room states;
- Announcer progression;
- content history;
- persistent chain flags;
- session runtime/overrun state.

Release builds must not expose these.

## Force actions

Developer controls should support:

- force any game;
- force game variant;
- force next content item;
- force advert;
- force room cutaway;
- force incident by ID;
- force private message by ID/target;
- force Graham relationship state;
- force Graham mood;
- force punishment;
- force Announcer stage;
- set score;
- set Rot;
- simulate disconnect/reconnect;
- simulate late join;
- jump to scoreboard;
- jump to commercial break;
- jump to awards;
- accelerate timers;
- mark content seen/unseen;
- change room state;
- trigger crash-recovery snapshot.

## Full broadcast simulation

Provide `SIMULATE FULL BROADCAST` or command-line/headless equivalent.

Capabilities:

- accelerated timers;
- bots auto-answer;
- configurable player count;
- configurable number of sessions;
- seed control in dev;
- collect Director decision logs;
- output failures/warnings;
- detect deadlocks;
- collect selected-content distribution;
- measure incident density/pacing;
- confirm finale/credits reached.

## Automated test gates

Before a checkpoint is complete:

### Core

- project loads/imports;
- unit tests pass;
- content validation passes;
- build/export succeeds where build environment is available.

### Player-count

- 2-player accelerated session completes;
- 8-player accelerated session completes;
- relevant intermediate counts sampled.

### Networking

- join flow;
- duplicate-name handling;
- late join wait state;
- disconnect pause;
- reconnect before 30 sec;
- failure to return;
- all disconnect;
- stale/replayed invalid client messages rejected.

### Game state

- no game can deadlock because one client is silent;
- timers resolve;
- score/Rot remain server authoritative;
- 2-player adaptations allocate valid roles/content;
- no impossible Do Not Press That role layout;
- Basement has valid theory scoring.

### Director

- final game always selected unless a deliberate end-transmission condition applies;
- major incidents respect cooldowns;
- sinister-density guard works;
- normal game variety constraints work;
- punishment target cooldown works;
- no repeated core game under normal selection rules;
- deliberate repeated-content flags override correctly;
- run-over remains bounded.

### Persistence

- save/load;
- migration test;
- profile persistence;
- reset scopes;
- room state persistence;
- installation seed persistence;
- crash recovery at supported boundary.

### UI

- essential TV text stays in safe/readable area;
- phone controls fit target viewport;
- controller can recover after orientation/browser resize;
- drawing input remains usable;
- pause/end remains reachable.

## Pacing metrics

Automated reports should include approximate:

- game type distribution;
- average episode duration;
- average/maximum incident density;
- tier distribution;
- repeated-category streaks;
- average number of punishments;
- average private interference targets;
- proportion of very clean sessions;
- finale type distribution;
- content repetition rate.

Do not use tests to eliminate all randomness; use them to detect pathological randomness.

## Director decision logs

Development logs explain *why* a segment/event was selected.

Example:

```text
[Director] SelectGame(HOLE)
reason:
  previous_mechanic=social
  desired_energy=high
  sinister_density=0.71 -> comedy_reset_weight +0.40
  player_count=4 compatible
  recent_game_history excludes HOLE
  expected_duration=360s fits runtime budget
```

For an incident:

```text
[Incident] tier2.private_plea.green_room eligible
pressure=0.62 OK
cooldown OK
requires_green_room_seen=true OK
recent_sinister_density=0.31 OK
target=player_2 weighted_random
rolled=true
```

These logs are for developers, not players.

## Content Browser

See content spec. It should allow preview/force-run/filter/disable and show source/licence data.

## Network diagnostics

Developer lobby should expose:

- host LAN IP;
- serving port;
- controller URL;
- client IDs;
- round-trip latency;
- reconnect token state;
- protocol version;
- dropped/invalid message count;
- current server state.

Never show technical diagnostics in normal broadcast unless deliberately surfaced as fictional non-authoritative graphics.

## Test reports

Each checkpoint records:

- commit/hash if available;
- engine/toolchain versions;
- APK output path/version;
- tests executed;
- player-count simulations;
- failures;
- performance observations;
- known limitations;
- next remediation.

Use `templates/TEST_REPORT.md` as starting structure.
