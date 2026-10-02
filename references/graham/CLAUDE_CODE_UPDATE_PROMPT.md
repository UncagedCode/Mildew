# Prompt to send Claude Code with this pack

I have added a new Graham reference/asset pack to the Mildew repository. Read its `README.md` and every file in its `docs/` directory before changing Graham presentation.

This pack reflects an important production constraint: my current budget is extremely limited, so Mildew must NOT depend on generating a large FMV library.

Treat `reference/video/graham_canonical_reference_clean_4x3.mp4` as the primary canonical visual/performance reference for Graham. The final generated clip defines his face, age, hair, suit, cue-card handling, overall presenter manner and the subtle irritated-recovery performance. Earlier generations are supplementary only.

Implement Graham initially as a low-budget broadcast-compositing system using the curated still states, authentic camera editing, graphics cutaways, audio, scoreboards, questions and analogue treatment. Dynamic speech should often begin on Graham and continue while the broadcast cuts to other material, rather than trying to keep fake lip-sync visible for long lines.

Important:
- Do not block a checkpoint waiting for new AI-generated video.
- Do not silently redesign Graham.
- Do not reintroduce the accidental BBC-style branding; Mildew has no confirmed real-world broadcaster.
- Implement semantic Graham states with fallbacks so higher-quality stills, alpha puppets or FMV can replace individual states later without changing Director/game logic.
- Add a Graham debug/gallery view so every available state, fallback and transition can be tested quickly.
- Benchmark any runtime motion asset before relying on video decoding on Android TV. The supplied MP4 motion excerpts are references first; short frame sequences are preferable if native playback is awkward.
- Preserve the main Mildew rule that the broadcast remains readable and authentically late-1990s rather than becoming generic analogue horror.

Integrate this into the current checkpoint rather than starting a separate prototype. Update the repo's detailed progress/decision/test tracking with exactly what was imported, implemented and still missing.
