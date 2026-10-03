#!/usr/bin/env python3
"""Offline iOS conformance receipt refusals; all execution records are synthetic."""
import copy
import json
from pathlib import Path
import plistlib
import unittest
from unittest.mock import patch

import test_ios_runtime as consumer_tests
import verify_ios_conformance as ios


class IOSConformanceReceiptTests(unittest.TestCase):
    def setUp(self):
        fixture = consumer_tests.IOSReceiptTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.app, self.device = fixture.app, fixture.device
        self.deployment = fixture.delivery
        self.snapshot = {"Package.swift": "a" * 64}
        self.stamp = ios.sha(self.deployment)
        self.expected = {c: {"status": "passed", "syntheticCommand": c} for c in ios.COMMANDS}
        self.expected["--self-test"] = {"status": "passed", "checks": 1}
        self.expected["--audit"] = {"status": "incomplete", "runtimePassed": ["synthetic-pass"], "unimplemented": ["synthetic-pending"]}
        self.expected["--idna-normalization"] = {"status": "passed", "passed": 2}
        self.expected["--diagnostic-text"] = {"status": "passed", "observations": [{"id": "synthetic"}]}
        self.report = {k: copy.deepcopy(v) for k, v in fixture.report.items()
                       if k not in ("deliveryReportSHA256", "binarySHA256", "bundleIdentifier", "observation")}
        self.report.update(scope=ios.SCOPE, limits=ios.LIMITS, deploymentReportSHA256=self.stamp,
                           build={"app": str(self.app)}, hostSupplement=[])
        commands = self.report["commands"][:6]
        commands[5]["arguments"][-1] = str(self.app)
        for command in ios.COMMANDS:
            commands.append({"arguments": ["xcrun", "simctl", "launch", "--console", "--terminate-running-process",
                                            self.device, ios.BUNDLE, command], "exitCode": 0, "stderr": "",
                             "stdout": ios.frame_bytes(ios.canonical(self.expected[command]).encode())})
        commands += copy.deepcopy(fixture.report["commands"][-2:])
        self.report["commands"] = commands

    def check(self):
        return ios.protocol_check(self.report, self.app, self.expected, self.snapshot, self.stamp)

    def test_all_commands_keep_incomplete_corpus_status(self):
        actual = self.check()
        self.assertEqual(set(actual), set(ios.COMMANDS))
        self.assertEqual(actual["--audit"]["status"], "incomplete")

    def test_all_twenty_corruptions_are_refused(self):
        with patch.object(ios, "check"), patch.object(ios, "deployment_input", return_value=({}, {}, Path("/synthetic-host"), self.expected)), \
             patch.object(ios, "supplements"), patch.object(ios, "inputs", return_value=self.snapshot):
            self.assertEqual(len(ios.negative_controls(self.report, self.deployment)), 20)

    def test_reordered_launches_are_refused(self):
        self.report["commands"][6], self.report["commands"][7] = self.report["commands"][7], self.report["commands"][6]
        with self.assertRaisesRegex(ValueError, "simulator command"):
            self.check()

    def test_duplicate_output_members_are_refused(self):
        self.report["commands"][6]["stdout"] = ios.frame_bytes(b'{"status":"failed","status":"passed"}')
        with self.assertRaisesRegex(ValueError, "Repeated receipt member"):
            self.check()

    def test_nonfinite_output_is_refused(self):
        self.report["commands"][6]["stdout"] = ios.frame_bytes(b'{"checks":NaN}')
        with self.assertRaisesRegex(ValueError, "Nonfinite JSON"):
            self.check()

    def test_missing_pending_cases_cannot_become_passes(self):
        altered = {"status": "passed", "runtimePassed": ["synthetic-pass", "synthetic-pending"], "unimplemented": []}
        self.report["commands"][6 + list(ios.COMMANDS).index("--audit")]["stdout"] = ios.frame_bytes(ios.canonical(altered).encode())
        with self.assertRaisesRegex(ValueError, "observation differs"):
            self.check()

    def test_booted_device_must_belong_to_recorded_runtime(self):
        data = ios.decode(self.report["commands"][4]["stdout"])
        data["devices"]["other-runtime"] = data["devices"].pop(self.report["runtime"]["identifier"])
        self.report["commands"][4]["stdout"] = ios.canonical(data)
        with self.assertRaisesRegex(ValueError, "not booted"):
            self.check()

    def test_boolean_format_version_is_refused(self):
        self.report["formatVersion"] = True
        with self.assertRaisesRegex(ValueError, "scope/status"):
            self.check()

    def test_output_frame_requires_one_complete_observation(self):
        for text in [ios.END + "\n{}\n" + ios.BEGIN, ios.BEGIN + "\n{}\n{}\n" + ios.END]:
            with self.assertRaises(ValueError): ios.extract(text)

    def test_large_unicode_report_roundtrips_in_bounded_lines(self):
        value = {"synthetic": "é😀e\u0301" * 20_000}
        text = ios.frame_bytes(json.dumps(value, ensure_ascii=False).encode())
        self.assertEqual(ios.extract(text), value)
        self.assertTrue(all(len(line) <= 1024 for line in text.splitlines()[1:-1]))

    def test_invalid_base64_is_refused(self):
        with self.assertRaises(ValueError): ios.extract(ios.BEGIN + "\n!!!!\n" + ios.END)


class IOSConformancePackageTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.directory = tempfile.TemporaryDirectory(prefix="lokalized-ios-package-tests-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / "App.app"
        self.app.mkdir()
        (self.root / "Reference").mkdir()
        (self.root / "Reference/synthetic.json").write_text('{"synthetic":true}')
        (self.app / "Reference").mkdir()
        (self.app / "Reference/synthetic.json").write_bytes((self.root / "Reference/synthetic.json").read_bytes())
        (self.root / "Sources/Lokalized").mkdir(parents=True)
        (self.root / "Sources/Lokalized/PrivacyInfo.xcprivacy").write_text("synthetic privacy")
        (self.app / "lokalized-swift_Lokalized.bundle").mkdir()
        (self.app / "lokalized-swift_Lokalized.bundle/PrivacyInfo.xcprivacy").write_text("synthetic privacy")
        (self.app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": ios.BUNDLE, "MinimumOSVersion": "15.0"}))
        binaries = []
        for name in ["IOSConformance", "libLokalized.dylib", "libLokalizedConformanceSupport.dylib"]:
            path = self.app / name
            path.write_text("synthetic binary " + name)
            binaries.append({"path": str(path), "sha256": ios.sha(path), "platform": "IOSSIMULATOR", "architecture": "arm64", "minimumOS": "15.0",
                             "dependencies": [{"path": "/usr/lib/libSystem.B.dylib", "kind": "apple-system"}]})
        self.build = {"app": str(self.app), "compiler": "synthetic compiler", "commands": [{"exitCode": 0}], "binaries": binaries,
                      "filesSHA256": {str(p.relative_to(self.app)): ios.sha(p) for p in sorted(self.app.rglob("*")) if p.is_file()}}
        self.deployment = {"compiler": "synthetic compiler"}
        for item in [patch.object(ios, "ROOT", self.root), patch.object(ios, "inputs", return_value={"Reference/synthetic.json": ios.sha(self.root / "Reference/synthetic.json")})]:
            item.start(); self.addCleanup(item.stop)

    def test_retained_package_control(self):
        self.assertEqual(ios.package_check(self.build, self.deployment), self.app)

    def test_changed_binary_bytes_are_refused(self):
        (self.app / "IOSConformance").write_text("changed synthetic binary")
        with self.assertRaisesRegex(ValueError, "app bytes differ"):
            ios.package_check(self.build, self.deployment)

    def test_newer_macho_floor_is_refused(self):
        self.build["binaries"][0]["minimumOS"] = "17.0"
        with self.assertRaisesRegex(ValueError, "Mach-O"):
            ios.package_check(self.build, self.deployment)

    def test_external_runtime_library_is_refused(self):
        self.build["binaries"][0]["dependencies"][0]["path"] = "@rpath/External.dylib"
        with self.assertRaisesRegex(RuntimeError, "Unexpected runtime dependency"):
            ios.package_check(self.build, self.deployment)


if __name__ == "__main__":
    unittest.main()
