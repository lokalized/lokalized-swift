#!/usr/bin/env python3
"""Offline controls for stress-input and comparison admission; no Java/Swift required."""
import copy
import unittest

from verify_parser_stress import Case, SEED, canonical, check_coverage, decode_observations, differences, generate, structural_positions


class ParserStressControls(unittest.TestCase):
    def setUp(self):
        self.case = Case("control", "json-edge", b'{"A":"x"}')
        self.java = {"id": "control", "status": "threw", "class": "com.lokalized.LocalizedStringLoadingException",
                     "value": [65, 0xD83D, 0xDE00], "warnings": [[66], [67]]}
        self.swift = {**copy.deepcopy(self.java), "class": "Lokalized.StringsParseError"}

    def decode(self, row, cases=None):
        return decode_observations(canonical(row) + b"\n", cases or [self.case])

    def testMalformedOrLostObservationFieldsAreRefused(self):
        for field in self.java:
            changed = copy.deepcopy(self.java)
            del changed[field]
            with self.subTest(field=field), self.assertRaises(ValueError): self.decode(changed)
        with self.assertRaises(ValueError): self.decode({**self.java, "unexaminedField": []})

    def testMissingReorderedAndDuplicateRowsAreRefused(self):
        with self.assertRaises(ValueError): decode_observations(b"", [self.case])
        with self.assertRaises(ValueError): self.decode({**self.java, "id": "wrong"})
        with self.assertRaises(ValueError):
            decode_observations((canonical(self.java) + b"\n") * 2, [self.case, Case("second", "json-edge", b"{}")])

    def testUnknownOutcomeAndLostRefusalClassAreRefused(self):
        for change in [{"status": "ignored"}, {"class": None}, {"value": None}, {"value": [True]}]:
            with self.subTest(change=change), self.assertRaises(ValueError): self.decode({**self.java, **change})
        with self.assertRaises(ValueError): self.decode({**self.java, "status": "returned"})

    def testWarningUnitsAreValidated(self):
        for warnings in [None, ["text"], [[True]], [[-1]], [[65536]]]:
            with self.subTest(warnings=warnings), self.assertRaises(ValueError): self.decode({**self.java, "warnings": warnings})

    def testErrorClassAndMessageAreActuallyCompared(self):
        self.assertEqual(differences(self.java, self.swift), [])
        self.assertEqual(differences(self.java, {**self.swift, "class": "OtherError"}), ["class"])
        self.assertEqual(differences(self.java, {**self.swift, "value": [65]}), ["value"])
        with self.assertRaises(ValueError): differences({**self.java, "class": "java.lang.RuntimeException"}, self.swift)

    def testWarningLossAndOrderAreActuallyCompared(self):
        for warnings in [[], [[67], [66]], [[66]]]:
            with self.subTest(warnings=warnings):
                self.assertEqual(differences(self.java, {**self.swift, "warnings": warnings}), ["warnings"])

    def testDecodedContentsAndExactUnicodeAreActuallyCompared(self):
        returned = {"id": "control", "status": "returned", "class": None,
                    "value": [[[233], [120], None, [], []], [[101, 769], [121], None, [], []]], "warnings": []}
        self.assertEqual(differences(returned, copy.deepcopy(returned)), [])
        changed = copy.deepcopy(returned)
        changed["value"][1][0] = [233]
        self.assertEqual(differences(returned, changed), ["value"])
        changed = copy.deepcopy(returned)
        changed["value"][0][1] = [121]
        self.assertEqual(differences(returned, changed), ["value"])

    def testDegenerateOracleCannotPass(self):
        cases = [Case(str(i), "json-edge", b"{}") for i in range(150)]
        rows = [{"id": str(i), "status": "returned", "class": None, "value": [], "warnings": []} for i in range(150)]
        with self.assertRaises(ValueError): check_coverage(cases, rows)

    def testKnownValidModelMustActuallyReturn(self):
        with self.assertRaises(ValueError): check_coverage([Case("control", "valid-model", b"{}")], [self.java])

    def testGeneratorIsReproducibleAndSeedSensitive(self):
        cases = generate(count=8)
        self.assertEqual(cases, generate(count=8))
        self.assertNotEqual(cases, generate(seed=SEED + 1, count=8))
        self.assertEqual(len({case.id for case in cases}), len(cases))
        self.assertTrue(all(len(case.data) < 16_384 for case in cases))
        for seed, count in [(0, 8), (1 << 64, 8), (SEED, 7), (SEED, 1001)]:
            with self.subTest(seed=seed, count=count), self.assertRaises(ValueError): generate(seed, count)

    def testStructuralMutationPreservesEscapesAndMultibyteStrings(self):
        data = b'{"x":"[,]\\\"\\uD83D\\uDE00"}'
        self.assertEqual([data[i] for i in structural_positions(data)], list(b"{:}"))


if __name__ == "__main__":
    unittest.main()
