# Claude Code Integration Instructions

This pack is an implementation update to the existing Mildew design specification.

## Production constraint

The current budget is extremely limited. The project must therefore treat large-scale AI-generated FMV as **optional future polish**, not a build dependency.

## Required behaviour

1. Use the final clean Graham reference as the canonical visual/performance source.
2. Implement the presenter with semantic visual states and swappable assets.
3. Use full-frame still plates first; do not wait for transparent character cutouts.
4. Use authentic broadcast editing to hide limited mouth animation.
5. Keep dynamic speech working even when Graham is off-screen.
6. Reserve the existing motion/video material for moments where motion adds real value.
7. Do not ask the user to purchase/generate additional video merely to progress a checkpoint.
8. Missing cosmetic states must fall back to existing states.
9. Keep the presenter system portable to future better stills, alpha puppets or FMV.
10. Treat the accidental BBC-style bug as removed non-canon material.

## Recommended repository location

If the Mildew repo already has an art/reference structure, adapt to it without duplicating folders.

Otherwise place this pack under:

```text
reference/graham/
```

Runtime assets that are actually used by the game may then be copied/imported into the normal Godot asset tree, e.g.:

```text
game/assets/graham/
```

Keep reference videos out of the packaged Android release unless the runtime explicitly uses them.

## Checkpoint 1 expectation

The first real Android TV vertical slice should already demonstrate:

- canonical Graham identity;
- at least neutral, restrained smile, presenting, reading cards and irritated states;
- a simple state transition driven by the Director;
- one line of dynamic speech that begins on Graham and continues over a graphic;
- a scoreboard/question cutaway that makes the still-driven presenter feel like a real broadcast;
- no dependence on additional paid AI generation.

## Implementation order

1. Import canonical stills.
2. Create semantic state map.
3. Build `GrahamPresenter` scene.
4. Create debug gallery.
5. Add broadcast-plate micro-motion.
6. Add Director -> Graham state interface.
7. Add dynamic speech cutaway flow.
8. Benchmark optional motion excerpt playback.
9. Add fallbacks for missing states.
10. Document exact status in project progress files.

## Change control

Do not silently reinterpret Graham as:

- a cartoon;
- a 3D avatar;
- a horror monster;
- a modern streamer/presenter;
- a generic still talking head.

If technical constraints require a material change to the presenter approach, bring the change suggestion to the user first, consistent with the main Mildew change-control rules.
