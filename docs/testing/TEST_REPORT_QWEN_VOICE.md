# Qwen voice pipeline — 2026-10-03

Scope: Graham's production pipeline, reconciled with game branch `claude/cp3-factual` at `8099b13`.

## Verified

- `./mildew voice test`: **17 tests passed**. Includes real FFmpeg/Vorbis output, name mapping,
  unchanged-cache reuse without inference/network, changed-source/take invalidation, corrupt-cache
  detection, failed-generation preservation, approval/demotion, legacy index preservation,
  pronunciation boundaries, line schema/path validation, resumable/verified download contract,
  unlocked-voice refusal, voice-profile truncation/identity-only refusal, idempotent collection,
  non-Graham/variable exclusion and all current game's indexed subtitle bindings.
- Native C runner `ef339be58a778b062e1c14382347964552eae007`: built with GCC/OpenBLAS on x86-64 Linux;
  `--help` succeeds. `voice setup --no-model` source checkout/build/help path succeeds.
- Pinned official VoiceDesign model downloaded; every model/tokenizer file verified against
  committed SHA-256 or Git blob SHA-1 metadata.
- **Real Qwen inference**, not a test tone: `correct_01`, instructed pleased Graham VoiceDesign.
  Raw output: 24 kHz mono PCM16, 2.0s. Peak 0.51251, RMS -24.06 dBFS, leading silence 0.019s,
  trailing silence 0.194s. Passed QA. Processed OGG: 2.25s including protective tail.
  Total load/generation/conversion: 15.61s. Engine inference reported RTF 6.59 on this container.
  These timings are not a phone benchmark or real-time runtime performance claim.
- 260 fixed Graham game lines collected and wired; 24 existing semantic/name ids preserved.
- `.gdignore`, export exclusions and gitignore keep source/models/cache out of the APK/repository.

## Full native profile path

**Passed with genuine Qwen models:** VoiceDesign audition → Base reference extraction
→ 25,216,751-byte `.qvoice` with 2048-dimensional embedding and 25 ICL reference frames
→ CustomVoice `--icl-only --instruct` pleased and disappointed takes → QA/OGG export
→ local Godot index → fully cached repeat build → approval. Tested in an isolated output
project under the ignored working directory; the actual game's clips remain missing until
the user chooses/locks Graham and builds them. No test voice has been shipped or approved.

The native profile's 2048-dimensional embedding was checked against the real runner output;
the initial overly strict 1024-dimensional check was corrected before publication.
Nine existing factory/sync tests also passed. All 12 existing game dialogue packs were compared
to the current upstream baseline: text, categories, moods and other data are unchanged;
only fixed Graham audio bindings were added.

## Unverified / remaining gates

- Actual phone: Termux package installation, ARM/Bionic compilation, inference RAM, speed and thermals.
- Human listening: British accent, voice identity consistency, pronunciation, omitted/duplicated words,
  intended emotion and suitability for Graham. Numerical audio QA cannot judge these.
- Official Qwen guarantees: community graft + instruction is experimental, unlike the official separate
  Base/VoiceDesign/CustomVoice model APIs. No production guarantee is inferred from a successful CLI run.
- No new GDScript implementation in this change. The full Godot/LAN/APK suite was not rerun because
  this environment has no Godot executable; current JSON subtitle/index binding contracts were checked.
- Arbitrary runtime name/score TTS and a new Android TV APK are outside this production-tool update.
