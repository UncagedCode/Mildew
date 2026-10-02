import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import sync_godot as sg


class SyncGodotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = pathlib.Path(self.tmp.name)
        self.repo, self.src = t / "repo", t / "src"
        self.src.mkdir()
        (self.repo / "config").mkdir(parents=True)
        man = t / "manifest.json"
        man.write_text(json.dumps({"lines": [
            {"id": "name_aaron", "mood": "name", "text": "Aaron."},
            {"id": "correct_01", "mood": "pleased", "text": "That is correct. Well done."},
            {"id": "wrong_01", "mood": "disappointed", "text": "No."}]}))
        self.saved = (sg.REPO, sg.MANIFEST, sg.INDEX, sg.ASSET_DIR)
        sg.REPO, sg.MANIFEST = self.repo, man
        sg.INDEX = self.repo / "config" / "graham_voice_index.json"
        sg.ASSET_DIR = self.repo / "assets" / "audio" / "graham"

    def tearDown(self):
        sg.REPO, sg.MANIFEST, sg.INDEX, sg.ASSET_DIR = self.saved
        self.tmp.cleanup()

    def index(self):
        return json.loads(sg.INDEX.read_text())

    def test_imports_as_development_and_maps_names(self):
        (self.src / "name_aaron.mp3").write_bytes(b"ID3fake-aaron")
        (self.src / "correct_01.mp3").write_bytes(b"ID3fake-correct")
        sg.build(self.src, [], [], False)
        idx = self.index()
        self.assertEqual(idx["names"], {"aaron": "name_aaron"})
        self.assertEqual(idx["clips"]["correct_01"]["status"], "development")
        self.assertEqual(idx["clips"]["correct_01"]["path"], "res://assets/audio/graham/correct_01.mp3")
        self.assertEqual(idx["clips"]["wrong_01"]["status"], "missing")
        self.assertTrue((sg.ASSET_DIR / "name_aaron.mp3").exists())

    def test_approval_and_new_take_demotes(self):
        (self.src / "correct_01.mp3").write_bytes(b"take1")
        sg.build(self.src, [], [], False)
        sg.build(self.src, ["correct_01"], [], False)
        self.assertEqual(self.index()["clips"]["correct_01"]["status"], "approved")
        sg.build(self.src, [], [], False)
        self.assertEqual(self.index()["clips"]["correct_01"]["status"], "approved", "unchanged file keeps approval")
        (self.src / "correct_01.mp3").write_bytes(b"take2")
        sg.build(self.src, [], [], False)
        self.assertEqual(self.index()["clips"]["correct_01"]["status"], "development", "new take needs re-approval")

    def test_cannot_approve_missing_and_check_changes_nothing(self):
        r = sg.build(self.src, ["wrong_01"], [], False)
        self.assertEqual(self.index()["clips"]["wrong_01"]["status"], "missing")
        self.assertTrue(any("cannot approve wrong_01" in x for x in r["report"]))
        before = sg.INDEX.read_text()
        (self.src / "wrong_01.mp3").write_bytes(b"x")
        sg.build(self.src, [], [], True)
        self.assertEqual(sg.INDEX.read_text(), before)
        self.assertFalse((sg.ASSET_DIR / "wrong_01.mp3").exists())


if __name__ == "__main__":
    unittest.main()
