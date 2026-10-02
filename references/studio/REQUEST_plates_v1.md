# Request to ChatGPT — Mildew studio plates, batch v1

Mildew's studio is shown as **photographic still plates**, one per camera angle. The game composites
the presenter cut-out, podium screen graphics, lamp flicker and broadcast effects on top. So every
plate must be an **empty, clean, photoreal** image of the same studio.

## Applies to every image

- Photoreal, as if photographed in a real late-1990s British TV studio (1997–1999), regional ITV/BBC
  light-entertainment budget. Real materials: painted MDF flats, sponge-paint effects, chrome trim,
  gaffer tape, scuffs, cables, a slightly cheap look. Not CGI, not glossy, not modern.
- **4:3, 1600 × 1200**, PNG or high-quality JPG.
- **Clean image**: no scanlines, no VHS noise, no film grain, no vignette, no lens flares, no
  on-screen graphics, no captions, no channel logos/watermarks. (The game adds the broadcast look.)
- **No broadcaster or real-show branding.** The only text allowed anywhere is the show name **MILDEW**
  on the set signs.
- **No people** unless a plate says so.
- Consistent studio across all plates: same sign artwork, same colours, same carpet, same lighting rig.
- Contestant podium screens: **small built-in CRT screens, switched off — plain dark grey glass,
  facing the camera, nothing in front of them**. (The game draws the contestant on them.)

## Studio design (keep consistent)

Use the attached Graham reference frame as the style anchor: sage-green sponge-painted curved sign with
chrome bands top and bottom and chunky cream-yellow MILDEW lettering with an orange swoosh; a row of
coloured PAR-can lights (yellow, blue, pink, white, green) hanging from a dark rig; painted blue walls;
angled sage flats; a cream pillar with a red-framed monitor; a round presenter table with a chrome rim;
navy carpet with colourful 1990s ring/circle patterns. Contestant area: **eight podiums in a gentle
curved row**, each podium a chunky 1990s unit (sage/purple/teal panels, chrome edge strip) with a small
CRT screen in its front face and a coloured lamp strip along the top.

## Plates required

1. **`cam1_presenter_with_graham`** — the reference composition: presenter mid-shot, Graham standing at
   his mark holding the blue cue cards, sign and PAR cans behind. (Used only to align Graham.)
2. **`cam1_presenter_empty`** — the SAME image as 1 with Graham removed and the background filled in.
   Edit image 1; do not regenerate, so the framing stays identical.
3. **`wide_master`** — wide shot of the whole studio from the audience side, slightly elevated: the
   presenter table on the left, all eight podiums in a gentle arc centre-right, the big MILDEW sign
   above the podiums, the lighting rig, carpet, flats. Nobody at the presenter table, podiums empty.
4. **`podium_row`** — closer three-quarter shot of the eight podiums from front-left, all eight screens
   visible (switched off, facing camera as much as possible).
5. **`podium_closeup`** — one podium, front-on, close-up, at contestant eye level, screen filling
   about a third of the width, podium edge lamp visible. Empty.
6. **`presenter_wide`** — a slightly wider two-shot angle of the presenter area from the side (about 30°
   to the right of camera 1), empty, same set.

### Nice to have

7. **`audience_clapping`** and **`audience_unimpressed`** — the studio audience seating (a few raked
   rows, late-90s ordinary people, cardigans and anoraks), lit dimly, for reaction cutaways.
   People are fine in these two. No recognisable real people.
8. **`floor_wrong_camera`** — a camera accidentally pointing at the studio floor: carpet, a gaffer-taped
   cable, the edge of a camera pedestal. Nothing else.
9. **`corridor`** and **`corridor_doorway`** — backstage service corridor: breeze-block walls painted
   institutional green to dado height, scuffed lino, one fluorescent tube, a fire door, and at the far
   end a dark open doorway. `corridor_doorway` is a closer view of that dark doorway. Empty.

## File naming

Name files exactly as above (e.g. `wide_master.png`) and zip them if possible. If something can't be
made consistent, send it anyway and say which.
