# Claude integration note — Graham Factory

Graham's release voice is **pre-rendered authored audio**, not Android TTS and not live ElevenLabs.

## Source of truth

- `manifest.json`: semantic dialogue IDs and spoken text.
- `styles.json`: production-only performance directions.
- approved generated audio: copied into the Godot asset tree after human approval.

## Do not

- put an ElevenLabs API key in Godot, an APK, a web controller, source control, CI logs, or client JavaScript;
- make gameplay wait for a cloud TTS request;
- hard-code ElevenLabs request IDs into game logic;
- construct release dialogue directly from `styles.json`.

## Game-side interface

The intended game API remains semantic, for example:

```gdscript
graham_voice.say("correct_01")
```

or later:

```gdscript
graham_voice.say_intent("wrong_answer", {"mood": "irritated"})
```

The game maps that request onto approved local audio. If an approved clip is missing in development, Android/system TTS may be used only as an obvious developer fallback.

## Production workflow

1. Add/modify a line in `manifest.json`.
2. Run `python generate.py plan`.
3. Run `python generate.py missing <id>`.
4. Review the generated audio.
5. If bad, `python generate.py regenerate <id>`; no other line is regenerated.
6. Copy the approved asset into the Godot authored audio directory.
7. Update the game's local dialogue index.

The generated working directory is intentionally ignored by Git until a take is approved.
