# Mildew — Graham Low-Budget Asset & Reference Pack

This pack turns the four Graham Mildew concept videos into a practical, low-cost production reference for the **Mildew** Godot project.

## Purpose

The project currently has a very limited production budget. Graham should therefore **not** depend on a large library of newly generated FMV. The intended first implementation is a broadcast-compositing illusion built from:

- curated still frames from the existing generated Graham footage;
- a few short motion excerpts cut from footage already generated;
- Godot camera cuts, scoreboards, questions, podiums, lower thirds and archive inserts;
- voice/audio continuing over non-Graham shots;
- restrained analogue/VHS processing;
- selective future FMV only where physical performance itself matters.

This is an intentional aesthetic direction, not a temporary programmer-art compromise. It should resemble a strange late-1990s TV programme / interactive CD-ROM hybrid.

## Canonical source

`reference/video/graham_canonical_reference_clean_4x3.mp4`

This is the **primary visual and performance reference**. It is the final user-selected Graham generation, converted to a 4:3 reference presentation and cleaned of the accidental BBC-style corner branding.

Earlier clips are supplementary only. They may supply useful gestures, but **must not override the final clip's face, age, styling, demeanour or performance tone**.

## Start here

1. Read `docs/GRAHAM_CANONICAL_REFERENCE.md`.
2. Review `assets/contact_sheets/graham_curated_states.jpg`.
3. Read `docs/GRAHAM_ASSET_INVENTORY.md` and `docs/GRAHAM_MISSING_ASSETS.md`.
4. Implement the presenter system according to `docs/GRAHAM_GODOT_IMPLEMENTATION.md`.
5. Follow `docs/GRAHAM_PERFORMANCE_AND_EDITING_RULES.md` whenever adding new Graham material.
6. Claude Code should read `docs/CLAUDE_CODE_INTEGRATION.md` before modifying Mildew.

## Non-canon artefact removed

The generated source videos accidentally displayed a BBC-style broadcaster bug/logo. **Mildew is not a BBC programme.** The bug has been removed from the curated assets and cleaned reference videos. Do not reintroduce BBC branding or any other real broadcaster branding.

## Budget rule

Do not block implementation on missing AI video. The still-driven presenter system must be capable of shipping a convincing proof of concept on its own.
