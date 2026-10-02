# Claude integration note — Graham Factory

Graham's release voice is **pre-rendered authored audio**, not Android TTS and not live ElevenLabs.

## Current status

The Graham Factory pipeline is working and merged on `main`.

- The initial 19-line development library has been generated and is useful for implementation/testing, but several emotional states drift too far in pitch/register. Do **not** treat all 19 as final approved release takes yet.
- The required player-name bank currently contains: `Aaron`, `Elijah`, `Grace`, `Josh`, `Donna`.
- Name-bank v2 generation uses bare names with sentence-final punctuation and no performance tag. This fixes the abrupt file-end problem from v1 and keeps generation cost very low.
- Do not spend more ElevenLabs credits during integration unless explicitly requested. The game must never depend on cloud speech at runtime.

## Source of truth

- `manifest.json`: semantic dialogue IDs and spoken text.
- `styles.json`: production-only performance directions.
- approved generated audio: copied into the Godot asset tree after human approval.

## Do not

- put an ElevenLabs API key in Godot, an APK, a web controller, source control, CI logs, or client JavaScript;
- make gameplay wait for a cloud TTS request;
- hard-code ElevenLabs request IDs into game logic;
- construct release dialogue directly from `styles.json`;
- regenerate the whole Graham library while implementing game-side playback.

## Game-side interface

Implement a semantic local-audio service, for example:

```gdscript
graham_voice.say("correct_01")
```

and for names:

```gdscript
graham_voice.say_name("Aaron")
```

Name lookup should map case-insensitively onto the stable IDs:

- `Aaron` -> `name_aaron`
- `Elijah` -> `name_elijah`
- `Grace` -> `name_grace`
- `Josh` -> `name_josh`
- `Donna` -> `name_donna`

Later intent-based calls may use something like:

```gdscript
graham_voice.say_intent("wrong_answer", {"mood": "irritated"})
```

The game maps requests onto approved local audio. If an approved clip is missing in development, Android/system TTS may be used only as an obvious developer fallback and must never silently become the release path.

## Immediate implementation tasks for Claude

1. Create `GrahamVoiceService` as a Godot autoload/service for local authored audio playback.
2. Add an ID -> asset-path index that can be populated without changing gameplay code.
3. Add `say(id)` and `say_name(name)` APIs.
4. Make missing clips fail gracefully in development with a clear log warning.
5. Keep the system ready for optional common-number clips later, but do not build cloud/runtime synthesis.
6. Route Graham through a dedicated audio bus so broadcast EQ/compression/VHS treatment can be applied globally.
7. Add a small developer Voice Browser that lists semantic IDs and lets a developer audition local clips.
8. Keep all Graham playback asynchronous/non-blocking so game flow can continue or await completion explicitly where needed.

## Production workflow

1. Add/modify a line in `manifest.json`.
2. Run `python generate.py plan`.
3. Run `python generate.py missing <id>`.
4. Review the generated audio.
5. If bad, `python generate.py regenerate <id>`; no other line is regenerated.
6. Copy the approved asset into the Godot authored audio directory.
7. Update the game's local dialogue index.

The generated working directory is intentionally ignored by Git until a take is approved.
