# 06 — Networking and Platform Architecture

## Platform strategy

### Primary

- Godot 4.x host application on Android TV / Google TV.
- Mid-range Android TV hardware is the design target.
- 16:9 TV output; fictional programme normally framed as 4:3.
- Players join with phone browsers over local Wi‑Fi.
- Core multiplayer must not depend on internet/cloud services.

### Secondary / contingency

The user has Xbox Series X Developer Mode and may use a stronger host if Android TV proves too constrained. Do not make Xbox a first-checkpoint dependency. Preserve portability by separating:

- Director/session logic;
- content model;
- controller protocol;
- persistence model;
- broadcast rendering/platform glue.

Do not hard-wire game logic to Android APIs.

## Logical application layers

### 1. Broadcast Client

Responsibilities:

- TV rendering;
- Graham animation/presentation;
- 4:3 broadcast composition;
- camera switching;
- game visuals;
- scoreboards;
- adverts;
- audio mixing;
- visible reconnect/pause states.

### 2. Mildew Server / Director

Authoritative state owner:

- rooms/sessions;
- player identity/profile mapping;
- current game/round;
- validation of player actions;
- scoring;
- Rot;
- Director state;
- incident eligibility;
- content selection;
- persistence writes;
- reconnect/session resume;
- broadcast event stream;
- controller-specific hidden payloads.

### 3. Controller Client

Local static web app served by the host.

Responsibilities:

- player join/profile selection;
- answer buttons;
- text entry;
- voting;
- drawing canvas;
- Do Not Press That control panels;
- Basement private clues;
- private interference rendering;
- vibration where browser/device permits;
- reconnect/resume UX.

Controllers are **not trusted** to compute authoritative points, Rot, timers or game progression.

## Local hosting model

The Android TV process must expose a local HTTP endpoint to serve the controller bundle and a persistent real-time channel, preferably WebSocket or an equivalent low-latency local protocol.

The exact implementation mechanism may be chosen during Checkpoint 1 based on reliability:

- pure Godot networking / TCP + WebSocket handling; or
- a small embedded Android/Kotlin server module wrapped cleanly behind a host-network interface.

This is an implementation choice, not a design change. Choose the simplest reliable path that can later be implemented on another host platform behind the same protocol.

## Session/join flow

1. Host launches Mildew.
2. `BEGIN TRANSMISSION`.
3. Graham appears and complains there are no contestants.
4. Host starts local session server.
5. TV displays:
   - QR code;
   - short local URL fallback;
   - four-character room code for manual entry.
6. QR contains local URL + ephemeral session token/room information, so QR users do not retype room code.
7. Phone loads controller app.
8. Phone chooses returning local profile or `NEW CONTESTANT`.
9. TV displays contestant/podium.
10. Minimum 2 active contestants required to begin.

With one contestant:

> “One is not really a party.”

## Local security model

This is a trusted home-LAN party experience but should still avoid careless exposure.

Recommended:

- bind only to appropriate LAN interfaces;
- ephemeral room/session token;
- short-lived client reconnect token;
- reject arbitrary commands outside current game state;
- validate payload sizes and types;
- same-origin controller resources where possible;
- simple rate limiting against accidental spam;
- no internet-facing port forwarding assumption;
- never accept client-supplied score/role/Director values.

## Controller protocol design

Prefer explicit event/state messages rather than coupling controller HTML to game internals.

Example server -> controller concepts:

- `session_state`
- `player_profile_state`
- `show_screen`
- `question`
- `vote_options`
- `drawing_prompt`
- `drawing_state_restore`
- `private_clue`
- `puzzle_panel`
- `timer_sync`
- `interference_payload`
- `reconnect_state`
- `spectator_wait`

Controller -> server:

- `join`
- `select_profile`
- `create_profile`
- `answer`
- `submit_text`
- `submit_vote`
- `drawing_delta` or `drawing_submit`
- `control_action`
- `ready`
- `reconnect`
- `leave`

Include protocol versioning early.

## Phone browser targets

Initial practical compatibility priority:

1. Current Android Chrome
2. Samsung Internet
3. iPhone Safari / modern iOS WebKit where practical

Use standards-based HTML/CSS/JS so iOS remains possible even though Android TV is the host.

No controller app installation/PWA requirement for ordinary play.

## Phone orientation

Portrait-first.

Drawing may use a large portrait canvas with full-screen mode. Do not require players to rotate unless a future specific mechanic clearly benefits.

## Profile join flow

Phone initially resembles institutional hardware:

> MILDEW HOME RESPONSE UNIT
>
> CONNECTION ESTABLISHED
>
> IDENTIFY YOURSELF

Options:

- returning profiles;
- `NEW CONTESTANT`.

### Duplicate / same-name handling

Exact active/display duplicates are not allowed.

If a new contestant types a name matching an **inactive local profile**:

TV can trigger Graham:

> “We've had a Stacy before.”

Other active phones:

> IS THIS ACTUALLY STACY?
>
> YES / NO / I DON'T KNOW

If accepted, offer association with old profile. If not, require a distinguishable name such as `Stacy B`.

Do not automatically infer identity based on name.

## Name pronunciation

Player names must be speakable by Graham.

Profile creation:

1. enter display name;
2. local speech path attempts pronunciation;
3. phone/TV asks `Is this pronunciation correct?`;
4. player confirms or chooses/enters a pronunciation variant supported by the TTS pipeline;
5. store display name separately from speech form.

Restrictions:

- sensible length;
- supported characters;
- exact duplicate handling;
- reserved names can trigger Graham reactions rather than simply failing (e.g. someone calls themselves Graham), provided technical identifiers remain safe.

Adult profanity may be accepted within normal safety/technical constraints.

## Late join

Late join is allowed **between games**.

If a new player connects during an active game:

- complete profile selection;
- place in waiting/spectator controller state;
- integrate at next safe game boundary;
- Graham may comment on their lateness.

Do not inject them halfway through a chain/puzzle that cannot fairly assign state.

## Voluntary leave

A player may leave. If at least two players remain, continue after appropriate transition. Their podium can darken/clear.

## Disconnect/reconnect

Active-player network loss:

1. detect disconnect;
2. pause gameplay progression;
3. start maximum **30-second reconnect window**;
4. Graham reacts/fills time/silence;
5. if client reconnects, restore state and resume immediately;
6. preserve text/drawing/current panel state where practical;
7. if window expires, remove player from active participation and continue if enough remain.

Presentation examples:

> “We've temporarily misplaced Sarah.”

At 15 seconds:

> “Sarah?”

Reconnect:

> “There she is!”

Failure to return:

> “Sarah has elected not to return.”

or ambiguously:

> “We've lost Sarah. Again.”

Even if it was the first real disconnect.

## Everyone disconnects

Give the normal reconnect window. If nobody returns, Graham becomes visibly annoyed and ends transmission.

> “Fine.”

Do not keep an abandoned session running forever.

## One player remains

Pause/wait for reconnect/join rather than attempting unsupported solo versions.

## Real vs fictional failure

Never make a real network failure indistinguishable from a fictional glitch.

Allowed fictional effects:

- fake broadcast static;
- controller content weirdness;
- fictional `SIGNAL` graphics inside a game/interference event.

Not allowed:

- fake browser disconnected page;
- fake OS Wi‑Fi error;
- hiding a real disconnect warning;
- pretending a genuine missing client is merely an incident.

## TV remote

Normal gameplay should not require the remote.

Remote/system controls provide:

- pause;
- broadcast settings;
- end transmission;
- development/debug access in non-release builds.

## Crash/session recovery

Persist sufficient in-progress session state periodically so an unexpected host restart may offer:

> RESUME INTERRUPTED TRANSMISSION

Recovery priority:

- player profiles/session roster;
- score/Rot;
- current game/round;
- content IDs already used;
- Director state snapshot;
- current persistent flags.

Exact mid-animation recovery is less important than restoring a coherent round boundary.

## Performance/network budget

Use low-bandwidth state messages. Do not stream video to phones.

Drawing should avoid sending full PNG every frame. Prefer local stroke capture with bounded delta updates and final compressed image/stroke data.

Controller UI should be resilient to modest Wi‑Fi latency. Use server-authoritative deadlines and client clock sync for timers.

## Android TV fallback planning

Do not prematurely abandon Android TV because of visual ambition. Optimise:

- pre-rendered Graham loops;
- texture atlases;
- limited simultaneous heavy video layers;
- efficient post-process pass;
- compressed audio;
- sensible room/ad asset streaming;
- 1080p reference rather than native 4K.

If profiling proves the target experience cannot run acceptably on the user's hardware, document exact bottlenecks and propose platform fallback before changing product behaviour.
