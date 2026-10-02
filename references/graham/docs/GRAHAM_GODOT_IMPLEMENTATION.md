# Godot Implementation Plan — Low-Budget Graham Presenter

Target: Godot 4.x, Android TV first.

## Architecture goal

Graham presentation must be **asset-swappable**. Game/Director logic should request semantic states (`neutral`, `irritated`, `reading_cards`) rather than filenames or specific video clips.

This makes it possible to replace a still with:

- a better still;
- an animated sprite;
- an alpha-cutout puppet;
- a short video;
- a future performance-capture asset;

without changing game logic.

## Recommended scene structure

```text
GrahamPresenter (Control)
├── PlateA (TextureRect)
├── PlateB (TextureRect)
├── MotionSequence (AnimatedSprite2D/TextureRect) # optional / rare
├── SafeFrameMask (Control)
├── PresenterAnimation (AnimationPlayer)
├── CameraMotion (AnimationPlayer)
├── StateTimer (Timer)
├── SpeechPlayer (AudioStreamPlayer)
└── DebugLabel (Label)                     # development only
```

`PlateA` and `PlateB` allow crossfades without destroying the current image.

## Do not make GrahamPresenter authoritative

GrahamPresenter renders what the Director tells it.

The Director owns:

- Graham mood;
- relationship/target state;
- incident eligibility;
- line selection;
- intended emotional beat.

GrahamPresenter owns:

- which asset represents the requested visual state;
- transition/crossfade;
- optional micro-camera motion;
- video excerpt playback;
- visible speech bridge timing.

## State model

Initial state IDs:

```text
neutral
restrained_smile
presenter_smile
presenting
reading_cards
irritated_turn
irritated_hold
return_tense
recovered_presenter
presenting_gesture
open_hand_gesture
```

Missing future states should still be represented in code but fall back gracefully:

```text
disappointed -> neutral
amused -> restrained_smile
rattled -> return_tense
angry -> irritated_hold
stare -> neutral
off_air -> reading_cards
```

Never throw an error because a cosmetic presenter state is missing.

## Transition types

### CUT
Use between genuinely different broadcast cameras/angles.

### DISSOLVE_SHORT
80–160 ms. Useful for minor full-frame still substitutions after a cutaway.

### CAMERA_BRIDGE
The preferred emotional transition:

1. leave Graham shot;
2. set hidden next Graham state;
3. return later.

### MOTION_BRIDGE
Play an existing motion excerpt such as `recover_to_camera.mp4`, then settle on a still.

Use sparingly because Android TV video decoding should not become a requirement for every line.

## Camera-plate micro-motion

For still plates only:

- duration: random 3–8 sec;
- scale: 1.000 -> 1.002–1.007;
- x/y movement: max ~3 px at 960×720 reference scale;
- use ease-in-out;
- occasionally no motion at all.

This represents imperfect live camera operation, not breathing.

## Speech strategy

### Pre-authored line with matching motion
Play corresponding video/motion if available.

### Dynamic line
Preferred flow:

```text
show presenting state
start dynamic audio
hold visible mouth bridge 0.5–1.2 sec
cut to relevant graphic/player/scoreboard
continue audio off-screen
return to reading_cards / reaction state
```

### Very short dynamic comment
A quick state swap among `speech_cycle` frames is acceptable under broadcast softness.

Recommended rate: roughly 5–8 frame changes/sec, randomized rather than a perfectly repeating ABCD loop.

Avoid more than ~1.5 sec of obvious fake mouth cycling without a cutaway.

## Mouth-cycle implementation

`assets/stills/speech_cycle/speech_01.png` through `speech_04.png`

Do not map these to phonemes. Use them as a noisy presentational bridge only.

Possible selection:

```gdscript
var last_index := -1
func next_speech_frame() -> int:
    var choices := [0, 1, 2, 3]
    choices.erase(last_index)
    last_index = choices.pick_random()
    return last_index
```

The purpose is to avoid robotic four-frame repetition.

## Blink plan

No suitable locked blink pair currently exists.

For the first proof of concept:

- do not fake aggressive procedural eyelids;
- rely on camera cuts and existing short motion clips;
- add a proper blink pair later as a small image-generation/editing task.

A bad blink will hurt realism more than no visible blink during short shots.

## Shot duration guidance

Typical Graham still shot: **1.0–4.0 sec**.

Longer holds are allowed when intentionally uncomfortable, but should be deliberate Director events rather than normal hosting.

## Motion excerpt use

Existing zero-cost motion references are supplied as MP4 **reference files**, not guaranteed native Godot runtime assets. Godot's built-in video support should not be assumed to play these H.264 MP4s directly. For a runtime use, either convert the selected excerpt to the project's supported video format or, preferably for short clips, extract an optimized frame sequence / sprite animation.

Existing references:

- irritation reaction;
- recovery to camera;
- reading cards;
- presenting gesture.

For Android TV proof of concept, prefer a reduced frame sequence for these very short motions. Benchmark before making any video decoder a core dependency.

## Runtime resolution strategy

Reference art is 960×720 (4:3).

Recommended first broadcast render target:

- internal broadcast viewport: 960×720 or 768×576;
- TV shell/UI: 1920×1080;
- broadcast plate scaled into 4:3 region;
- 25 fps visual cadence is stylistically acceptable;
- main Godot UI can still run at 60 fps.

## Broadcast shader

Apply analogue processing to the **broadcast viewport**, not separately to Graham states. This guarantees consistent treatment of:

- Graham;
- question graphics;
- adverts;
- studio feeds;
- incident cutaways.

Keep processing restrained enough that text remains readable.

## Performance rules

- Preload likely next Graham textures.
- Do not load large PNGs synchronously during a camera cut.
- Keep only a small LRU set if memory is constrained.
- Consider WebP/runtime-compressed textures after visual QA; retain PNG masters in source assets.
- Never downscale master source files destructively.

## Development debug controls

Add buttons/commands to force:

- every Graham visual state;
- every transition type;
- every motion reference;
- dynamic speech with cutaway timing;
- Pressure-driven state change;
- anger recovery;
- 30-second reconnect waiting performance.

A `Graham Gallery` debug screen should show all states side by side with filenames and fallback relationships.
