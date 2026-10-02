# Mildew — Claude Code Handoff Package

Repository: `Mildew`

This package is the authoritative product/design/implementation handoff for **Mildew**, a local-multiplayer adult party game presented as a forgotten late-1990s British TV game show that somehow still broadcasts.

## How to use this package

Copy the contents of this package into the root of the `Mildew` GitHub repository, preserving the folder structure. `CLAUDE.md` is intentionally placed at the root so Claude Code can treat it as the primary operating brief.

Then send Claude Code the text in `PROMPT_TO_CLAUDE_CODE.md`.

## Authority order

When documents appear to overlap, use this order:

1. `CLAUDE.md`
2. `docs/01_NON_NEGOTIABLES.md`
3. `docs/12_DECISION_LEDGER.md`
4. The relevant detailed subsystem/game document
5. Existing repo implementation, provided it does not contradict the above

Later user instructions override this package only when explicitly given.

## Package contents

- `CLAUDE.md` — master brief Claude Code should read first.
- `PROMPT_TO_CLAUDE_CODE.md` — kickoff prompt to paste into Claude Code.
- `docs/00_PRODUCT_VISION.md` — product identity, audience experience, core loop.
- `docs/01_NON_NEGOTIABLES.md` — locked creative and technical rules.
- `docs/02_BROADCAST_WORLD_AND_TONE.md` — Graham, Announcer, studio, crew, rooms, humour, sinister layer.
- `docs/03_DIRECTOR_SYSTEM.md` — procedural episode direction, moods, pressure, complicity, interference, incidents, punishment, favourites/grudges.
- `docs/04_GAME_SPECS.md` — launch 6+2 game roster, rules, variants, low-player adaptations.
- `docs/05_SCORING_AND_SESSION_FLOW.md` — scoring, Rot, episode structure, finals, awards, timing.
- `docs/06_NETWORKING_AND_PLATFORM_ARCHITECTURE.md` — Android TV host, LAN phone controllers, reconnects, portability/Xbox contingency.
- `docs/07_CONTENT_SYSTEM_AND_SCHEMAS.md` — data-driven content model, factual sourcing, quality states, familiarity tiers.
- `docs/08_ART_AUDIO_ASSET_BIBLE.md` — 4:3 broadcast look, Graham presentation, fake adverts, audio, camera grammar.
- `docs/09_PERSISTENCE_PROFILES_AND_SAVE.md` — profiles, local memory, installation seed, room/event progression, migration/reset.
- `docs/10_DEBUG_TESTING_AND_TOOLING.md` — fake players, Director debug, content browser, logs, automated testing.
- `docs/11_BUILD_CHECKPOINTS.md` — required checkpoint order; every checkpoint ends in a playable APK.
- `docs/12_DECISION_LEDGER.md` — reconciliation record of the user’s decisions so they are not silently lost.
- `docs/13_SAFETY_BOUNDARIES_AND_NEVER_DO.md` — hard boundaries for fictional interference and device behaviour.
- `docs/14_ACCEPTANCE_CRITERIA.md` — proof-of-concept success definition and release-readiness gates.
- `config/design_constants.json` — initial machine-readable design constants; values may be tuned only within the design rules.
- `schemas/*.json` — starter schemas for data-driven content and incidents.
- `templates/*.md` — repo progress/status/reporting templates.

## Design intent in one paragraph

Mildew is not “Jackbox but rude,” and it is not a horror game with party-game mechanics. It is a genuinely fun, adult, local multiplayer party pack that looks and behaves like a cheap British game show from roughly 1997–1999. Gross biology, inappropriate humour, absurd social games, drawing, deduction and cooperative puzzles are the primary entertainment. Underneath that, the broadcast occasionally behaves incorrectly: private controller messages vanish before players can verify them, cameras cut to recurring backstage rooms, production audio leaks through, Graham forms petty opinions about contestants, the Announcer occasionally resists him, and very rare incidents imply something deeply wrong with the production. The show does not explain itself. It moves on.
