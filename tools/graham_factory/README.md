# Graham Factory

Local, free-first production tool for Graham Mildew's pre-rendered voice library.

It is intentionally **not** a runtime dependency of the game. ElevenLabs is used only while producing assets; Mildew ships and plays offline with generated audio files.

## Why this exists

Generating lines manually in the ElevenLabs web UI caused three problems:

1. too much copy/paste/download/rename work;
2. each independent generation could change Graham's delivery;
3. long generations occasionally duplicated words.

Graham Factory generates one short utterance per API request, then uses ElevenLabs request-stitching context to keep consecutive lines coherent. It caches outputs and refuses to cross a configurable monthly usage ceiling.

## Cost policy

The default hard cap is **8,000 characters of account usage per billing period**, below a 10,000-character free allowance. The tool checks `GET /v1/user/subscription` before a generation command and stops before the configured cap.

This is a guardrail, not a billing contract. Also set a credit quota on the ElevenLabs API key itself in the ElevenLabs dashboard. That server-side quota is the strongest protection against accidental spending.

No ElevenLabs call is made during gameplay.

## Termux setup

No Python packages are required.

```sh
cd tools/graham_factory
cp .env.example .env
nano .env
```

Fill in only:

```text
ELEVENLABS_API_KEY=...
GRAHAM_VOICE_ID=...
```

Do not send the API key to ChatGPT, Claude, GitHub, the Android app, or a browser client.

## Commands

Check account usage without generating audio:

```sh
python generate.py status
```

See exactly what would be generated and estimated characters:

```sh
python generate.py plan
```

Generate only missing/out-of-date lines:

```sh
python generate.py missing
```

Generate only particular lines:

```sh
python generate.py missing welcome_01 correct_01
```

Force a replacement take of one bad line:

```sh
python generate.py regenerate insult_pathetic_01
```

Show the local cache:

```sh
python generate.py report
```

## Dialogue workflow

Edit `manifest.json`, not the Python script. Each line needs:

```json
{"id": "correct_01", "mood": "pleased", "text": "That is correct. Well done."}
```

`styles.json` maps the semantic mood to an Eleven v4 square-bracket performance direction. This keeps prompt wording consistent and means dialogue authors never have to remember generation prompts.

The output filenames are derived from the stable IDs, for example:

```text
generated_audio/correct_01.mp3
```

## Request stitching

For each line, Graham Factory sends up to three previous ElevenLabs `request-id` values when available. If there is no usable prior request ID it supplies neighbouring text as context. This provides continuity without forcing many lines into a single error-prone audio generation.

## Caching

`.graham_state.json` records the exact voice settings, rendered text, output path, request ID, returned character cost, and generation timestamp. `missing` skips anything whose source/settings fingerprint is unchanged.

Changing the text, mood, voice, model, seed, or voice settings automatically invalidates the cached line.

## Output and game integration

`generated_audio/` is ignored by Git by default while voice production is still iterative. Once a take is approved, copy it into the game's authored audio tree and commit the approved asset there.

Godot should ask for semantic dialogue intents. Game logic must not know about ElevenLabs, API keys, or generation prompts.

## QA

The generator deliberately keeps utterances short to reduce v4 repetition glitches. If an output contains a doubled word, use `regenerate <id>`; the rest of the library remains untouched.

A future optional local transcription QA pass can be added using an offline Whisper implementation without consuming cloud credits.
