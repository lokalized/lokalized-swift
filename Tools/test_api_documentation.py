#!/usr/bin/env python3
"""Reference scope, documentation coverage, and release-label negative controls.

Copyright 2026 Revetware LLC. Licensed under the Apache License, Version 2.0.
"""
import unittest
from pathlib import Path
import tempfile
from build_api_documentation import coverage_for, edition_for, symbol_graphs, validate_release_source


def graph(documented=True, module="Lokalized", member=False):
    symbol = {"identifier": {"precise": "s:test"}, "pathComponents": ["Example"], "names": {"title": "Example"}}
    if member:
        symbol["pathComponents"].append("method()")
    if documented:
        symbol["docComment"] = {"lines": [{"text": "A useful public API summary."}]}
    return {"module": {"name": module}, "symbols": [symbol]}


class ReferenceTests(unittest.TestCase):
    def test_reported_symbol_graph_directory_supports_compiler_layouts(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary)
            for layout in ("arm64-apple-macosx/symbolgraph", "out/symbolgraph"):
                directory = scratch / layout
                directory.mkdir(parents=True)
                for name in ("Lokalized.symbols.json", "Lokalized@Foundation.symbols.json",
                             "LokalizedConformanceSupport.symbols.json"):
                    (directory / name).write_text("{}")
                selected = symbol_graphs(scratch, f"Build complete!\nFiles written to {directory}\n")
                self.assertEqual({path.name for path in selected},
                                 {"Lokalized.symbols.json", "Lokalized@Foundation.symbols.json"})

    def test_symbol_graph_directory_cannot_escape_scratch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scratch = root / "build"
            scratch.mkdir()
            outside = root / "other"
            outside.mkdir()
            with self.assertRaisesRegex(ValueError, "inside the documentation scratch"):
                symbol_graphs(scratch, f"Files written to {outside}\n")

    def test_missing_or_ambiguous_symbol_graph_directory_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary)
            for output in ("Build complete!", f"Files written to {scratch}\nFiles written to {scratch}\n"):
                with self.assertRaisesRegex(ValueError, "one symbol-graph output directory"):
                    symbol_graphs(scratch, output)

    def test_development_is_not_a_release(self):
        self.assertEqual(edition_for(None), "development")
        self.assertEqual(edition_for("1.0.0-rc.1"), "1.0.0-rc.1")
        with self.assertRaisesRegex(ValueError, "clean checkout"):
            validate_release_source("1.0.0", True, ["1.0.0"])
        with self.assertRaisesRegex(ValueError, "release tag"):
            validate_release_source("1.0.0", False, ["1.0.1"])
        validate_release_source("1.0.0", False, ["v1.0.0"])

    def test_versions_are_safe_directory_names(self):
        for value in ("../outside", "v1.0.0", "01.0.0", "1.0", "1.0.0+build", "1.0.0-01", "1.0.0\n"):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "semantic version"):
                edition_for(value)

    def test_conformance_modules_cannot_enter_the_public_reference(self):
        with self.assertRaisesRegex(ValueError, "only the Lokalized module"):
            coverage_for([graph(module="LokalizedConformanceSupport")])

    def test_empty_symbol_output_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "No public symbols"):
            coverage_for([])

    def test_missing_top_level_documentation_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "need documentation: Example"):
            coverage_for([graph(documented=False)])
        self.assertEqual(coverage_for([graph()])["documentedTopLevelDeclarations"], 1)

    def test_undocumented_members_are_reported_without_claiming_full_coverage(self):
        coverage = coverage_for([graph(documented=False, member=True)])
        self.assertEqual(coverage["documentedSymbols"], 0)
        self.assertEqual(coverage["undocumentedMembers"], ["Example/method()"])


if __name__ == "__main__":
    unittest.main()
