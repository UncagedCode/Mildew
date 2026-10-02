# Prompt to send Claude Code

You are taking over implementation of my GitHub repository **Mildew**.

I have added a complete design/implementation handoff package to the repository. Start by reading `CLAUDE.md` in full, then follow its required reading order and inspect the existing repository before making changes. Treat the handoff as the authoritative product specification. It contains the decisions from a long design process; do not re-ask questions that are already answered there.

Your job is to build Mildew as a checkpointed, recoverable project, starting with **Checkpoint 1** in `docs/11_BUILD_CHECKPOINTS.md` and progressing forward as far as you can without sacrificing correctness or the locked design.

Important working rules:

- Mildew is primarily an **Android TV Godot game**. One TV runs the main broadcast and 2–8 players join using phone browsers over the same local Wi-Fi. Ordinary multiplayer gameplay must work without internet.
- From the first build, make it look and feel as close to the intended late-1990s British Mildew broadcast as practical. Do not build a generic grey programmer UI and promise to style it later.
- Implement the Director early rather than bolting it on after the games.
- Every major checkpoint must end with a **buildable/installable playable APK** and updated tests/status documentation.
- Maintain detailed `PROGRESS.md`, `NEXT_BUILD.md`, `DECISIONS.md`, and test reports in the repository throughout the work so a later session can resume immediately.
- Do not silently change locked design decisions. If you believe a design change is genuinely necessary, document the original requirement, the technical/design problem, the proposed alternative and impact, and bring the suggestion to me **before** changing the product behaviour. Normal low-level implementation decisions can be made autonomously if they preserve the spec.
- Prefer vertical-slice quality over racing ahead with ugly placeholders. Temporary assets are fine, but they should already respect the Mildew art direction wherever practical.
- Use the content schemas/config structure from the package and keep questions, incidents, adverts, factual content and large libraries data-driven.
- Build developer tooling as specified: fake players, Director state/debug controls, content browser/validator, accelerated broadcast simulation and automated tests.
- Preserve host portability so Xbox Series X Developer Mode or another stronger host can be investigated later if Android TV hardware proves insufficient, but do not let that delay the Android TV proof of concept.

First, inspect the repository and reconcile it against the package. Then create/update the progress tracking files and begin **Checkpoint 1**. Work through the checkpoint autonomously. Do not stop after writing a plan: implement, test, build the APK if the environment allows it, and document exact status/remaining blockers before moving on.
