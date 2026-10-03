# Graham's Qwen voice pipeline

Run this in your Mildew checkout in **Termux's home directory**, rather than shared Android storage.
It builds a pinned native C Qwen3-TTS runner, downloads models onto the phone, generates speech locally,
checks and converts takes, and updates the game's existing `GrahamVoice` index. No paid service,
second computer, Python packages, GitHub Actions or runtime internet is required.

## First run

From your existing checkout, bring in the pipeline branch:

```bash
cd ~/Mildew
git fetch origin
git switch feature/qwen-voice-pipeline
./mildew voice setup
./mildew voice audition welcome_01 --takes 3
```

`setup` installs the required Termux packages, compiles the native runner and downloads the first model.
The audition command prints the paths of three `clip.ogg` files. Listen with
`./mildew voice preview welcome_01 --take 1 --audition` (repeat for takes 2 and 3).
Choose the Graham voice you like, then run (for take 2):

```bash
./mildew voice lock welcome_01 --take 2
./mildew voice build correct_01 wrong_01
```

Locking downloads the Base model and makes a reusable reference profile from the chosen **raw** audition,
with its exact transcript. The first build downloads the CustomVoice model, then tests a pleased and
disappointed delivery with the same profile. Listen before committing to a long batch.

If you already have a Graham voice recording you prefer, skip the designed auditions:

```bash
./mildew voice setup --no-model
./mildew voice lock /path/to/graham.wav --transcript /path/to/exact-words.txt
./mildew voice build correct_01 wrong_01
```

The existing `references/graham/reference/audio/graham_final_voice_performance_reference.wav`
is also available as a performance reference. Supply an accurate transcript if using it;
the pipeline does not invent a transcript or automatically choose a stretch of the recording.

## Normal use

After the small test sounds right:

```bash
./mildew voice build
```

The initial library has **284 lines**: the existing 24 semantic/name clips plus 260 fixed Graham
game lines. Future runs regenerate only changed text, voice, performance, pronunciation, model,
pipeline or generation settings. Each completed take is checkpointed. If Android stops Termux,
rerun the same command. Partial model downloads resume; incomplete takes restart.

Useful smaller commands:

```bash
./mildew voice plan
./mildew voice build name_aaron name_elijah name_grace name_josh name_donna
./mildew voice build welcome_01 --takes 3
./mildew voice select welcome_01 3
./mildew voice approve welcome_01 3
./mildew voice report
./mildew voice doctor
./mildew voice test
```

`approve` means you have listened and accepted that take. Structural/audio QA alone cannot judge
pronunciation, duplicated words, acting or character identity. An unchanged rebuild keeps approval;
changed sources/takes return to `development`. There is no automatic quality-based selection of
an acting performance. Until selected otherwise, take 1 is the gameplay take.

`plan` never loads a model or contacts a server. Subsequent fully cached builds also work offline.
Setup/downloads need the internet. Generation never sends dialogue or reference audio to a service.

## Listening on the phone

Use the same command for each take:

```bash
./mildew voice preview welcome_01 --take 1 --audition
```

`preview` prints the path and uses Termux:API's media player when available, otherwise
Termux's `termux-open` to launch your normal audio app. If external playback is blocked by
your Termux settings, open the listed clip through a file manager's Termux storage picker.
Playback integration is optional; generation does not require it.

## Editing dialogue and performance

- Existing stable clips: `tools/graham_factory/manifest.json`. Keep its text aligned with subtitles.
- Fixed game lines: edit `content/graham/lines/*.json`, then run `./mildew voice collect`.
- Additional production-only lines: `dialogue/graham/*.json`, using the shape below.
- Voice description/generation settings: `voice/graham_profile.json`.
- Performance instructions: `voice/performances.json`.
- Pronunciation overrides: `voice/pronunciation.json`. Only the spoken form changes; subtitles stay intact.

```json
{"lines": [{"id": "graham_wrong_004", "text": "Oh dear. No, that's not right at all.", "performance": "forced_smile", "takes": 3}]}
```

`collect` is idempotent and links fixed game lines to stable audio ids. It preserves manual
performance choices in its generated pack. It does not collect the Announcer, floor manager,
silent beats or lines containing runtime placeholders such as `{name}` or `{score}`.
The five known names are pre-rendered; arbitrary runtime names/scores still need the separate
offline speech work described by the game specification. This production pipeline does not claim
to implement that runtime system.

## Phone requirements and model stages

Each pinned 1.7B checkpoint is around **4.5 GB downloaded**; all three together are around **13.6 GB**,
plus native source/cache/audio. You can put the working tree elsewhere in Termux-owned storage with
`MILDEW_VOICE_HOME=/absolute/path`. Do not use shared storage for executable native binaries.

The pipeline runs stages sequentially. INT8 is the default; this quantizes during model loading,
so the download remains the original BF16 checkpoint. Available settings: `int8`, experimental
`int4`, and `bf16`. `threads` defaults to 4 to avoid oversubscribing the phone.

**Storage capacity is separate from RAM.** The native runner has been built/tested on Linux here;
Termux/ARM inference time, memory use and thermal behaviour require a short run on the actual phone.
Android may kill a process under memory pressure. The cache makes resuming safe; it does not remove
the model's RAM requirements. Run `doctor` to report the phone's environment if generation fails.

## Qwen capabilities and voice consistency

The official models split capabilities:

| Stage | Checkpoint | Purpose |
|---|---|---|
| Audition | 1.7B VoiceDesign | Voice description + performance instruction; independently generated voice candidates |
| Lock | 1.7B Base | Extract a reference/ICL profile from one accepted candidate or existing reference |
| Build | 1.7B CustomVoice | Native runner's `--load-voice ... --icl-only --instruct` graft path |

The **cloned-profile + instruction combination is a community native-runner extension**, not an
official Qwen guarantee. It is promising but experimental. `build` refuses to generate unlocked
voices, and locking refuses an identity-only fallback without reference prosody. This keeps one
reference across lines, but listening is still required to confirm that the result sounds like the
Graham you selected, with the desired emotion. A hash/seed cannot guarantee a perfect performance.

## Game output and QA

Selected takes are written to `assets/audio/graham/qwen/<id>.ogg`. The existing
`config/graham_voice_index.json` receives their subtitle, mood, duration, hash and approval state.
Existing recordings/index entries are preserved. The game's playback calls remain unchanged:

```gdscript
GrahamVoice.say("correct_01")
GrahamVoice.say_name("Aaron")
```

FFmpeg normalises loudness to -19 LUFS with a -2 dBTP target and adds a short protective tail.
No silence trimming is used, so short names are not cut at the beginning/end. Broadcast EQ and
compression already live on Godot's `Graham` audio bus; clips are not treated twice.
QA rejects empty/invalid WAVs, unreasonable durations, very quiet audio, excessive silence,
significant clipping and takes hitting the duration limit. Failed output is never published.

Models, native source, references and audition/cache files stay under git-ignored `voice/.local/`.
Only selected game assets and the index are committed. `voice/` has `.gdignore` and export exclusion;
models cannot inflate the APK. There is no pretend-speech production backend.

## Provenance

- [Official Qwen project](https://github.com/QwenLM/Qwen3-TTS): models use Apache-2.0.
- [Native C runner](https://github.com/gabriele-mastrapasqua/qwen3-tts): MIT, pinned in `native.py`.
- Exact model commits, sizes and hashes: `voice/models.lock.json`.

The native runner is pinned rather than silently following upstream changes. Update its revision
and model locks deliberately, then rerun the regression tests and re-audition the voice.
