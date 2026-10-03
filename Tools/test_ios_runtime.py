#!/usr/bin/env python3
"""Offline refusal tests using synthetic simulator receipts, never runtime claims."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import verify_ios_runtime as ios


class IOSReceiptTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="lokalized-ios-check-tests-")
        self.addCleanup(self.directory.cleanup)
        self.delivery = Path(self.directory.name) / "delivery.json"
        self.delivery.write_text("{}")
        self.app = Path(self.directory.name) / "IOSCatalogs.app"
        self.bundle = "com.lokalized.examples.IOSCatalogs"
        self.runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
        self.device = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.name = "lokalized-qualification-synthetic-test"
        self.type = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
        patches = [patch.object(ios, "packaged_input", return_value=(self.app, self.bundle, "b" * 64)),
                   patch.object(ios, "inputs", return_value={"Package.swift": "a" * 64})]
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        arguments = [
            ["xcrun", "simctl", "list", "runtimes", "--json"],
            ["xcrun", "simctl", "create", self.name, self.type, self.runtime],
            ["xcrun", "simctl", "boot", self.device],
            ["xcrun", "simctl", "bootstatus", self.device, "-b"],
            ["xcrun", "simctl", "list", "devices", "--json"],
            ["xcrun", "simctl", "install", self.device, str(self.app)],
            ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", self.device, self.bundle, "--qualify"],
            ["xcrun", "simctl", "shutdown", self.device],
            ["xcrun", "simctl", "delete", self.device],
        ]
        commands = [{"arguments": args, "exitCode": 0, "stdout": "", "stderr": ""} for args in arguments]
        commands[0]["stdout"] = json.dumps({"runtimes": [{"identifier": self.runtime, "version": "26.5",
            "buildversion": "23F77", "isAvailable": True, "platform": "iOS", "supportedArchitectures": ["arm64"],
            "supportedDeviceTypes": [{"identifier": self.type}]}]})
        commands[1]["stdout"] = self.device + "\n"
        commands[4]["stdout"] = json.dumps({"devices": {self.runtime: [{"udid": self.device, "name": self.name, "state": "Booted"}]}})
        commands[6]["stdout"] = self.bundle + ": 123\n" + ios.MARKER + "\n"
        self.report = {"formatVersion": 1, "scope": ios.SCOPE, "status": "passed",
            "inputSha256": {"Package.swift": "a" * 64}, "deliveryReportSHA256": ios.sha(self.delivery),
            "binarySHA256": "b" * 64, "bundleIdentifier": self.bundle,
            "runtime": {"identifier": self.runtime, "version": "26.5", "build": "23F77", "architecture": "arm64", "minimumOSExecuted": False},
            "device": {"id": self.device, "name": self.name, "type": self.type, "createdByThisRun": True},
            "observation": ios.MARKER, "commands": commands, "cleanup": {"shutdown": "passed", "deleted": "passed"},
            "startedAtUTC": "synthetic", "finishedAtUTC": "synthetic", "limits": ios.LIMITS}

    def test_control_retains_narrow_coverage(self):
        result = ios.check(self.report, self.delivery)
        self.assertEqual(result["iOS"], "26.5")
        self.assertFalse(result["fullCorpusExecuted"])
        self.assertFalse(result["minimumOSExecuted"])

    def test_all_ten_corruptions_are_refused(self):
        self.assertEqual(len(ios.negative_controls(self.report, self.delivery)), 10)

    def test_cleanup_cannot_target_another_device(self):
        self.report["commands"][-1]["arguments"][-1] = "11111111-2222-3333-4444-555555555555"
        with self.assertRaisesRegex(ValueError, "actual simulator command"):
            ios.check(self.report, self.delivery)

    def test_device_cannot_belong_to_another_runtime(self):
        data = json.loads(self.report["commands"][4]["stdout"])
        data["devices"]["other-runtime"] = data["devices"].pop(self.runtime)
        self.report["commands"][4]["stdout"] = json.dumps(data)
        with self.assertRaisesRegex(ValueError, "not booted"):
            ios.check(self.report, self.delivery)

    def test_unavailable_runtime_is_refused(self):
        data = json.loads(self.report["commands"][0]["stdout"])
        data["runtimes"][0]["isAvailable"] = False
        self.report["commands"][0]["stdout"] = json.dumps(data)
        with self.assertRaisesRegex(ValueError, "Installed runtime"):
            ios.check(self.report, self.delivery)

    def test_failure_output_cannot_be_hidden_by_success_marker(self):
        self.report["commands"][6]["stderr"] = "Catalog qualification failed: example error"
        with self.assertRaisesRegex(ValueError, "successful qualification marker"):
            ios.check(self.report, self.delivery)

    def test_duplicate_receipt_members_are_refused(self):
        self.delivery.write_text('{"status":"failed","status":"passed"}')
        with self.assertRaisesRegex(ValueError, "Repeated receipt member"):
            ios.read(self.delivery)

    def test_boolean_is_not_a_format_version(self):
        self.report["formatVersion"] = True
        with self.assertRaisesRegex(ValueError, "scope/status"):
            ios.check(self.report, self.delivery)

    def test_floor_claim_tracks_the_actual_runtime_and_keeps_narrow_scope(self):
        identifier = "com.apple.CoreSimulator.SimRuntime.iOS-15-0"
        self.report["runtime"].update(identifier=identifier, version="15.0", minimumOSExecuted=True)
        self.report["commands"][1]["arguments"][-1] = identifier
        inventory = json.loads(self.report["commands"][0]["stdout"])
        inventory["runtimes"][0].update(identifier=identifier, version="15.0")
        self.report["commands"][0]["stdout"] = json.dumps(inventory)
        devices = json.loads(self.report["commands"][4]["stdout"])
        devices["devices"][identifier] = devices["devices"].pop(self.runtime)
        self.report["commands"][4]["stdout"] = json.dumps(devices)
        result = ios.check(self.report, self.delivery)
        self.assertTrue(result["minimumOSExecuted"])
        self.assertFalse(result["fullCorpusExecuted"])
        self.assertEqual(len(ios.negative_controls(self.report, self.delivery)), 10)


if __name__ == "__main__":
    unittest.main()
