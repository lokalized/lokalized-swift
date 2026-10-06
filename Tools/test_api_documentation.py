#!/usr/bin/env python3
"""Reference scope, documentation coverage, and release-label negative controls.

Copyright 2026 Revetware LLC. Licensed under the Apache License, Version 2.0.
"""
import unittest
from unittest.mock import patch
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import json
from build_api_documentation import ROOT, compare_documentation_inputs, coverage_for, edition_for, extract_symbol_graphs, public_declarations, symbol_graphs, validate_release_source
from measure_package import source_sizes


def graph(documented=True, module="Lokalized", member=False):
    symbol = {"identifier": {"precise": "s:test"}, "pathComponents": ["Example"], "names": {"title": "Example"}}
    if member:
        symbol["pathComponents"].append("method()")
    if documented:
        symbol["docComment"] = {"lines": [{"text": "A useful public API summary."}]}
    return {"module": {"name": module}, "symbols": [symbol]}


class ReferenceTests(unittest.TestCase):
    def test_docc_catalogs_are_not_counted_as_runtime_resources(self):
        files = [{"path": "Sources/Lokalized/PrivacyInfo.xcprivacy", "bytes": 300, "sha256": "privacy"},
                 {"path": "Sources/Lokalized/Lokalized.docc/UsingLokalized.md", "bytes": 6000, "sha256": "guide"}]
        sizes = source_sizes(files)
        self.assertEqual(sizes["runtimeResourceBytes"], 300)
        self.assertEqual(sizes["runtimeResources"], files[:1])

    def test_ci_artifact_preserves_docc_routes_and_payloads(self):
        workflow = (ROOT / ".github/workflows/api-documentation.yml").read_text()
        commands = re.findall(r"^\s*run: ((?:env \S+ )?tar .+)$", workflow, re.MULTILINE)
        self.assertEqual(len(commands), 1, "The static site needs one archive step")
        upload = re.search(r"name: swift-api-reference\n\s+path: ([^\n]+)", workflow)
        self.assertIsNotNone(upload)
        uploaded_path = Path(upload.group(1))
        self.assertNotRegex(uploaded_path.name, r'[":<>|*?\r\n]')

        # These are real DocC route shapes rejected by direct artifact upload.
        contents = {
            "site/index.html": b"reference editions",
            "site/development/data/documentation/lokalized/animacy/!=(_:_:).json": b'{"title":"!=(_:_:)"}',
            "site/development/data/documentation/lokalized/exactdecimal/<(_:_:).json": b'{"title":"<(_:_:)"}',
            "site/development/documentation/lokalized/index.html": b"module page",
            "site/development/js/index.js": b"load the original symbol routes",
        }
        # AppleDouble's ._ prefix cannot be restored beside a 255-byte name.
        long_route = "site/development/data/documentation/lokalized/options/" + "init(" + "a" * 244 + ").json"
        contents[long_route] = b"long initializer route"
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            output = directory / ".build/api-documentation"
            for name, data in contents.items():
                path = output / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            if sys.platform == "darwin":
                subprocess.run(["xattr", "-w", "com.lokalized.reference-test", "macOS-only metadata",
                                str(output / long_route)], check=True)
            subprocess.run(shlex.split(commands[0]), cwd=directory, check=True)
            archive = directory / uploaded_path
            self.assertTrue(archive.is_file(), "The uploaded path must be the archive, not the site directory")
            extracted = directory / "extracted"
            extracted.mkdir()
            subprocess.run(["tar", "-xzf", str(archive), "-C", str(extracted)], check=True)
            self.assertEqual({path.relative_to(extracted).as_posix(): path.read_bytes()
                              for path in extracted.rglob("*") if path.is_file()}, contents)

    def test_only_public_library_graphs_are_selected(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for name in ("Lokalized.symbols.json", "Lokalized@Foundation.symbols.json",
                         "LokalizedConformanceSupport.symbols.json", "lokalized_swiftPackageTests.symbols.json"):
                (directory / name).write_text("{}")
            self.assertEqual({path.name for path in symbol_graphs(directory)},
                             {"Lokalized.symbols.json", "Lokalized@Foundation.symbols.json"})

    def test_extension_graphs_cannot_replace_missing_library_graph(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "Lokalized@Foundation.symbols.json").write_text("{}")
            with self.assertRaisesRegex(ValueError, "was not emitted"):
                symbol_graphs(directory)

    def test_extraction_builds_only_library_and_discards_stale_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "build").mkdir()
            (output / "build" / "stale.swiftmodule").write_text("old module")
            directory = output / "build" / "symbolgraphs"
            directory.mkdir()
            (directory / "Lokalized@OldModule.symbols.json").write_text("{}")

            def compile_library(command, env, cwd=ROOT):
                self.assertEqual(command[:3], ["xcrun", "swift", "build"])
                self.assertEqual(command[command.index("--target") + 1], "Lokalized")
                self.assertNotIn("--build-tests", command)
                self.assertEqual(command[command.index("-symbol-graph-minimum-access-level") + 2], "public")
                self.assertFalse((output / "build" / "stale.swiftmodule").exists())
                self.assertEqual(list(directory.iterdir()), [])
                (directory / "Lokalized.symbols.json").write_text("{}")

            with patch("build_api_documentation.run", side_effect=compile_library):
                self.assertEqual(extract_symbol_graphs(output, {}), [directory / "Lokalized.symbols.json"])

    def test_extraction_cannot_pass_using_a_previous_builds_graph(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            directory = output / "build" / "symbolgraphs"
            directory.mkdir(parents=True)
            (directory / "Lokalized.symbols.json").write_text("{}")
            with patch("build_api_documentation.run", return_value=""), self.assertRaisesRegex(ValueError, "was not emitted"):
                extract_symbol_graphs(output, {})

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

    def test_authored_members_need_prose_but_synthesized_members_are_separate(self):
        authored = graph(documented=False, member=True)
        authored["symbols"][0]["location"] = {"uri": "file:///project/Sources/Lokalized/API/Example.swift"}
        with self.assertRaisesRegex(ValueError, "Authored public declarations need documentation"):
            coverage_for([authored])
        authored["symbols"][0]["docComment"] = {"lines": [{"text": "Translates the requested key."}]}
        generated = graph(documented=False, member=True)
        generated["symbols"][0]["identifier"]["precise"] = "s:generated::SYNTHESIZED::Example"
        generated["symbols"][0]["location"] = authored["symbols"][0]["location"]
        coverage = coverage_for([authored, generated])
        self.assertEqual(coverage["authoredPublicSymbols"], 1)
        self.assertEqual(coverage["documentedAuthoredPublicSymbols"], 1)
        self.assertEqual(coverage["publicSymbols"], 2)

    def test_maintenance_notes_cannot_enter_public_comments(self):
        for text in ("Fixed BOOT-M0-17 in this slice.", "See DefaultStrings.java:2718.",
                     "Run the development conformance executable.", "TODO: document this method."):
            bad = graph()
            bad["symbols"][0]["docComment"]["lines"][0]["text"] = text
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, "Internal maintenance notes"):
                coverage_for([bad])

    def test_public_signature_comparison_ignores_prose_and_locations(self):
        first = graph()
        second = graph(documented=False)
        first["symbols"][0]["location"] = {"uri": "file:///old/path"}
        second["symbols"][0]["location"] = {"uri": "file:///new/path"}
        self.assertEqual(public_declarations([first]), public_declarations([second]))
        second["symbols"][0]["declarationFragments"] = [{"kind": "keyword", "spelling": "class"}]
        self.assertNotEqual(public_declarations([first]), public_declarations([second]))

    def test_corrections_preserve_tokens_file_inventory_and_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
            host = compiler.parents[1] / "lib/swift/host"
            sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
            checker = root / "tokens"
            subprocess.run([str(compiler), "-sdk", sdk, "-module-cache-path", str(root / "module-cache"),
                            "-I", str(host), "-L", str(host), "-Xlinker", "-rpath", "-Xlinker", str(host),
                            str(ROOT / "Tools/documentation_source_tokens.swift"), "-o", str(checker)], check=True)
            tokenize = lambda directory: json.loads(subprocess.check_output([str(checker), str(directory)]))
            current, baseline = root / "current", root / "baseline"
            source = 'let text = #"a /* literal */ and // text"#\nlet answer = 1 + 2\n'
            for directory in (current, baseline):
                library = directory / "Sources/Lokalized"
                library.mkdir(parents=True)
                (directory / "Package.swift").write_text("same package")
                (library / "Example.swift").write_text(source)
                (library / "PrivacyInfo.xcprivacy").write_text("same resource")
            file = current / "Sources/Lokalized/Example.swift"
            alias = root / "library-alias"
            alias.symlink_to(file.parent, target_is_directory=True)
            self.assertEqual(tokenize(file.parent), tokenize(alias))
            file.write_text("/// Consumer prose\n/* nested /* comment */ note */\n" + source)
            compare_documentation_inputs(current, baseline, tokenize)
            for changed in (source.replace("1 + 2", "1 - 2"), source.replace("/* literal */", "/* changed */")):
                file.write_text(changed)
                with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, "cannot change Swift code"):
                    compare_documentation_inputs(current, baseline, tokenize)
            file.write_text(source)
            extra = file.with_name("Extra.swift")
            extra.write_text("let extra = true")
            with self.assertRaisesRegex(ValueError, "file inventory"):
                compare_documentation_inputs(current, baseline, tokenize)
            extra.unlink()
            (current / "Sources/Lokalized/PrivacyInfo.xcprivacy").write_text("changed resource")
            with self.assertRaisesRegex(ValueError, "cannot change library resources"):
                compare_documentation_inputs(current, baseline, tokenize)


if __name__ == "__main__":
    unittest.main()
