# 08 — Art, Broadcast and Audio Bible

## Visual north star

Authentic **cheap British television circa 1997–1999**, not generic “retro horror VHS.”

The programme should look colourful, tacky, overproduced for its budget and slightly damp.

Reference qualities:

- 4:3 programme frame;
- ugly chrome 3D logos;
- purple/teal gradients;
- lens flares;
- fake depth/extruded titles;
- MDF studio scenery;
- patterned carpet;
- plastic plants;
- chunky CRT monitors;
- physical podiums;
- cheap gold/chrome accents;
- nicotine beige;
- mildew green;
- burgundy/purple;
- teal;
- bright late-90s broadcast colours;
- imperfect chroma key;
- practical curtains and lights.

Do not make everything dark. Mildew is often visually cheerful.

## TV framing

Android TV output is 16:9. The programme normally appears as a 4:3 broadcast within it.

Possible side treatment:

- subtle black/pillarbox;
- old-TV receiver/frame motif;
- simple broadcast surround;
- restrained decorative metadata.

Do not clutter the edges enough to compete with the programme.

Lobby/system screens may use wider composition when useful.

## Render quality vs old-TV appearance

Render assets/UI clearly at modern resolution, then **simulate** old transmission characteristics.

Effects may include:

- slight analogue softness;
- chroma bleed;
- interlacing impression;
- CRT bloom/glow;
- scanline suggestion;
- subtle noise;
- occasional tape dropout;
- occasional tracking error;
- compression/tape-generation variation.

Do not intentionally create low-resolution unreadable text.

Active question text, timers, reconnect state and settings must remain readable.

## Tape generations

Different source material may have different apparent quality:

- main studio: relatively clean broadcast master;
- older advert: softer/noisier;
- archive insert: third-generation VHS feel;
- odd backstage footage: inconsistent source generation.

This creates texture without applying one global horror filter.

## Graham visual specification

- convincingly human;
- late 40s–mid-50s;
- dated hair;
- cheap but presentable suit;
- iconic tie/outfit;
- heavy TV makeup;
- visible sweat under lights;
- highly practiced smile;
- never visually supernatural by default.

Hybrid FMV-style implementation:

- high-quality rendered/filmed-looking loops/states;
- composited into studio camera shots;
- dialogue driven separately;
- imperfect lip sync acceptable initially due to old-broadcast aesthetic, but should be believable enough not to feel broken.

Required PoC states:

- idle;
- speaking;
- smile;
- disappointed;
- irritated;
- angry;
- stare;
- looking off-camera;
- waiting/reconnect;
- laughing.

Add more states over time.

## Graham stress progression

Pressure may subtly alter appearance:

- loosened tie;
- extra sweat;
- hair displaced;
- makeup less perfect;
- posture more tired.

Do not rot/deform him into horror imagery.

## Studio layout

Core set elements:

- Graham presenter area;
- oversized physical `MILDEW` logo;
- contestant podium positions;
- CRT name/avatar displays;
- physical scoreboard/monitor surfaces;
- carpet;
- curtains;
- cheap MDF geometry;
- plastic plants/props;
- coloured practical studio lights;
- visible enough construction detail to feel cheap but intentional.

## Camera grammar

Establish normal camera language:

- Cam 1: Graham frontal medium;
- Cam 2: studio wide;
- Cam 3: contestant/podium angle;
- Cam 4: utility/roaming.

Normal live TV can include:

- tiny late cut;
- Graham looking at wrong camera;
- operator reframing;
- awkward pause before switch.

Then wrong-camera incidents gain meaning.

## Opening titles

Aggressively enthusiastic 1998 CGI:

- spinning chrome `MILDEW`;
- purple tunnel/background;
- flying symbols/question marks;
- green organic/mildew motifs;
- lens flares;
- cheap depth/extrusion;
- overconfident game-show music.

Mostly fixed for recognisability. Rare older/corrupted variants may occur.

## Minigame stings

Each game gets a short ~3–8 second title sting with its own cheap TV identity.

Examples:

- Guess the Genitals: triumphant brass + rotating clinical silhouette;
- Hole: ridiculous mystery sting + zooming circular motif;
- Real or Mildew?: faux-serious factual/news graphic;
- Survey: audience/game-show response-board styling;
- Police Sketch: police-file/drawing graphics;
- Do Not Press That: industrial emergency/control-room graphics;
- Basement: restrained investigative title, not overt horror;
- Mouthfeel: food/texture/consumer-show absurdity.

## Player avatars

PoC does not need a huge character creator. Use deliberately cheap late-90s contestant graphics.

Options can include:

- head/hair silhouette;
- glasses;
- simple face/feature set;
- outfit colour/pattern;
- one silly accessory.

Graham may make sparse comments about an avatar.

## Audience visuals

Normally:

- darkness;
- silhouettes;
- backs of heads;
- edge-of-frame glimpses.

Avoid clear bright full audience shots. Rare inconsistency may be an incident.

## Recurring rooms

First PoC: 4–5 fully realised rooms from the larger set.

Each room needs:

- normal base state;
- several subtle variants;
- at least one stronger incident state where appropriate;
- consistent camera angle(s);
- consistent geography cues;
- same broadcast treatment as other footage.

## Fake adverts

Adverts must not all look the same. Mimic multiple late-90s genres:

- cheap supermarket product;
- local furniture/carpet warehouse;
- insurance/corporate;
- pseudo-medical;
- public information film;
- mail order;
- family food product;
- home computer/electronics;
- travel/local tourism.

Recurring brands develop identities, packaging and jingles.

Candidate brands:

### MEAT-O

Mystery canned/processed meat.

Tagline territory:

> `Now containing meat.`

### DampAway

Mould/damp product presented too cheerfully.

### Mildew Home Computer

Ridiculous late-90s specs and partial Y2K compliance.

### Graham's Home Dentistry

Mail-order dentistry kit, possibly `Not endorsed by Graham` despite featuring him.

### BODY BAG PLUS

Presented like premium luggage; keep absurd, not graphic.

### E-Z Cremation

Deadpan local commercial; use tastefully enough to remain satire.

Final mature target: 20–30+ adverts.
Serious PoC: 8–12 polished adverts across at least five brands/styles.

Graham may occasionally appear in adverts and later deny/resent the endorsement.

## Audio north star

The soundtrack should mostly sound like tacky television, not horror.

### Main music

- game-show brass;
- cheap synths;
- library-music confidence;
- MIDI/orchestral feel;
- short jingles/stings;
- segment-specific motifs.

### Each game

Own musical identity within the same era/style.

The Basement should use investigative/restraint rather than horror drones.

## Graham voice

Hybrid pipeline:

1. Common authored lines can be pre-rendered in a consistent synthetic voice and bundled.
2. Dynamic names/scores/callbacks use offline local TTS.
3. Profile creation validates name pronunciation.
4. Dialogue system abstracts voice provider so future voice replacement does not alter game logic.

Do not depend on runtime internet.

Track licensing/redistribution status of any generated voice assets before public release.

## Announcer voice

Distinct from Graham:

- calm;
- formal;
- continuity-announcer style;
- reassuring initially;
- less emotionally expressive;
- later conflict becomes notable precisely because the voice was previously neutral.

## Audience audio system

Use layers, not a single applause clip.

Build separate pools for:

- tiny applause;
- medium applause;
- huge applause;
- polite laughter;
- big laugh;
- awkward laugh;
- boo;
- groan;
- gasp;
- murmur;
- isolated cough;
- isolated shout;
- chant;
- seating/movement.

Director should be able to combine/mismatch these intentionally.

## Spatial backstage audio

Where output configuration permits, place off-screen sounds spatially relative to studio orientation. A scream from backstage-left should feel off-camera, not like a centred sound effect.

Maintain graceful stereo fallback.

## Silence

Silence is a deliberate asset.

Examples:

- audience suddenly stops;
- reconnect wait with no banter;
- Graham stare;
- after off-camera conflict;
- before abrupt upbeat sting.

Do not fill every second with ambient scare noise.
