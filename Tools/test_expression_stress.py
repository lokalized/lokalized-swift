#!/usr/bin/env python3
"""Offline admission checks for the expression differential recipe."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_expression_stress import Case, CLASS_MAP, generate, forms, normalize


class ExpressionStressRecipeTests(unittest.TestCase):
    def test_deterministic_two_seed_generation(self):
        first = generate(count=64)
        self.assertEqual([case.wire() for case in first], [case.wire() for case in generate(count=64)])
        self.assertNotEqual([case.wire() for case in first], [case.wire() for case in generate(seed=0xC4A5E117, count=64)])
        self.assertEqual(len({case.id for case in first}), len(first))

    def test_all_language_forms_and_exact_unicode_keys(self):
        inventory = forms()
        self.assertEqual(len(inventory), 61)
        cases = generate(count=64)
        self.assertEqual({case.source.removeprefix("x == ") for case in cases if case.family == "typed-form"}, set(inventory))
        distinct = next(case for case in cases if case.family == "unicode-distinct-keys")
        self.assertNotEqual(distinct.contexts[0]["é"], distinct.contexts[0]["e\u0301"])
        self.assertIn("e\u0301", distinct.source)

    def test_compiled_reuse_and_resolver_modes_are_present(self):
        cases = generate(count=64)
        self.assertTrue(any(len(case.contexts) >= 4 for case in cases))
        self.assertEqual({case.resolver for case in cases if case.family == "phonetic-callback"}, {"return", "throw"})
        self.assertEqual({case.family for case in cases if case.limits}, {"lowered-limit"})

    def test_serialized_fields_are_lossless(self):
        case = Case("id", "test", "é == 1 && e\u0301 == 2", ({"é": ["integer", "1"], "e\u0301": ["integer", "2"]},))
        self.assertEqual(len(case.wire().rstrip("\n").split("\t")), 6)
        self.assertIn("\t\t", case.wire())

    def test_swift_exception_map_is_explicit(self):
        self.assertIn("TranslationEvaluationError.expression", CLASS_MAP)
        self.assertEqual(normalize({"id": "a", "compile": [["ExpressionCompilationError", [65]]], "results": []})["compile"],
                         [["com.lokalized.ExpressionEvaluationException", [65]]])
        with self.assertRaisesRegex(ValueError, "unmapped refusal class"):
            normalize({"id": "a", "compile": [["SomeOtherError", [65]]], "results": []})
        with self.assertRaisesRegex(ValueError, "unmapped refusal class"):
            normalize({"id": "a", "compile": [["java.lang.RuntimeException", [65]]], "results": []})

    def test_error_and_callback_units_are_bounded(self):
        with self.assertRaisesRegex(ValueError, "invalid UTF-16"):
            normalize({"id": "a", "compile": [["ExpressionCompilationError", [65536]]], "results": []})
        with self.assertRaisesRegex(ValueError, "invalid resolver trace"):
            normalize({"id": "a", "compile": None, "results": [{"value": True, "calls": [[[65], [99999]]]}]})

    def test_invalid_generation_limits_fail_closed(self):
        for seed, count in [(0, 64), (1, 0), (1, 2001)]:
            with self.assertRaises(ValueError): generate(seed, count)


if __name__ == "__main__": unittest.main()
