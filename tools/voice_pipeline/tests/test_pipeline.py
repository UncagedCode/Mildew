"""Contract and failure tests. Synthetic audio exists only in temporary test directories."""
import json
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pipeline as p
import native as n


def tone(path, seconds=1, silent=False, clipped=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = []
    for i in range(int(seconds * 24000)):
        sample = 0 if silent else (32767 if clipped else int(9000 * math.sin(i * 2 * math.pi * 300 / 24000)))
        frames.append(struct.pack("<h", sample))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(24000)
        out.writeframes(b"".join(frames))


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.home = Path(self.temp.name) / "local"
        self.env = patch.dict(os.environ, {"MILDEW_VOICE_HOME": str(self.home)})
        self.env.start()
        self.rp = patch.object(p, "REPO", self.repo)
        self.rn = patch.object(n, "REPO", self.repo)
        self.rp.start()
        self.rn.start()
        original = Path(__file__).resolve().parents[3]
        (self.repo / "voice").mkdir(parents=True)
        for name in ("graham_profile.json", "performances.json", "pronunciation.json", "models.lock.json"):
            (self.repo / "voice" / name).write_bytes((original / "voice" / name).read_bytes())
        (self.repo / "tools/graham_factory").mkdir(parents=True)
        self.manifest = self.repo / "tools/graham_factory/manifest.json"
        self.manifest.write_text(json.dumps({"lines": [
            {"id": "name_aaron", "mood": "name", "text": "Aaron."},
            {"id": "correct_01", "mood": "pleased", "text": "That is correct. Well done."}]}))
        self.home.mkdir()
        (self.home / "graham.qvoice").write_bytes(b"test-only-profile")
        n.atomic_json(self.home / "locked_voice.json", {"voice_sha256": n.digest(self.home / "graham.qvoice")})

    def tearDown(self):
        self.rp.stop()
        self.rn.stop()
        self.env.stop()
        self.temp.cleanup()

    def fake_run(self, args, log=None, timeout=None):
        if args[0] == "test-runner":
            tone(Path(args[args.index("-o") + 1]))
        else:
            self.original_run(args, log, timeout)

    def render(self, line, take=1):
        self.original_run = n.run
        with patch.object(n, "binary", return_value=Path("test-runner")), \
             patch.object(n, "model_path", return_value=self.home), \
             patch.object(n, "run", side_effect=self.fake_run):
            return p.generate(line, take)

    def test_end_to_end_real_ffmpeg_ogg_name_mapping_and_cached_rebuild(self):
        line = p.lines(["name_aaron"])[0]
        path = self.render(line)
        p.publish(line, 1)
        index = p.read(self.repo / "config/graham_voice_index.json")
        self.assertEqual(index["names"], {"aaron": "name_aaron"})
        entry = index["clips"]["name_aaron"]
        self.assertEqual(entry["status"], "development")
        self.assertTrue((self.repo / entry["path"][6:]).exists())
        self.assertGreater(entry["duration"], 1.1)
        with patch.object(n, "run", side_effect=AssertionError("cache must not launch inference")):
            self.assertEqual(p.generate(line, 1), path)

    def test_changed_text_performance_profile_reference_and_take_invalidate_cache(self):
        line = p.lines()[1]
        original = p.fingerprint(line, 1)
        self.assertNotEqual(original, p.fingerprint({**line, "text": "Different."}, 1))
        self.assertNotEqual(original, p.fingerprint({**line, "performance": "angry"}, 1))
        self.assertNotEqual(original, p.fingerprint(line, 2))
        profile = p.configs()[0]
        profile["temperature"] = 0.7
        n.atomic_json(self.repo / "voice/graham_profile.json", profile)
        self.assertNotEqual(original, p.fingerprint(line, 1))
        (self.home / "graham.qvoice").write_bytes(b"changed")
        self.assertTrue(p.lock_info(False)["unlocked"])

    def test_corrupt_cache_is_not_reused(self):
        line = p.lines()[1]
        path = self.render(line)
        (path / "clip.ogg").write_bytes(b"corrupt")
        self.assertFalse(p.cached(path, p.fingerprint(line, 1)))

    def test_failed_generation_preserves_existing_asset_and_index(self):
        line = p.lines()[1]
        self.render(line)
        p.publish(line, 1)
        before = (self.repo / "config/graham_voice_index.json").read_bytes()
        with patch.object(n, "binary", return_value=Path("test-runner")), \
             patch.object(n, "model_path", return_value=self.home), \
             patch.object(n, "run", side_effect=RuntimeError("failed generation")):
            with self.assertRaises(RuntimeError):
                p.generate(line, 2)
        self.assertEqual(before, (self.repo / "config/graham_voice_index.json").read_bytes())

    def test_approval_survives_identical_build_and_new_take_demotes(self):
        line = p.lines()[1]
        self.render(line)
        p.publish(line, 1)
        self.assertEqual(p.main(["approve", "correct_01", "1"]), 0)
        p.publish(line, 1)
        self.assertEqual(p.read(self.repo / "config/graham_voice_index.json")["clips"]["correct_01"]["status"], "approved")
        self.render(line, 2)
        p.publish(line, 2)
        self.assertEqual(p.read(self.repo / "config/graham_voice_index.json")["clips"]["correct_01"]["status"], "development")

    def test_pipeline_preserves_unrelated_legacy_index_entries(self):
        n.atomic_json(self.repo / "config/graham_voice_index.json", {"version": 1, "names": {},
                      "clips": {"old": {"path": "res://old.mp3", "status": "approved"}}})
        line = p.lines()[1]
        self.render(line)
        p.publish(line, 1)
        self.assertEqual(p.read(self.repo / "config/graham_voice_index.json")["clips"]["old"]["status"], "approved")

    def test_qa_rejects_silence_clipping_and_duration_cap(self):
        profile = p.configs()[0]
        path = self.home / "qa.wav"
        for kwargs in ({"silent": True}, {"clipped": True}, {"seconds": 20}):
            tone(path, **kwargs)
            with self.assertRaises(ValueError):
                p.wav_stats(path, profile)

    def test_pronunciation_changes_spoken_form_only_and_respects_word_boundary(self):
        self.assertEqual(p.speech("Mildew, Graham, Mildewed.", {"Mildew": "Mill dew", "Graham": "Gray um"}),
                         "Mill dew, Gray um, Mildewed.")

    def test_unknown_id_style_duplicate_and_path_traversal_are_rejected(self):
        with self.assertRaises(ValueError):
            p.lines(["unknown"])
        for entries in ([{"id": "../escape", "text": "Hi"}],
                        [{"id": "x", "text": "Hi", "performance": "unknown"}],
                        [{"id": "x", "text": "Hi"}, {"id": "x", "text": "Hi"}],
                        [{"id": "x", "text": "Hello {name}"}]):
            self.manifest.write_text(json.dumps({"lines": entries}))
            with self.assertRaises(ValueError):
                p.lines()

    def test_plan_and_cached_build_need_no_model_and_no_network(self):
        line = p.lines()[1]
        self.render(line)
        with patch.object(n, "download", side_effect=AssertionError("no download")), \
             patch.object(n, "binary", side_effect=AssertionError("no inference")):
            p.main(["plan", "correct_01"])
            p.build([line])

    def test_model_blob_integrity_including_git_sha1(self):
        path = self.home / "blob"
        path.write_bytes(b"abc")
        sha1 = __import__("hashlib").sha1(b"blob 3\0abc").hexdigest()
        self.assertTrue(n.verified(path, {"size": 3, "git_sha1": sha1}))
        self.assertFalse(n.verified(path, {"size": 2, "git_sha1": sha1}))
        self.assertFalse(n.verified(path, {"size": 3, "sha256": "wrong"}))

    def test_download_resumes_part_verifies_and_skips_complete_file(self):
        import hashlib
        blob = b"test-model-content"
        spec = {"repo": "Qwen/test", "revision": "pinned", "kind": "base",
                "files": [{"path": "model.safetensors", "size": len(blob), "sha256": hashlib.sha256(blob).hexdigest()}]}
        dest = self.home / "models/base"
        dest.mkdir(parents=True)
        (dest / "model.safetensors.part").write_bytes(blob[:5])
        def fake_curl(args):
            self.assertIn("--continue-at", args)
            Path(args[args.index("--output") + 1]).write_bytes(blob)
        with patch.object(n, "models", return_value={"base": spec}), patch.object(n, "run", side_effect=fake_curl) as run:
            n.download("base")
            n.download("base")
            self.assertEqual(run.call_count, 1)
            self.assertEqual(n.model_path("base"), dest)

    def test_unlocked_build_cannot_silently_produce_different_presenters(self):
        (self.home / "graham.qvoice").unlink()
        with self.assertRaises(RuntimeError):
            p.build(p.lines())

    def test_source_directories_excluded_from_game_export(self):
        original = Path(__file__).resolve().parents[3]
        self.assertTrue((original / "voice/.gdignore").exists())
        self.assertIn("voice/*", (original / "export_presets.cfg").read_text())

    def test_all_real_game_audio_bindings_have_matching_index_subtitles(self):
        original = Path(__file__).resolve().parents[3]
        index = p.read(original / "config/graham_voice_index.json")["clips"]
        count = 0
        for path in (original / "content/graham/lines").glob("*.json"):
            for item in p.read(path).get("items", []):
                if "audio" not in item:
                    continue
                ids = item["audio"] if isinstance(item["audio"], list) else [item["audio"]]
                self.assertTrue(all(lid in index for lid in ids), item["id"])
                self.assertEqual(item["text"], " ".join(index[lid]["text"] for lid in ids), item["id"])
                self.assertEqual(item.get("speaker", p.read(path).get("speaker", "graham")), "graham")
                count += 1
        self.assertGreaterEqual(count, 240)

    def test_voice_lock_rejects_identity_only_or_truncated_profiles(self):
        path = self.home / "bad.qvoice"
        for blob in (b"bad", b"QVCE" + struct.pack("<II", 3, 1024),
                     b"QVCE" + struct.pack("<II", 3, 1024) + bytes(4096) + struct.pack("<II", 0, 0)):
            path.write_bytes(blob)
            with self.assertRaises(RuntimeError):
                p.validate_qvoice(path)

    def test_collect_is_idempotent_preserves_legacy_skips_variables_and_tracks_edit(self):
        path = self.repo / "content/graham/lines/game.json"
        data = {"items": [
            {"id": "g.a", "text": "Fixed line.", "category": "intro"},
            {"id": "g.b", "text": "Hello {name}.", "category": "intro"},
            {"id": "g.c", "text": "Legacy.", "category": "intro", "audio": "correct_01"},
            {"id": "f.floor", "text": "Graham, you're on.", "category": "floor", "speaker": "floor"}]}
        n.atomic_json(path, data)
        p.collect()
        self.assertEqual(p.read(path)["items"][0]["audio"], "qwen.g.a")
        self.assertNotIn("audio", p.read(path)["items"][1])
        self.assertEqual(p.read(path)["items"][2]["audio"], "correct_01")
        self.assertNotIn("audio", p.read(path)["items"][3])
        p.collect()
        self.assertEqual(len(p.read(self.repo / "dialogue/graham/game_static.json")["lines"]), 1)
        data = p.read(path)
        data["items"][0]["text"] = "Now {variable}."
        n.atomic_json(path, data)
        p.collect()
        self.assertNotIn("audio", p.read(path)["items"][0])
        self.assertEqual(len(p.read(self.repo / "dialogue/graham/game_static.json")["lines"]), 0)


if __name__ == "__main__":
    unittest.main()
