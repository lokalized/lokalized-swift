#!/usr/bin/env python3
"""Offline admission tests for the locale-input differential recipe."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_locale_stress import Case, FIELDS, coverage, differences, generate
from generate_locale_unicode_tables import OUTPUT, SOURCE_SHA256, sha


class LocaleStressRecipeTests(unittest.TestCase):
    def test_two_seeds_are_deterministic_and_distinct(self):
        first = generate(count=32)
        self.assertEqual([row.wire() for row in first], [row.wire() for row in generate(count=32)])
        self.assertNotEqual([row.wire() for row in first], [row.wire() for row in generate(0x2C71A9E0D5F48B63, 32)])
        self.assertEqual(len({row.id for row in first}), len(first))

    def test_reference_edges_and_fuzz_families_are_present(self):
        rows = generate(count=32)
        self.assertTrue(any(row.text == "i-klingon" for row in rows))
        self.assertTrue(any(row.text == "en\u0000US" for row in rows))
        self.assertEqual({row.family for row in rows if row.family != "fixed-reference-edge" and row.family != "fixed-control-edge"},
                         {"composed-tag", "inserted-code-point", "deleted-code-point", "case-variant", "duplicate-extension", "private-variant"})

    def test_grapheme_sensitive_delimiter_and_kelvin_inputs(self):
        rows = generate(count=300)
        self.assertTrue(any(row.text.startswith("ji-") and "\u0301" in row.text for row in rows))
        self.assertTrue(any("Katn" in row.text for row in rows))

    def test_wire_preserves_controls_and_unicode(self):
        row = Case("case", "test", "ji-\u0301u\n")
        self.assertEqual(len(row.wire().rstrip("\n").split("\t")), 2)
        self.assertTrue(row.wire().isascii())

    def test_field_inventory_and_difference_detection(self):
        self.assertEqual(len(FIELDS), 21)
        left = {"id": "a", "values": [[65] for _ in FIELDS]}
        right = {"id": "a", "values": [[65] for _ in FIELDS]}
        self.assertIsNone(differences(Case("a", "test", "en"), left, right))
        right["values"][11] = [66]
        self.assertEqual(differences(Case("a", "test", "en"), left, right)["fields"][0]["field"], "canonicalRaw")

    def test_degenerate_coverage_fails_closed(self):
        rows = generate(count=32)
        observations = [{"id": case.id, "values": [[ord(c) for c in "true"] for _ in FIELDS]} for case in rows]
        with self.assertRaisesRegex(ValueError, "degenerate"):
            coverage(rows, observations)

    def test_invalid_generator_bounds_fail_closed(self):
        for seed, count in [(0, 32), (1, 0), (1, 2001)]:
            with self.assertRaises(ValueError): generate(seed, count)

    def test_generated_unicode_source_is_pinned(self):
        self.assertEqual(sha(OUTPUT.read_bytes()), SOURCE_SHA256)


if __name__ == "__main__": unittest.main()
