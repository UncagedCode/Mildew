# Graham Voice Integration — Low-Budget Strategy

## Goal

Graham's voice should feel coherent without requiring every possible line to be pre-recorded or lip-synced to video.

## Two-layer architecture

### Layer A — authored/pre-rendered lines

Use for high-frequency or performance-critical material:

- opening greeting;
- standard game introductions;
- rules explanations;
- common correct/wrong reactions;
- adverts;
- major punishment setups;
- major incident dialogue;
- anger/irritation moments where delivery matters.

These can be rendered in batches when a suitable voice solution is available.

### Layer B — offline dynamic speech

Use for:

- player names;
- scores;
- temporary titles;
- session-specific statistics;
- procedural callbacks;
- reconnect commentary;
- dynamically selected short linking phrases.

The architecture must permit the dynamic TTS provider to be replaced later.

## Player names

Profiles store a validated speakable pronunciation. Do not infer identity from the spelling beyond the profile workflow defined by the main Mildew spec.

## Editing around dynamic TTS

Dynamic speech does not require visible mouth animation.

Preferred camera flow:

1. Graham begins or sets up the line.
2. Cut to the person/scoreboard/graphic.
3. Dynamic name/number speech happens over that shot.
4. Return to Graham after the unpredictable portion.

## Emotional consistency

Do not use bright default TTS delivery for a line that is supposed to be angry/rattled if the voice system cannot produce that emotion convincingly.

Fallback options:

- shorten the spoken line;
- use a pre-authored anger line followed by text/graphic for the dynamic portion;
- let Graham say nothing and use silence/visual reaction.

Silence is preferable to obviously wrong performance.

## Subtitles

All spoken lines should have a subtitle/caption representation available for accessibility and debugging. Subtitle timing should not force the broadcast to display every caption by default if that conflicts with final UI direction; accessibility settings decide presentation.

## Source audio

`reference/audio/graham_final_voice_performance_reference.wav` is a performance reference, not a promise that the exact generated voice can or must be cloned.
