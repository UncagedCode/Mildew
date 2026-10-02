# Existing Graham Asset Inventory

## Summary

The current footage already supplies enough material to build a convincing **first presenter system** without buying more AI video generation.

## Canonical full-frame states

| State | File | Source | Use | Quality |
|---|---|---|---|---|
| Neutral front | `assets/stills/canonical/neutral_front.png` | Final clip | waiting, stare, deadpan | Canonical |
| Restrained smile | `assets/stills/canonical/restrained_smile.png` | Final clip | default friendly Graham | Canonical |
| Presenter smile | `assets/stills/canonical/presenter_smile.png` | Final clip | applause, reveals | Canonical |
| Presenting / speaking | `assets/stills/canonical/presenting_speaking.png` | Final clip | visible start/end of dialogue | Canonical |
| Irritated turn | `assets/stills/canonical/irritated_turn.png` | Final clip | reaction transition | Canonical |
| Irritated hold | `assets/stills/canonical/irritated_hold.png` | Final clip | rare annoyed Graham | Canonical |
| Return tense | `assets/stills/canonical/return_tense.png` | Final clip | recovery transition | Canonical |
| Recovered presenter | `assets/stills/canonical/recovered_presenter.png` | Final clip | post-irritation hosting | Canonical |
| Reading cards | `assets/stills/canonical/reading_cards.png` | Final clip | natural hiding/cutaway state | Canonical |

## Supplementary states

| State | File | Source | Use | Restriction |
|---|---|---|---|---|
| Presenting gesture | `assets/stills/supplementary/presenting_gesture.png` | First clip | one-hand explanatory gesture | final clip wins if identity drifts |
| Open hand gesture | `assets/stills/supplementary/open_hand_gesture.png` | First clip | energetic reveal / hosting | expression is somewhat broader than preferred |

## Crude speech-cycle frames

`assets/stills/speech_cycle/`

Four neighbouring frames from the final clip provide different mouth shapes and tiny natural shifts. These may be used for **very short low-resolution speaking loops**, especially after analogue softening.

They are not true lip-sync visemes. Do not cycle them rapidly for long dialogue. Recommended use:

- 0.4–1.5 seconds at the start of a line;
- cut away to question/scoreboard/podium;
- return to a neutral or reaction state at the end of the line.

## Face crops

`assets/face_crops/`

512×512 crops exist for visual comparison and future recreation/generation. These should not automatically be treated as runtime assets. Their main purposes are:

- identity matching;
- evaluating new stills;
- future image generation reference;
- facial-expression reference.

## Video references

### Primary
`reference/video/graham_canonical_reference_clean_4x3.mp4`

The final approved reference.

### Supplementary history

- `reference/video/01_first_generation_clean_4x3.mp4`
- `reference/video/02_continuity_pass_clean_4x3.mp4`
- `reference/video/03_transition_pass_clean_4x3.mp4`

These document the development of the performance. They are useful for understanding what was rejected and improved, but they do not override the final clip.

## Zero-cost motion excerpts

These have been cut from already-generated material:

- `reference/motion/irritated_turn_hold.mp4`
- `reference/motion/recover_to_camera.mp4`
- `reference/motion/read_cards.mp4`
- `reference/motion/presenting_hand_gesture.mp4`

Potential uses:

1. Performance reference only.
2. Rare runtime FMV moments in a prototype.
3. Source for additional frame extraction.
4. Source for future rotoscoping/masking if a low-cost segmentation workflow is added.

Do not make the entire presenter depend on these clips. Static/motion-graphic operation must remain viable.

## Audio reference

`reference/audio/graham_final_voice_performance_reference.wav`

Use this to judge the intended general performance qualities:

- polished game-show cadence;
- British presenter tone;
- professional brightness;
- underplayed reaction rather than horror acting.

This file does **not** establish a permanent voice-provider dependency. The project's voice architecture must remain replaceable.
