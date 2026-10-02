import json
import pathlib
import tempfile
import unittest
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import generate as gf


class GrahamFactoryTests(unittest.TestCase):
    def config(self):
        return gf.Config(api_key="x", voice_id="graham", hard_cap=8000)

    def test_render_line(self):
        styles = {"presenter": "[warm host]"}
        self.assertEqual(gf.render_line({"id":"a","mood":"presenter","text":"Hello."}, styles), "[warm host]\nHello.")

    def test_budget_blocks_over_hard_cap(self):
        snap = gf.budget_snapshot({"tier":"free","character_count":7900,"character_limit":10000}, self.config(), projected=101)
        self.assertFalse(snap["would_fit"])
        self.assertEqual(snap["remaining"], 100)

    def test_budget_uses_lower_account_limit(self):
        cfg = self.config()
        cfg.hard_cap = 12000
        snap = gf.budget_snapshot({"tier":"free","character_count":100,"character_limit":10000}, cfg, projected=9901)
        self.assertEqual(snap["effective_limit"], 10000)
        self.assertFalse(snap["would_fit"])

    def test_fingerprint_changes_with_mood_render(self):
        cfg = self.config()
        item = {"id":"x","text":"Hello"}
        a = gf.fingerprint(item, "[warm]\nHello", cfg)
        b = gf.fingerprint(item, "[angry]\nHello", cfg)
        self.assertNotEqual(a,b)

    def test_manifest_rejects_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "m.json"
            path.write_text(json.dumps({"lines":[{"id":"x","text":"a"},{"id":"x","text":"b"}]}), encoding="utf-8")
            with self.assertRaises(gf.GrahamFactoryError):
                gf.ordered_manifest(path)

    def test_safe_filename(self):
        self.assertEqual(gf.safe_filename("Question Six / 01"), "question_six___01")


if __name__ == "__main__":
    unittest.main()
