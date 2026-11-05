import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_l10n as g


def tokens(text):
    return [m.group() for m in g.KEEP.finditer(text)]


class PseudoTests(unittest.TestCase):
    def test_keeps_placeholders_for_every_key(self):
        data, _ = g.catalog()
        texts = [t for _, t in g.rows(data, {}, "en")] + [g.english_view(k) for k in g.view_keys()]
        self.assertTrue(texts)
        for text in texts:
            out = g.pseudo(text)
            self.assertTrue(out.startswith("[!! ") and out.endswith(" !!]"), text)
            self.assertEqual(tokens(out), tokens(text), text)
            self.assertEqual(g.placeholders(out), g.placeholders(text), text)
            self.assertEqual(g.specifiers(out), g.specifiers(text), text)
            self.assertEqual(out.count("\n"), text.count("\n"), text)

    def test_example(self):
        self.assertEqual(g.pseudo("Save {0} pages\n100%% of %1$@"), "[!! Šàvé {0} pàgéš\n100%% õf %1$@~~~~~ !!]")
        self.assertEqual(g.pseudo("a\\n b"), "[!! à\\n b~~ !!]")


if __name__ == "__main__":
    unittest.main()
