#!/usr/bin/env python3
"""Phone-local Graham voice production; no paid API or runtime model dependency."""
from __future__ import annotations

import argparse
import array
import fcntl
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time
import wave

import native

REPO = native.REPO
VERSION = 1
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$")


def read(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def configs():
    return (read(REPO / "voice/graham_profile.json"), read(REPO / "voice/performances.json"),
            read(REPO / "voice/pronunciation.json"))


def lines(ids=None):
    paths = [REPO / "tools/graham_factory/manifest.json"]
    paths += sorted((REPO / "dialogue/graham").glob("*.json"))
    found = {}
    _, styles, _ = configs()
    for path in paths:
        for line in read(path)["lines"]:
            lid = line.get("id", "")
            if not ID_RE.fullmatch(lid) or lid in found:
                raise ValueError(f"unsafe or duplicate line id: {lid!r} in {path}")
            if not isinstance(line.get("text"), str) or not line["text"].strip():
                raise ValueError(f"{lid}: text required")
            if len(line["text"]) > 500 or re.search(r"[{}\[\]]", line["text"]):
                raise ValueError(f"{lid}: use short resolved text, without variables or emotion tags")
            mood = line.get("performance", line.get("mood", "presenter"))
            if mood not in styles:
                raise ValueError(f"{lid}: unknown performance {mood!r}")
            takes = line.get("takes", 1)
            if isinstance(takes, bool) or not isinstance(takes, int) or not 1 <= takes <= 8:
                raise ValueError(f"{lid}: takes must be 1..8")
            found[lid] = {**line, "performance": mood, "takes": takes}
    if ids:
        unknown = set(ids) - found.keys()
        if unknown:
            raise ValueError("unknown ids: " + ", ".join(sorted(unknown)))
        return [found[i] for i in ids]
    return list(found.values())


def speech(text, pronunciation):
    for word, spoken in sorted(pronunciation.items(), key=lambda x: -len(x[0])):
        if not word or not isinstance(spoken, str) or not spoken.strip():
            raise ValueError("pronunciation entries require nonempty strings")
        text = re.sub(r"(?<!\w)" + re.escape(word) + r"(?!\w)", lambda _: spoken, text)
    return text


def lock_info(required=True):
    meta = read(native.home() / "locked_voice.json", {})
    voice = native.home() / "graham.qvoice"
    if not meta or not voice.exists() or native.digest(voice) != meta.get("voice_sha256"):
        if required:
            raise RuntimeError("Graham voice not locked. Audition first, then run ./mildew voice lock <raw.wav> --transcript <text-file>")
        return {"unlocked": True}
    return meta


def fingerprint(line, take, design=False):
    profile, styles, pronunciation = configs()
    info = {"pipeline": VERSION, "line": line, "take": take, "profile": profile,
            "performance": styles[line["performance"]], "pronunciation": pronunciation,
            "native_revision": native.NATIVE_REV, "models": native.models(),
            "pipeline_code": native.digest(Path(__file__)), "adapter_code": native.digest(Path(native.__file__)),
            "voice": {"design": True} if design else lock_info(False)}
    return hashlib.sha256(json.dumps(info, sort_keys=True).encode()).hexdigest()


def cache_path(line, take, design=False):
    return native.home() / ("auditions" if design else "cache") / line["id"] / fingerprint(line, take, design)[:24]


def wav_stats(path: Path, profile):
    with wave.open(str(path), "rb") as w:
        if w.getsampwidth() != 2 or w.getnchannels() != 1 or w.getcomptype() != "NONE":
            raise ValueError("runner must produce mono PCM16 WAV")
        rate = w.getframerate()
        samples = array.array("h", w.readframes(w.getnframes()))
        if sys.byteorder != "little":
            samples.byteswap()
    if not samples or rate < 8000:
        raise ValueError("empty/invalid audio")
    duration = len(samples) / rate
    peak = max(abs(x) for x in samples) / 32768
    rms = math.sqrt(sum((x / 32768) ** 2 for x in samples) / len(samples))
    db = 20 * math.log10(max(rms, 1e-12))
    active = [i for i, x in enumerate(samples) if abs(x) > 164]  # -46 dBFS
    lead = active[0] / rate if active else duration
    tail = (len(samples) - active[-1] - 1) / rate if active else duration
    qa = profile["qa"]
    errors = []
    if not qa["min_seconds"] <= duration <= min(qa["max_seconds"], profile["max_seconds"] + 0.5):
        errors.append(f"duration {duration:.2f}s outside allowed range")
    if db < -55:
        errors.append("silent or unusually quiet audio")
    if sum(abs(x) >= 32760 for x in samples) / len(samples) > 0.002:
        errors.append("possible clipping")
    if lead > qa["max_leading_silence"] or tail > qa["max_trailing_silence"]:
        errors.append("excessive leading/trailing silence")
    if duration >= profile["max_seconds"] - 0.25:
        errors.append("generation reached duration cap; possible cut-off")
    if errors:
        raise ValueError("; ".join(errors))
    return {"duration": round(duration, 4), "sample_rate": rate, "peak": round(peak, 5),
            "rms_db": round(db, 2), "leading_silence": round(lead, 3), "trailing_silence": round(tail, 3)}


def postprocess(raw: Path, out: Path, profile):
    p = profile["postprocess"]
    # Graham bus already supplies broadcast EQ/compression. Avoid treating clips twice.
    # Keep the complete waveform; no silence trimming that can cut short names.
    filt = (f"loudnorm=I={p['loudness_lufs']}:TP={p['peak_db']}:LRA=7,"
            f"apad=pad_dur={p['tail_seconds']}")
    temp = out.with_suffix(".tmp.ogg")
    native.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(raw), "-af", filt,
                "-ac", "1", "-ar", "24000", "-c:a", "libvorbis", "-q:a", "5", str(temp)])
    probe = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                     "-of", "csv=p=0", str(temp)], text=True)
    duration = float(probe.strip())
    if not math.isfinite(duration) or duration < profile["qa"]["min_seconds"]:
        raise ValueError("invalid processed output")
    temp.replace(out)
    return duration


def cached(path: Path, expected: str):
    meta = read(path / "take.json", {})
    raw, audio = path / "raw.wav", path / "clip.ogg"
    return bool(meta.get("fingerprint") == expected and raw.exists() and audio.exists()
                and native.digest(raw) == meta.get("raw_sha256")
                and native.digest(audio) == meta.get("audio_sha256"))


def generate(line, take, design=False):
    path = cache_path(line, take, design)
    fp = fingerprint(line, take, design)
    if cached(path, fp):
        print(f"cached {line['id']} take {take}", flush=True)
        return path
    profile, styles, pronunciation = configs()
    kind = "design" if design else "custom"
    runner, model = native.binary(), native.model_path(kind)
    voice = [] if design else ["--load-voice", str(native.home() / "graham.qvoice"), "--icl-only"]
    if not design:
        lock_info()
    instruct = profile["description"] + " " + styles[line["performance"]]["prompt"]
    seed = profile["seed"] + int(hashlib.sha256(line["id"].encode()).hexdigest()[:7], 16) + take
    args = [str(runner), "-d", str(model), "--text", speech(line["text"], pronunciation),
            "--language", profile["language"], "--instruct", instruct, "--seed", str(seed),
            "--temperature", str(profile["temperature"]), "--threads", str(profile["threads"]),
            "--max-duration", str(profile["max_seconds"]), "--max-tokens", "512", *voice]
    if design:
        args.append("--voice-design")
    if profile["quantization"] not in ("int8", "int4", "bf16"):
        raise ValueError("quantization must be int8, int4 or bf16")
    if profile["quantization"] != "bf16":
        args.append("--" + profile["quantization"])
    path.mkdir(parents=True, exist_ok=True)
    raw = path / "raw.wav"
    partial = path / "raw.partial.wav"
    print(f"generating {line['id']} take {take}; {line['performance']}", flush=True)
    started = time.monotonic()
    native.run(args + ["-o", str(partial)], path / "generation.log", timeout=3600)
    stats = wav_stats(partial, profile)
    partial.replace(raw)
    duration = postprocess(raw, path / "clip.ogg", profile)
    native.atomic_json(path / "take.json", {"fingerprint": fp, "id": line["id"], "take": take,
                       "text": line["text"], "performance": line["performance"], "design": design,
                       "raw_sha256": native.digest(raw), "audio_sha256": native.digest(path / "clip.ogg"),
                       "stats": stats, "duration": duration, "generation_seconds": round(time.monotonic() - started, 2)})
    print(f"  ready: {path / 'clip.ogg'}", flush=True)
    return path


def publish(line, take):
    path = cache_path(line, take)
    fp = fingerprint(line, take)
    if not cached(path, fp):
        raise RuntimeError(f"{line['id']} take {take} missing or stale; run voice build {line['id']}")
    index_path = REPO / "config/graham_voice_index.json"
    index = read(index_path, {"version": 1, "clips": {}, "names": {}})
    old = index["clips"].get(line["id"], {})
    dest = REPO / "assets/audio/graham/qwen" / (line["id"] + ".ogg")
    dest.parent.mkdir(parents=True, exist_ok=True)
    temp = dest.with_suffix(".tmp.ogg")
    shutil.copyfile(path / "clip.ogg", temp)
    temp.replace(dest)
    sha = native.digest(dest)
    status = "approved" if old.get("status") == "approved" and old.get("source_fingerprint") == fp and old.get("sha256") == sha else "development"
    meta = read(path / "take.json")
    index["clips"][line["id"]] = {"path": "res://" + str(dest.relative_to(REPO)), "status": status,
                                    "text": line["text"], "mood": line["performance"], "sha": sha[:16],
                                    "sha256": sha, "bytes": dest.stat().st_size, "duration": meta["duration"],
                                    "source": "qwen3-tts-native", "source_fingerprint": fp, "take": take,
                                    "processing": "loudness_only; broadcast effects on Graham bus"}
    if line["id"].startswith("name_"):
        index["names"][line["id"][5:].lower()] = line["id"]
    index["_comment"] = "Local authored Graham audio. Qwen entries generated by ./mildew voice build. No runtime model or network."
    native.atomic_json(index_path, index)
    state = read(native.home() / "selection.json", {})
    state[line["id"]] = {"take": take, "fingerprint": fp}
    native.atomic_json(native.home() / "selection.json", state)


def build(selected, takes=None):
    lock_info()
    needs_model = any(not cached(cache_path(line, take), fingerprint(line, take))
                      for line in selected for take in range(1, (takes or line["takes"]) + 1))
    if needs_model:
        try:
            native.model_path("custom")
        except RuntimeError:
            native.download("custom")
    state = read(native.home() / "selection.json", {})
    failures = []
    for line in selected:
        try:
            for take in range(1, (takes or line["takes"]) + 1):
                generate(line, take)
            chosen = state.get(line["id"], {}).get("take", 1)
            # Keep a previously selected take even when the requested count is now smaller.
            generate(line, chosen)
            publish(line, chosen)
        except (RuntimeError, ValueError, subprocess.SubprocessError) as e:
            failures.append(line["id"])
            print(f"FAILED {line['id']}: {e}", flush=True)
    if failures:
        raise RuntimeError(f"{len(failures)} failed: {', '.join(failures)}. Successful clips saved; rerun to resume.")


def lock_voice(audio: Path, transcript: Path):
    text = transcript.read_text(encoding="utf-8").strip()
    if not text or len(text) > 600:
        raise ValueError("reference transcript required (exact words in reference, <=600 characters)")
    profile, _, _ = configs()
    source = audio.resolve()
    dest = native.home() / "reference.wav"
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Convert, never silently cut the reference or change the supplied transcript.
    temp = dest.with_suffix(".tmp.wav")
    native.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(source), "-ac", "1", "-ar", "24000",
                "-c:a", "pcm_s16le", str(temp)])
    stats = wav_stats(temp, {**profile, "max_seconds": 30,
                           "qa": {**profile["qa"], "min_seconds": 2.0, "max_seconds": 30}})
    voice = native.home() / "graham.partial.qvoice"
    runner = native.binary()
    try:
        model = native.model_path("base")
    except RuntimeError:
        model = native.download("base")
    args = [str(runner), "-d", str(model), "--ref-audio", str(temp),
            "--ref-text", text, "--save-voice", str(voice), "--voice-name", "Graham Mildew",
            "--language", "English", "--threads", str(profile["threads"])]
    native.run(args, native.home() / "logs/lock.log", timeout=3600)
    validate_qvoice(voice)
    voice.replace(native.home() / "graham.qvoice")
    temp.replace(dest)
    native.atomic_json(native.home() / "locked_voice.json", {"voice_sha256": native.digest(native.home() / "graham.qvoice"),
                       "reference_sha256": native.digest(dest), "transcript": text, "stats": stats,
                       "native_revision": native.NATIVE_REV, "base_revision": native.models()["base"]["revision"],
                       "mode": "experimental_native_icl_graft"})
    print("Graham reference locked. Next: ./mildew voice build correct_01 wrong_01", flush=True)


def validate_qvoice(voice: Path):
    blob = voice.read_bytes()
    if len(blob) < 20 or blob[:4] != b"QVCE":
        raise RuntimeError("invalid voice profile; see lock.log")
    dim = struct.unpack_from("<I", blob, 8)[0]
    if dim != 2048:
        raise RuntimeError("unexpected voice embedding dimensions")
    offset = 12 + dim * 4
    if len(blob) < offset + 4:
        raise RuntimeError("truncated voice profile")
    ntext = struct.unpack_from("<I", blob, offset)[0]
    if len(blob) < offset + 8 + ntext:
        raise RuntimeError("truncated voice transcript")
    nframes = struct.unpack_from("<I", blob, offset + 4 + ntext)[0]
    if nframes == 0 or len(blob) < offset + 8 + ntext + nframes * 16 * 4:
        raise RuntimeError("runner could not encode reference prosody; refusing an identity-only fallback")


def doctor():
    target = native.home()
    target.mkdir(parents=True, exist_ok=True)
    print(f"Voice files: {target}\nFree disk: {shutil.disk_usage(target).free / 1024**3:.1f} GiB")
    if Path("/proc/meminfo").exists():
        mem = Path("/proc/meminfo").read_text()
        for key in ("MemTotal", "MemAvailable", "SwapTotal"):
            value = re.search(rf"^{key}:\s+(\d+)", mem, re.M)
            if value:
                print(f"{key}: {int(value[1]) / 1024**2:.1f} GiB")
    print("1.7B generation may need several GiB of RAM beyond the download size; Android can kill it.")
    print("First run only a short audition. No phone timing or memory guarantee is assumed.")
    for cmd in ("ffmpeg", "ffprobe", "curl", "make", "git"):
        print(f"{cmd}: {shutil.which(cmd) or 'missing'}")
    for kind in native.models():
        try:
            print(f"{kind}: {native.model_path(kind)}")
        except RuntimeError:
            print(f"{kind}: not installed")
    print("voice: " + ("not locked" if lock_info(False).get("unlocked") else "locked (native graft, audition for identity and acting)"))


def collect():
    """Wire fixed game lines to stable Qwen ids; keep variable/silent/legacy lines intact."""
    pack = REPO / "dialogue/graham/game_static.json"
    previous = {x["id"]: x for x in read(pack, {"lines": []})["lines"]}
    index_path = REPO / "config/graham_voice_index.json"
    index = read(index_path, {"version": 1, "clips": {}, "names": {}})
    collected, changes = [], []
    _, styles, _ = configs()
    aliases = {"relaxed": "presenter", "amused": "teasing", "disappointed": "disappointed",
               "irritated": "irritated", "angry": "angry", "rattled": "rattled"}
    for path in sorted((REPO / "content/graham/lines").glob("*.json")):
        data = read(path)
        changed = False
        for item in data.get("items", []):
            lid = "qwen." + item.get("id", "")
            audio = item.get("audio")
            text = item.get("text", "")
            if audio and audio != lid:
                continue
            if (item.get("speaker", data.get("speaker", "graham")) != "graham" or item.get("silent")
                    or not item.get("enabled", True) or not text.strip() or re.search(r"[{}\[\]]", text)):
                if audio == lid:
                    item.pop("audio")
                    changed = True
                continue
            if not ID_RE.fullmatch(lid) or len(text) > 500:
                raise ValueError(f"cannot collect {lid}: unsafe id or too much text")
            moods = item.get("moods", [])
            mood = previous.get(lid, {}).get("performance", aliases.get(moods[0], "presenter") if moods else "presenter")
            if mood not in styles:
                raise ValueError(f"unknown collected mood: {mood}")
            collected.append({"id": lid, "text": text, "performance": mood,
                              "source_file": str(path.relative_to(REPO)), "game_line_id": item["id"]})
            if audio != lid:
                item["audio"] = lid
                changed = True
            entry = index["clips"].get(lid, {})
            if not entry or entry.get("text") != text:
                # Never play a recording of outdated text. Successful build replaces this entry.
                index["clips"][lid] = {"path": "", "status": "missing", "text": text,
                                        "mood": mood, "sha": "", "bytes": 0}
        if changed:
            changes.append((path, data))
    if len({x["id"] for x in collected}) != len(collected):
        raise ValueError("duplicate game line id in collected packs")
    obsolete = previous.keys() - {x["id"] for x in collected}
    for lid in obsolete:
        if index["clips"].get(lid, {}).get("status") == "missing":
            index["clips"].pop(lid, None)
    for path, data in changes:
        native.atomic_json(path, data)
    native.atomic_json(pack, {"version": 1, "notes": "Generated by ./mildew voice collect. Fixed lines only; performance prompts may be edited here.", "lines": collected})
    native.atomic_json(index_path, index)
    print(f"Collected {len(collected)} fixed game lines. Variables/silent lines and existing recordings retained.")


def parser():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("setup").add_argument("--no-model", action="store_true")
    sub.add_parser("download").add_argument("kind", choices=list(native.models()))
    for cmd in ("doctor", "report", "test", "collect"):
        sub.add_parser(cmd)
    for cmd in ("plan", "build", "audition"):
        p = sub.add_parser(cmd)
        p.add_argument("ids", nargs="*")
        p.add_argument("--takes", type=int, choices=range(1, 9))
    p = sub.add_parser("lock")
    p.add_argument("audio", help="raw reference WAV path, or audition line id")
    p.add_argument("--transcript", type=Path, help="exact reference transcript (required for an external WAV)")
    p.add_argument("--take", type=int, choices=range(1, 9), default=1)
    for cmd in ("select", "approve"):
        p = sub.add_parser(cmd)
        p.add_argument("id")
        p.add_argument("take", type=int, choices=range(1, 9))
    p = sub.add_parser("preview")
    p.add_argument("id")
    p.add_argument("--take", type=int, choices=range(1, 9), default=1)
    p.add_argument("--audition", action="store_true")
    return ap


def main(argv=None):
    a = parser().parse_args(argv)
    if a.command == "test":
        return subprocess.call([sys.executable, "-m", "unittest", "discover", "-s", str(Path(__file__).parent / "tests"), "-v"])
    native.home().mkdir(parents=True, exist_ok=True)
    # Kernel advisory lock releases on crashes/Termux interruptions, unlike a stale pid file.
    with (native.home() / ".pipeline.lock").open("a") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("another voice command is running; wait for it to finish")
        if a.command == "setup":
            native.setup(a.no_model)
        elif a.command == "download":
            native.download(a.kind)
        elif a.command == "doctor":
            doctor()
        elif a.command == "collect":
            collect()
        elif a.command == "lock":
            if a.transcript:
                lock_voice(Path(a.audio).expanduser(), a.transcript.expanduser())
            else:
                line = lines([a.audio])[0]
                path = cache_path(line, a.take, True)
                if not cached(path, fingerprint(line, a.take, True)):
                    raise RuntimeError("audition not found/current; generate it first, or supply --transcript for an external WAV")
                lock_voice(path / "raw.wav", path / "transcript.txt")
        elif a.command in ("plan", "build", "audition"):
            selected = lines(a.ids)
            if a.command == "plan":
                count = 0
                for line in selected:
                    for take in range(1, (a.takes or line["takes"]) + 1):
                        hit = cached(cache_path(line, take), fingerprint(line, take))
                        count += not hit
                        print(f"{'cached' if hit else 'generate'} {line['id']} take {take}: {line['text']}")
                print(f"{count} takes need generation. No model loaded, no network call.")
            elif a.command == "audition":
                if not a.ids:
                    raise ValueError("audition needs explicit line ids to avoid an accidental full-library run")
                for line in selected:
                    for take in range(1, (a.takes or line["takes"]) + 1):
                        path = generate(line, take, True)
                        (path / "transcript.txt").write_text(speech(line["text"], configs()[2]) + "\n")
            else:
                build(selected, a.takes)
        elif a.command in ("select", "approve"):
            line = lines([a.id])[0]
            publish(line, a.take)
            if a.command == "approve":
                path = REPO / "config/graham_voice_index.json"
                index = read(path)
                index["clips"][a.id]["status"] = "approved"
                native.atomic_json(path, index)
            print(f"{a.command}: {a.id} take {a.take}")
        elif a.command == "preview":
            line = lines([a.id])[0]
            path = cache_path(line, a.take, a.audition)
            if not cached(path, fingerprint(line, a.take, a.audition)):
                raise RuntimeError("take not found or stale; generate it first")
            print(path / "clip.ogg", flush=True)
            player = shutil.which("termux-media-player")
            if player:
                native.run([player, "play", str(path / "clip.ogg")], timeout=60)
            elif shutil.which("termux-open"):
                native.run(["termux-open", "--view", "--content-type", "audio/ogg", str(path / "clip.ogg")], timeout=60)
        elif a.command == "report":
            index = read(REPO / "config/graham_voice_index.json", {"clips": {}})
            for line in lines():
                clip = index["clips"].get(line["id"], {})
                print(f"{line['id']}: {clip.get('status', 'missing')} {clip.get('path', '')}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"VOICE ERROR: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Interrupted. Finished clips and partial downloads kept; rerun to resume.", file=sys.stderr)
        sys.exit(130)
