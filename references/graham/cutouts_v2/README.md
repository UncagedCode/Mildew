# Graham alpha cut-outs — batch v2 (user-supplied 2026-10-02, generated to REQUEST_cutouts_v2.md)

18 true-alpha PNGs, 1086×1448, same framing as batch v1. Masters — never edit in place.
Names assigned by Claude from visual review + alignment measurement (files arrived unnamed).

| File | Notes |
|---|---|
| talk_closed.png | talking set base; lips together, faint smile. Aligned to v1 neutral within 0.8 px |
| talk_half.png | talking set |
| talk_open.png | talking set ("ah") |
| talk_open_wide.png | talking set, wider "ah" (bonus frame) |
| talk_round.png | talking set ("oo"); ~2 px vertical offset vs base |
| neutral_blink.png | eyes closed, faint smile — blink partner for talk_closed / v1 neutral |
| restrained_smile.png | default friendly smile |
| restrained_smile_blink.png | blink partner for restrained_smile (0.5 px) |
| presenter_smile.png | broad toothy smile |
| laughing.png | open laugh; locked to presenter_smile (0.3 px) |
| reading_cards.png | head down reading |
| irritated_turn.png | eyes/head toward screen-right, smile gone |
| irritated_hold.png | side-facing, lips pressed |
| return_tense.png | back to camera, talking, brow tense |
| recovered_presenter.png | professional smile back, slight head tilt (~5 px offset) |
| presenting_gesture.png | open hand, cards in other hand |
| look_off_left.png | glance toward screen-left, mild smile |
| podium_glance.png | glance toward screen-right (contestants), mild smile |

Alignment (phase correlation vs talk_closed): talking frames ≤ 2 px, blinks ≤ 1 px. Body texture
differs slightly between frames (regeneration noise), so the importer registers each locked-set
frame and composites only the face region onto the base body to avoid flicker.

Not delivered (optional, not needed for the PoC): applause_ack. Fallback: podium_glance / restrained_smile.
