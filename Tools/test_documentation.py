#!/usr/bin/env python3
"""Offline admission controls for runnable consumer documentation."""
import unittest

from verify_documentation import DOCUMENTS, REMOTE, ROOT, extract


class DocumentationTests(unittest.TestCase):
    def setUp(self):
        self.text = (ROOT / "README.md").read_text()

    def test_authored_examples_preserve_code_resources_and_output(self):
        for document, identity, _, locales in DOCUMENTS:
            text = (ROOT / document).read_text()
            result = extract(text, identity, locales)
            self.assertNotIn(REMOTE, result["manifest"])
            self.assertEqual(set(result["catalogs"]), set(locales))
            self.assertIn("import Lokalized", result["source"])
            self.assertTrue(result["output"].endswith("\n"))
        catalogs = extract((ROOT / "Documentation/USAGE.md").read_text(), "catalogs", ("en", "fr"))
        # Preserve the decomposed escape in JSON, not a normalized decoded key.
        self.assertIn('"e\\u0301": "Decomposed key"', catalogs["catalogs"]["en"])
        self.assertIn('"é": "Composed key"', catalogs["catalogs"]["en"])

    def test_duplicate_manifest_is_refused(self):
        start = self.text.index("<!-- lokalized-example: quickstart manifest -->")
        end = self.text.index("\n```", self.text.index("```swift", start)) + len("\n```")
        with self.assertRaises(ValueError):
            extract(self.text + "\n" + self.text[start:end], "quickstart", ())

    def test_missing_output_is_refused(self):
        with self.assertRaises(ValueError):
            extract(self.text.replace("<!-- lokalized-example: quickstart output -->", ""), "quickstart", ())

    def test_wrong_language_is_refused(self):
        with self.assertRaises(ValueError):
            extract(self.text.replace("```text\nHello, Ada!", "```swift\nHello, Ada!"), "quickstart", ())

    def test_unknown_identity_is_refused(self):
        with self.assertRaises(ValueError):
            extract(self.text.replace("quickstart source", "unknown source"), "quickstart", ())

    def test_truncated_fence_is_refused(self):
        start = self.text.index("<!-- lokalized-example: quickstart output -->")
        end = self.text.index("\n```", self.text.index("```text", start))
        with self.assertRaises(ValueError):
            extract(self.text[:end], "quickstart", ())

    def test_changed_dependency_requires_review(self):
        with self.assertRaises(ValueError):
            extract(self.text.replace('from: "1.0.0"', 'from: "2.0.0"'), "quickstart", ())


if __name__ == "__main__":
    unittest.main()
