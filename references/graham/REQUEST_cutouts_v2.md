# Request to ChatGPT — Graham alpha cut-outs, batch v2

Context: Mildew composites Graham as transparent cut-outs over its own studio background (D022).
Batch v1 (10 cut-outs) is in `references/graham/cutouts_v1/`. This batch fills the core hosting states.

## Technical spec (applies to every image)

- PNG with true alpha, transparent background, **1086 × 1448** — identical canvas to batch v1.
- **Same framing as batch v1 `neutral.png`**: same scale and position (top of head ≈ 60 px from the top,
  shoulders and hands in the same place). Images will be swapped in place, so any shift is visible as a jump.
- Same man, suit, shirt, patterned tie, lapel mic and lighting as batch v1. Clean-shaven, same hair.
- Cue cards: the **blue marbled cards** from `neutral.png`, held at waist height with both hands
  unless the state says otherwise. No logos, no text, no broadcaster branding anywhere.
- Clean edges (hair included), no leftover background, no drop shadows, no floor.
- Front-facing camera, medium shot, same lens/height as batch v1.

## Locked sets — create as edits of ONE base image, changing only the face

These are swapped many times a second, so the body, cards, tie and framing must be **pixel-identical**
across each set. Only the mouth/eyes may change.

1. **Talking set** — base: a talking-to-camera pose (friendly, mid-sentence, cards at waist).
   `talk_closed`, `talk_half`, `talk_open` ("ah"), `talk_round` ("oo"). Four images.
2. **Blink pair** — base: `neutral.png` from batch v1. `neutral_blink`: identical except eyes closed. One image.
3. **Blink pair** — base: the `restrained_smile` from item 4. `restrained_smile_blink`. One image.

## Single states (pose may differ, framing must match)

4. `restrained_smile` — the default friendly presenter smile: closed or barely open mouth, warm but practised. NOT a big grin.
5. `presenter_smile` — broad, toothy game-show smile for applause and winners.
6. `reading_cards` — eyes and head down, reading the cards.
7. `irritated_turn` — head starting to turn toward screen-right, eyes leading, smile fading.
8. `irritated_hold` — fully side-facing toward screen-right, lips pressed, jaw tight. Annoyed, not angry.
9. `return_tense` — back facing camera, speaking, smile not yet rebuilt; irritation still visible.
10. `recovered_presenter` — professional smile rebuilt but slightly tight.
11. `presenting_gesture` — one hand open toward camera, explaining, cards in the other hand.
12. `laughing` — genuine but restrained laugh, eyes creased.

## Nice to have (only if cheap)

13. `look_off_left` — glancing toward screen-LEFT (opposite direction to batch v1 `look_off`).
14. `podium_glance` — looking toward screen-right at contestants, neutral expression.
15. `applause_ack` — small nod and modest smile toward the audience.

## File naming

Return files named exactly as above (e.g. `talk_open.png`, `neutral_blink.png`), ideally zipped.
