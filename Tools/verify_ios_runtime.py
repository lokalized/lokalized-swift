#!/usr/bin/env python3
"""Execute the source-bound packaged catalog app on an explicitly selected iOS simulator.

Python standard library and Apple tools only. Creates its own simulator, then
shuts down and deletes only that device. No runtime downloads or physical devices.
Saved checks validate evidence without contacting CoreSimulator.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import uuid

import verify_local_delivery as delivery

ROOT = Path(__file__).resolve().parents[1]
SCOPE = "packaged-ios-simulator-catalog-consumer-v1"
MARKER = "Packaged Apple catalogs passed"
LIMITS = "Packaged Bundle.main/locale/plural/exact-key consumer only; no full corpus, device, minimum compiler, Intel or hosted CI claim. Minimum OS execution refers only to this consumer."


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique(items):
    value = {}
    for name, item in items:
        require(name not in value, "Repeated receipt member: " + name)
        value[name] = item
    return value


def read(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def inputs():
    return {**delivery.inputs(), "Tools/verify_ios_runtime.py": sha(__file__)}


def packaged_input(path):
    value = read(path)
    require(value["status"] == "passed" and value["externalPackageDependencies"] == 0,
            "Packaged delivery did not pass with zero dependencies")
    require(value["inputSha256"] == delivery.inputs(), "Packaged delivery sources are stale")
    targets = [t for t in value["targets"] if t["sdk"] == "iphonesimulator"]
    require(len(targets) == 1, "Expected one packaged iOS simulator target")
    target = targets[0]
    require(target["status"] == "compiled-and-packaged" and target["minimumOS"] == "15.0"
            and target["languageMode"] == "6" and target["defaultIsolation"] == "MainActor"
            and target["approachableConcurrency"] is True, "Packaged simulator settings differ")
    app = Path(target["app"])
    binary = app / "IOSCatalogs"
    require(sha(binary) == target["binarySha256"], "Packaged simulator binary differs")
    delivery.verify_resources(app, {})
    plist = plistlib.loads((app / "Info.plist").read_bytes())
    require(plist["CFBundleIdentifier"] == "com.lokalized.examples.IOSCatalogs", "Unexpected consumer bundle")
    return app, plist["CFBundleIdentifier"], target["binarySha256"]


def invoke(report, arguments, timeout=120):
    print(" ".join(arguments[:4]), file=sys.stderr, flush=True)
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    record = {"arguments": arguments, "exitCode": result.returncode,
              "stdout": result.stdout, "stderr": result.stderr}
    report["commands"].append(record)
    require(result.returncode == 0, "Simulator command failed: " + " ".join(arguments) + "\n" + result.stderr)
    return result.stdout


def check(report, delivery_path):
    require(set(report) == set("formatVersion scope status inputSha256 deliveryReportSHA256 binarySHA256 bundleIdentifier runtime device observation commands cleanup startedAtUTC finishedAtUTC limits".split()),
            "Unexpected iOS runtime receipt fields")
    require(type(report["formatVersion"]) is int and report["formatVersion"] == 1
            and report["scope"] == SCOPE and report["status"] == "passed", "iOS receipt scope/status differs")
    app, bundle, binary_sha = packaged_input(delivery_path)
    require(report["inputSha256"] == inputs() and report["deliveryReportSHA256"] == sha(delivery_path)
            and report["binarySHA256"] == binary_sha and report["bundleIdentifier"] == bundle, "iOS receipt inputs differ")
    runtime = report["runtime"]
    require(type(runtime) is dict and set(runtime) == {"identifier", "version", "build", "architecture", "minimumOSExecuted"}
            and all(type(runtime[field]) is str for field in ["identifier", "version", "build", "architecture"])
            and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and runtime["version"] == runtime["identifier"].split("iOS-", 1)[1].replace("-", ".")
            and runtime["architecture"] == "arm64"
            and runtime["minimumOSExecuted"] is (runtime["version"] == "15.0"),
            "Runtime identity or coverage claim differs")
    device = report["device"]
    require(set(device) == {"id", "name", "type", "createdByThisRun"} and device["createdByThisRun"] is True
            and str(uuid.UUID(device["id"])) == device["id"].lower()
            and device["name"].startswith("lokalized-qualification-"), "Owned simulator identity differs")
    commands = report["commands"]
    require(type(commands) is list and len(commands) == 9, "Simulator command inventory differs")
    expected = [
        ["xcrun", "simctl", "list", "runtimes", "--json"],
        ["xcrun", "simctl", "create", device["name"], device["type"], runtime["identifier"]],
        ["xcrun", "simctl", "boot", device["id"]],
        ["xcrun", "simctl", "bootstatus", device["id"], "-b"],
        ["xcrun", "simctl", "list", "devices", "--json"],
        ["xcrun", "simctl", "install", device["id"], str(app)],
        ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device["id"], bundle, "--qualify"],
        ["xcrun", "simctl", "shutdown", device["id"]],
        ["xcrun", "simctl", "delete", device["id"]],
    ]
    for actual, arguments in zip(commands, expected):
        require(set(actual) == {"arguments", "exitCode", "stdout", "stderr"}
                and actual["arguments"] == arguments and type(actual["exitCode"]) is int
                and actual["exitCode"] == 0 and type(actual["stdout"]) is str and type(actual["stderr"]) is str,
                "Missing or failed actual simulator command")
    runtimes = json.loads(commands[0]["stdout"])["runtimes"]
    selected = [r for r in runtimes if r["identifier"] == runtime["identifier"]]
    require(len(selected) == 1 and selected[0]["isAvailable"] is True and selected[0]["platform"] == "iOS"
            and selected[0]["version"] == runtime["version"] and selected[0]["buildversion"] == runtime["build"]
            and "arm64" in selected[0]["supportedArchitectures"]
            and device["type"] in [d["identifier"] for d in selected[0]["supportedDeviceTypes"]], "Installed runtime evidence differs")
    require(commands[1]["stdout"].strip() == device["id"], "Created device differs")
    devices = json.loads(commands[4]["stdout"])["devices"].get(runtime["identifier"], [])
    owned = [d for d in devices if d["udid"] == device["id"]]
    require(len(owned) == 1 and owned[0]["state"] == "Booted" and owned[0]["name"] == device["name"], "Selected runtime was not booted")
    launch = commands[6]
    require(launch["stdout"].splitlines().count(MARKER) == 1
            and "Catalog qualification failed" not in launch["stdout"] + launch["stderr"]
            and report["observation"] == MARKER, "App did not produce its successful qualification marker")
    require(report["cleanup"] == {"shutdown": "passed", "deleted": "passed"} and report["limits"] == LIMITS,
            "Cleanup or qualification limits differ")
    return {"status": "passed", "scope": SCOPE, "iOS": runtime["version"], "binarySHA256": binary_sha,
            "fullCorpusExecuted": False, "minimumOSExecuted": runtime["minimumOSExecuted"], "deviceDeleted": True}


def negative_controls(report, delivery_path):
    check(report, delivery_path)
    changes = {
        "incorrect-minimum-os": lambda r: r["runtime"].update(minimumOSExecuted=not r["runtime"]["minimumOSExecuted"]),
        "stale-source": lambda r: r["inputSha256"].update({"Package.swift": "0" * 64}),
        "changed-binary": lambda r: r.update(binarySHA256="0" * 64),
        "missing-launch": lambda r: r["commands"].pop(6),
        "failed-launch": lambda r: r["commands"][6].update(exitCode=1),
        "missing-app-output": lambda r: r["commands"][6].update(stdout=""),
        "wrong-runtime": lambda r: r["runtime"].update(identifier="invalid-runtime"),
        "unowned-device": lambda r: r["device"].update(createdByThisRun=False),
        "cleanup-omitted": lambda r: r["cleanup"].update(deleted="not attempted"),
        "unknown-field": lambda r: r.update(releaseParity=True),
    }
    for name, change in changes.items():
        altered = copy.deepcopy(report)
        change(altered)
        try:
            check(altered, delivery_path)
        except (ValueError, KeyError, TypeError):
            continue
        raise ValueError("Corrupted iOS receipt accepted: " + name)
    return list(changes)


def execute(args):
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "This qualifier requires an arm64 Mac")
    app, bundle, binary_sha = packaged_input(args.delivery_report)
    report = {"formatVersion": 1, "scope": SCOPE, "status": "running", "inputSha256": inputs(),
              "deliveryReportSHA256": sha(args.delivery_report), "binarySHA256": binary_sha, "bundleIdentifier": bundle,
              "commands": [], "cleanup": {}, "startedAtUTC": datetime.now(timezone.utc).isoformat(), "limits": LIMITS}
    device = None
    try:
        inventory = json.loads(invoke(report, ["xcrun", "simctl", "list", "runtimes", "--json"]))
        selected = [r for r in inventory["runtimes"] if r["identifier"] == args.runtime and r["isAvailable"]]
        require(len(selected) == 1 and selected[0]["platform"] == "iOS", "Requested iOS runtime is unavailable")
        runtime = selected[0]
        require("arm64" in runtime["supportedArchitectures"], "Unsupported qualification runtime architecture")
        device_type = next(d["identifier"] for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
        report["runtime"] = {"identifier": args.runtime, "version": runtime["version"], "build": runtime["buildversion"],
                             "architecture": "arm64", "minimumOSExecuted": runtime["version"] == "15.0"}
        name = "lokalized-qualification-" + str(uuid.uuid4())
        device = invoke(report, ["xcrun", "simctl", "create", name, device_type, args.runtime]).strip()
        require(str(uuid.UUID(device)) == device.lower(), "Simulator did not return a device UUID")
        report["device"] = {"id": device, "name": name, "type": device_type, "createdByThisRun": True}
        invoke(report, ["xcrun", "simctl", "boot", device])
        invoke(report, ["xcrun", "simctl", "bootstatus", device, "-b"], timeout=240)
        invoke(report, ["xcrun", "simctl", "list", "devices", "--json"])
        invoke(report, ["xcrun", "simctl", "install", device, str(app)])
        output = invoke(report, ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, bundle, "--qualify"])
        require(output.splitlines().count(MARKER) == 1, "App qualification marker missing")
        report["observation"] = MARKER
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        if device is not None:
            for command, field in [("shutdown", "shutdown"), ("delete", "deleted")]:
                try:
                    invoke(report, ["xcrun", "simctl", command, device])
                    report["cleanup"][field] = "passed"
                except Exception as error:
                    report["cleanup"][field] = str(error)
                    report["status"] = "failed"
        report["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    try:
        check(report, args.delivery_report)
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        raise
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delivery-report", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--report", type=Path)
    modes.add_argument("--report-check", type=Path)
    parser.add_argument("--runtime")
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    if args.report and not args.runtime:
        parser.error("Runtime execution requires --runtime with an installed iOS runtime identifier")
    report = read(args.report_check) if args.report_check else execute(args)
    result = check(report, args.delivery_report)
    if args.negative_controls:
        result["rejectedControls"] = negative_controls(report, args.delivery_report)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError, KeyError, StopIteration, subprocess.TimeoutExpired) as error:
        print("iOS runtime qualification refused: " + str(error), file=sys.stderr)
        sys.exit(1)
