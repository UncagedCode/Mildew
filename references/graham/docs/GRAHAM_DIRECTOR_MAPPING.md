# Graham Director-to-Visual Mapping

The Director should never manipulate filenames directly. It requests a semantic performance intent; GrahamPresenter resolves the best currently available state.

## Baseline mood mapping

| Director Graham mood | Preferred visual states | Current fallback |
|---|---|---|
| relaxed | `restrained_smile`, `neutral`, `reading_cards` | available |
| pleased | `restrained_smile`, `presenter_smile` | available |
| amused | `amused`, `restrained_smile` | `restrained_smile` |
| irritated | `irritated_hold`, `return_tense`, `reading_cards` | available |
| angry | `angry`, `irritated_hold` | `irritated_hold` |
| embarrassed | `disappointed`, `reading_cards` | `neutral` / `reading_cards` |
| rattled | `rattled`, `return_tense`, `neutral` | `return_tense` |

## Relationship flavour

Relationship state affects line choice and shot selection more than facial state.

### Favourite

Prefer:

- restrained smile;
- presenting gesture;
- longer eye contact;
- presenter smile for genuine praise.

Do not turn Graham into a constantly smiling friend.

### Irritant / disliked player

Prefer:

- neutral deadpan;
- reading cards immediately after their answer;
- return_tense;
- irritated hold only when justified.

### Humiliation target

The funniest visual response is often **neutral**, not angry. Graham's seriousness makes the humiliation funnier.

### Pet project

Use a mix of:

- restrained encouragement;
- disappointed fallback;
- overlarge presenter smile for patronising celebration when they finally succeed.

## Pressure interaction

Pressure changes shot duration and recovery, not just state selection.

### Low pressure

- normal 1–4 sec shots;
- easy return to restrained smile;
- more presenting gestures.

### Medium pressure

- more reading-card pauses;
- occasional neutral holds;
- slightly longer off-camera looks.

### High pressure

- fewer broad smiles;
- more return_tense / neutral;
- hard cut to adverts/graphics instead of cheerful recovery;
- irritability may bleed into next line.

## Important restraint

Do not map every numeric mood change to an immediate visible face swap. Graham should often remain visually stable while his dialogue or timing changes. Visible emotional changes are stronger when sparse.
