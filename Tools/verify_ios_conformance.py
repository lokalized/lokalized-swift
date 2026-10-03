#!/usr/bin/env python3
"""Run every standalone qualification command in an owned iOS simulator app.

Requires a current source-bound Apple deployment receipt and its retained
binaries. Python stdlib and installed Apple tools only; no XCTest, downloads,
external packages, signing identity or physical-device installation.
"""
import argparse
import base64
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import sys
import tempfile
import uuid

import verify_deployment as sdk
import verify_ios_runtime as simulator

ROOT = sdk.ROOT
SCOPE = "ios-simulator-standalone-conformance-v1"
BUNDLE = "com.lokalized.qualification.Conformance"
BEGIN = "LOKALIZED_IOS_REPORT_BEGIN"
END = "LOKALIZED_IOS_REPORT_END"
COMMANDS = {
    "--self-test": ("selfTests",), "--inventory": ("inventory",),
    "--plural-data": ("dataAudits", "pluralData"), "--locale-data": ("dataAudits", "localeData"),
    "--resolution-components": ("resolutionComponents",), "--runtime-adapter": None,
    "--loader": ("nativeFilesystemAudit",), "--loader-boundaries": None,
    "--manifest-contract": ("manifestContract",), "--manifest-normalization": ("manifestNormalization",),
    "--diagnostic-text": ("diagnosticText",), "--manifest-urls": ("manifestURLs",),
    "--idna-normalization": ("idnaNormalization",), "--audit": ("wholeRuntimeAudit",),
}
LIMITS = "All standalone commands execute; the frozen corpus retains 2197 passes and 184 pending IDs. No release parity, minimum compiler/OS, physical device, Intel, XCTest or hosted CI claim."
require = simulator.require
sha = simulator.sha
read = simulator.read


def decode(text):
    return json.loads(text, object_pairs_hook=simulator.unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("Nonfinite JSON: " + value)))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def inputs():
    paths = [ROOT / "Package.swift"]
    for name in ("Sources", "Reference", "Tools"):
        paths += [p for p in (ROOT / name).rglob("*") if p.is_file()
                  and not any(part in ("__pycache__", ".build", ".DS_Store") for part in p.relative_to(ROOT).parts)]
    return {str(p.relative_to(ROOT)): sha(p) for p in sorted(paths)}


def deployment_input(path):
    report = read(path)
    require(report["status"] == "passed" and report["languageMode"] == "6"
            and report["runtimeDependencies"] == "local source modules and Apple system/Swift runtime only",
            "Apple deployment did not pass")
    modules = {name: sdk.source_files(name) for name in ("Lokalized", "LokalizedConformanceSupport", "LokalizedConformance")}
    require(report["sourceSha256"] == sdk.source_hashes(modules), "Apple deployment sources are stale")
    require(all(sha(name) == digest for name, digest in report["inputSha256"].items()), "Apple deployment inputs are stale")
    require(report["referenceDirectory"] == str(ROOT / "Reference"), "Unexpected deployment reference directory")
    require(re.search(r"dependencies:\s*\[\]", (ROOT / "Package.swift").read_text()), "External package dependencies declared")
    targets = {t["name"]: t for t in report["targets"]}
    require(set(targets) == {t[0] for t in sdk.TARGETS}, "Deployment target inventory differs")
    for target in targets.values():
        require(target["status"] == "compiled-imported-linked-inspected" and len(target["binaries"]) == 4,
                "Deployment binaries are incomplete")
        for binary in target["binaries"]:
            require(sha(binary["path"]) == binary["sha256"], "Deployment binary bytes differ")
            for dependency in binary["dependencies"]:
                require(dependency["kind"] == sdk.dependency_kind(dependency["path"]), "Deployment dependency differs")
    host = targets["macos-arm64"]
    runtime = host["runtimeExecution"]
    require(runtime["status"] == "passed-on-host", "Host baseline was not executed")
    host_bin = Path(next(b["path"] for b in host["binaries"] if Path(b["path"]).name == "LokalizedConformance"))
    expected = {}
    for command, keys in COMMANDS.items():
        if keys is None:
            continue
        value = runtime
        for key in keys:
            value = value[key]
        prefix = [str(host_bin), command]
        if command != "--self-test": prefix += ["--reference", str(ROOT / "Reference")]
        observations = [c for c in report["commands"] if c["arguments"][:len(prefix)] == prefix]
        require(len(observations) == 1 and observations[0]["exitCode"] == (1 if command == "--audit" else 0)
                and canonical(decode(observations[0]["stdout"])) == canonical(value), "Host command evidence differs: " + command)
        expected[command] = value
    return report, targets["ios-simulator-arm64"], host_bin, expected


def extract(text):
    lines = text.splitlines()
    require(lines.count(BEGIN) == 1 and lines.count(END) == 1, "Missing or repeated iOS output frame")
    start, finish = lines.index(BEGIN), lines.index(END)
    payload = lines[start + 1:finish]
    require(payload and all(len(line) == 1024 for line in payload[:-1]) and 0 < len(payload[-1]) <= 1024,
            "iOS output frame chunk inventory differs")
    encoded = "".join(payload)
    raw = base64.b64decode(encoded, validate=True)
    require(base64.b64encode(raw).decode() == encoded, "iOS output frame is not canonical base64")
    return decode(raw.decode("utf-8"))


def frame_bytes(data):
    payload = base64.b64encode(data).decode()
    return BEGIN + "\n" + "\n".join(payload[n:n+1024] for n in range(0, len(payload), 1024)) + "\n" + END + "\n"


def build_app(report, deployment, target, output):
    app = output / "IOSConformance.app"
    app.mkdir()
    module_dir = Path(target["binaries"][0]["path"]).parent
    for name in ("libLokalized.dylib", "libLokalizedConformanceSupport.dylib"):
        shutil.copy2(module_dir / name, app / name)
    shutil.copytree(ROOT / "Reference", app / "Reference", ignore=shutil.ignore_patterns(".DS_Store"))
    privacy = app / "lokalized-swift_Lokalized.bundle"
    privacy.mkdir()
    shutil.copy2(ROOT / "Sources/Lokalized/PrivacyInfo.xcprivacy", privacy / "PrivacyInfo.xcprivacy")
    info = {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "IOSConformance", "CFBundleName": "IOSConformance",
            "CFBundlePackageType": "APPL", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0", "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            "MinimumOSVersion": "15.0", "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1, 2]}
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    build = {"commands": [], "app": str(app), "binaries": []}
    report["build"] = build
    swiftc = sdk.invoke(build, ["xcrun", "--find", "swiftc"], "Locate app compiler").strip()
    compiler = sdk.invoke(build, [swiftc, "--version"], "Identify app compiler").strip()
    require(compiler == deployment["compiler"], "App and library compilers differ")
    build["compiler"] = compiler
    command = [swiftc, "-swift-version", "6", "-default-isolation", "MainActor", "-parse-as-library",
               "-target", target["triple"], "-sdk", deployment["sdks"]["iphonesimulator"]["path"],
               "-module-cache-path", str(output / "ModuleCache"), "-I", str(module_dir), "-L", str(module_dir),
               "-lLokalizedConformanceSupport", "-lLokalized", "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
               "-o", str(app / "IOSConformance"), str(ROOT / "Tools/IOSConformanceApp.swift")]
    sdk.invoke(build, command, "Compile real iOS conformance app")
    for name in ("libLokalized.dylib", "libLokalizedConformanceSupport.dylib"):
        sdk.invoke(build, ["codesign", "--force", "--sign", "-", str(app / name)], "Ad-hoc sign local simulator module")
    sdk.invoke(build, ["codesign", "--force", "--sign", "-", str(app)], "Ad-hoc sign local simulator app")
    for name in ("libLokalized.dylib", "libLokalizedConformanceSupport.dylib", "IOSConformance"):
        build["binaries"].append(sdk.inspect_binary(build, app / name, sdk.TARGETS[3]))
    build["filesSHA256"] = {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob("*")) if p.is_file()}
    return app


def package_check(build, deployment):
    app = Path(build["app"])
    require(set(build) == {"commands", "app", "binaries", "compiler", "filesSHA256"}
            and build["compiler"] == deployment["compiler"], "App build scope differs")
    require(build["filesSHA256"] == {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob("*")) if p.is_file()},
            "Packaged conformance app bytes differ")
    for name in inputs():
        if name.startswith("Reference/"):
            require(sha(app / name) == sha(ROOT / name), "Packaged reference bytes differ")
    require(sha(app / "lokalized-swift_Lokalized.bundle/PrivacyInfo.xcprivacy")
            == sha(ROOT / "Sources/Lokalized/PrivacyInfo.xcprivacy"), "Packaged privacy bytes differ")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == BUNDLE and info["MinimumOSVersion"] == "15.0", "App identity/floor differs")
    require(len(build["binaries"]) == 3 and {Path(b["path"]).name for b in build["binaries"]}
            == {"IOSConformance", "libLokalized.dylib", "libLokalizedConformanceSupport.dylib"}, "App binary inventory differs")
    for binary in build["binaries"]:
        require(Path(binary["path"]) == app / Path(binary["path"]).name
                and binary["platform"] == "IOSSIMULATOR" and binary["architecture"] == "arm64"
                and sdk.normalized_version(binary["minimumOS"]) == (15, 0, 0)
                and sha(binary["path"]) == binary["sha256"], "App Mach-O identity/floor differs")
        for dependency in binary["dependencies"]:
            require(dependency["kind"] == sdk.dependency_kind(dependency["path"]), "App dependency differs")
    require(build["commands"] and all(c["exitCode"] == 0 for c in build["commands"]), "App compilation/inspection failed")
    return app


def supplements(report, host_bin, expected):
    require(len(report["hostSupplement"]) == 2, "Missing native host supplement")
    for record, command in zip(report["hostSupplement"], ["--runtime-adapter", "--loader-boundaries"]):
        require(record["arguments"] == [str(host_bin), command, "--reference", str(ROOT / "Reference")]
                and type(record["exitCode"]) is int and record["exitCode"] == 0, "Host supplemental command differs")
        expected[command] = decode(record["stdout"])
        require(expected[command]["status"] == "passed", "Host supplement failed")


def protocol_check(report, app, expected, snapshot, deployment_sha):
    require(set(report) == set("formatVersion scope status inputSha256 deploymentReportSHA256 build hostSupplement commands runtime device cleanup startedAtUTC finishedAtUTC limits".split()), "iOS conformance receipt fields differ")
    require(type(report["formatVersion"]) is int and report["formatVersion"] == 1
            and report["scope"] == SCOPE and report["status"] == "passed"
            and report["limits"] == LIMITS, "iOS conformance scope/status differs")
    require(report["inputSha256"] == snapshot and report["deploymentReportSHA256"] == deployment_sha, "Conformance inputs are stale")
    runtime, device = report["runtime"], report["device"]
    require(set(runtime) == {"identifier", "version", "build", "architecture", "minimumOSExecuted"}
            and all(type(runtime[k]) is str for k in ["identifier", "version", "build", "architecture"])
            and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and runtime["version"] == runtime["identifier"].split("iOS-", 1)[1].replace("-", ".")
            and runtime["architecture"] == "arm64" and runtime["minimumOSExecuted"] is (runtime["version"] == "15.0"), "Runtime claim differs")
    require(set(device) == {"id", "name", "type", "createdByThisRun"} and device["createdByThisRun"] is True
            and str(uuid.UUID(device["id"])) == device["id"].lower()
            and device["name"].startswith("lokalized-qualification-"), "Owned simulator identity differs")
    arguments = [["xcrun", "simctl", "list", "runtimes", "--json"],
                 ["xcrun", "simctl", "create", device["name"], device["type"], runtime["identifier"]],
                 ["xcrun", "simctl", "boot", device["id"]], ["xcrun", "simctl", "bootstatus", device["id"], "-b"],
                 ["xcrun", "simctl", "list", "devices", "--json"], ["xcrun", "simctl", "install", device["id"], str(app)]]
    arguments += [["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device["id"], BUNDLE, command]
                  for command in COMMANDS]
    arguments += [["xcrun", "simctl", command, device["id"]] for command in ("shutdown", "delete")]
    require(len(report["commands"]) == len(arguments), "Standalone command inventory differs")
    for record, args in zip(report["commands"], arguments):
        require(set(record) == {"arguments", "exitCode", "stdout", "stderr"} and record["arguments"] == args
                and type(record["exitCode"]) is int and record["exitCode"] == 0
                and type(record["stdout"]) is str and type(record["stderr"]) is str, "Missing or failed simulator command")
    selected = [r for r in decode(report["commands"][0]["stdout"])["runtimes"] if r["identifier"] == runtime["identifier"]]
    require(len(selected) == 1 and selected[0]["isAvailable"] is True and selected[0]["platform"] == "iOS"
            and selected[0]["version"] == runtime["version"] and selected[0]["buildversion"] == runtime["build"]
            and "arm64" in selected[0]["supportedArchitectures"]
            and device["type"] in [d["identifier"] for d in selected[0]["supportedDeviceTypes"]], "Installed runtime evidence differs")
    require(report["commands"][1]["stdout"].strip() == device["id"], "Created simulator differs")
    owned = [d for d in decode(report["commands"][4]["stdout"])["devices"].get(runtime["identifier"], []) if d["udid"] == device["id"]]
    require(len(owned) == 1 and owned[0]["name"] == device["name"] and owned[0]["state"] == "Booted", "Simulator runtime was not booted")
    actual = {}
    for index, command in enumerate(COMMANDS, 6):
        record = report["commands"][index]
        require(not record["stderr"].strip().startswith('{"error"'), "App reported an execution error")
        actual[command] = extract(record["stdout"])
        require(canonical(actual[command]) == canonical(expected[command]), "iOS/host observation differs: " + command)
    require(report["cleanup"] == {"shutdown": "passed", "deleted": "passed"}, "Simulator cleanup differs")
    return actual


def check(report, deployment_path):
    deployment, _, host_bin, expected = deployment_input(deployment_path)
    app = package_check(report["build"], deployment)
    supplements(report, host_bin, expected)
    actual = protocol_check(report, app, expected, inputs(), sha(deployment_path))
    # Reuse the existing corpus/adapter/filesystem gates, preserving exact IDs and
    # native pending observations in addition to complete host-output equality.
    import verify_package
    with tempfile.TemporaryDirectory(prefix="lokalized-ios-report-check-") as directory:
        for command, gate in [("--audit", verify_package.audit_check), ("--inventory", verify_package.inventory_check),
                              ("--runtime-adapter", verify_package.runtime_adapter_check), ("--loader", verify_package.loader_check),
                              ("--resolution-components", verify_package.resolution_components_check)]:
            path = Path(directory) / (command[2:] + ".json")
            path.write_text(canonical(actual[command]))
            gate(path, ROOT / "Reference")
    return {"status": "passed", "scope": SCOPE, "iOS": report["runtime"]["version"], "standaloneCommandsExecuted": len(COMMANDS),
            "runtimePassed": len(actual["--audit"]["runtimePassed"]), "pending": len(actual["--audit"]["unimplemented"]),
            "releaseParity": False, "minimumOSExecuted": report["runtime"]["minimumOSExecuted"], "deviceDeleted": True}


def negative_controls(report, deployment_path):
    check(report, deployment_path)
    _, _, host_bin, expected = deployment_input(deployment_path)
    supplements(report, host_bin, expected)
    snapshot, stamp = inputs(), sha(deployment_path)
    app = Path(report["build"]["app"])
    def observation(r, command, mutate):
        record = r["commands"][6 + list(COMMANDS).index(command)]
        value = extract(record["stdout"])
        mutate(value)
        record["stdout"] = frame_bytes(canonical(value).encode())
    mutations = {
        "stale-source": lambda r: r["inputSha256"].update({"Package.swift": "0" * 64}),
        "wrong-deployment": lambda r: r.update(deploymentReportSHA256="0" * 64),
        "missing-command": lambda r: r["commands"].pop(6),
        "failed-launch": lambda r: r["commands"][6].update(exitCode=1),
        "boolean-exit-code": lambda r: r["commands"][6].update(exitCode=False),
        "host-launch-substitution": lambda r: r["commands"][6].update(arguments=[str(host_bin), "--self-test"]),
        "missing-output": lambda r: r["commands"][6].update(stdout=""),
        "duplicate-frame": lambda r: r["commands"][6].update(stdout=r["commands"][6]["stdout"] + BEGIN + "\n"),
        "wrong-runtime": lambda r: r["runtime"].update(identifier="invalid-runtime"),
        "false-minimum-os": lambda r: r["runtime"].update(minimumOSExecuted=not r["runtime"]["minimumOSExecuted"]),
        "unowned-device": lambda r: r["device"].update(createdByThisRun=False),
        "cleanup-other-device": lambda r: r["commands"][-1]["arguments"].__setitem__(-1, str(uuid.uuid4())),
        "cleanup-omitted": lambda r: r["cleanup"].update(deleted="not attempted"),
        "missing-passing-id": lambda r: observation(r, "--audit", lambda v: v["runtimePassed"].pop()),
        "missing-pending-id": lambda r: observation(r, "--audit", lambda v: v["unimplemented"].pop()),
        "false-corpus-completion": lambda r: observation(r, "--audit", lambda v: v.update(status="passed")),
        "boolean-self-test-count": lambda r: observation(r, "--self-test", lambda v: v.update(checks=True)),
        "nfc-count-drift": lambda r: observation(r, "--idna-normalization", lambda v: v.update(passed=v["passed"] - 1)),
        "diagnostic-observation-omitted": lambda r: observation(r, "--diagnostic-text", lambda v: v["observations"].pop()),
        "unknown-claim": lambda r: r.update(releaseParity=True),
    }
    for name, mutate in mutations.items():
        corrupted = copy.deepcopy(report)
        mutate(corrupted)
        try:
            protocol_check(corrupted, app, expected, snapshot, stamp)
        except (ValueError, KeyError, TypeError):
            continue
        raise ValueError("Corrupted iOS conformance receipt accepted: " + name)
    return list(mutations)


def execute(args):
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "iOS qualification requires an arm64 Mac")
    deployment, target, host_bin, expected = deployment_input(args.deployment_report)
    output = Path(tempfile.mkdtemp(prefix="lokalized-ios-conformance-", dir="/private/tmp"))
    report = {"formatVersion": 1, "scope": SCOPE, "status": "running", "inputSha256": inputs(),
              "deploymentReportSHA256": sha(args.deployment_report), "hostSupplement": [], "commands": [], "cleanup": {},
              "startedAtUTC": datetime.now(timezone.utc).isoformat(), "limits": LIMITS}
    device = None
    try:
        app = build_app(report, deployment, target, output)
        supplement = {"commands": report["hostSupplement"]}
        for command in ("--runtime-adapter", "--loader-boundaries"):
            simulator.invoke(supplement, [str(host_bin), command, "--reference", str(ROOT / "Reference")], timeout=600)
        inventory = decode(simulator.invoke(report, ["xcrun", "simctl", "list", "runtimes", "--json"]))
        selected = [r for r in inventory["runtimes"] if r["identifier"] == args.runtime and r["isAvailable"]]
        require(len(selected) == 1 and selected[0]["platform"] == "iOS"
                and "arm64" in selected[0]["supportedArchitectures"], "Requested iOS runtime is unavailable/incompatible")
        runtime = selected[0]
        device_type = next(d["identifier"] for d in runtime["supportedDeviceTypes"] if d["productFamily"] == "iPhone")
        report["runtime"] = {"identifier": args.runtime, "version": runtime["version"], "build": runtime["buildversion"],
                             "architecture": "arm64", "minimumOSExecuted": runtime["version"] == "15.0"}
        name = "lokalized-qualification-" + str(uuid.uuid4())
        device = simulator.invoke(report, ["xcrun", "simctl", "create", name, device_type, args.runtime]).strip()
        require(str(uuid.UUID(device)) == device.lower(), "Created device is not a UUID")
        report["device"] = {"id": device, "name": name, "type": device_type, "createdByThisRun": True}
        simulator.invoke(report, ["xcrun", "simctl", "boot", device])
        simulator.invoke(report, ["xcrun", "simctl", "bootstatus", device, "-b"], timeout=240)
        simulator.invoke(report, ["xcrun", "simctl", "list", "devices", "--json"])
        simulator.invoke(report, ["xcrun", "simctl", "install", device, str(app)])
        for command in COMMANDS:
            simulator.invoke(report, ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, BUNDLE, command], timeout=600)
        report["status"] = "passed"
    except BaseException as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        if device is not None:
            for command, field in [("shutdown", "shutdown"), ("delete", "deleted")]:
                try:
                    simulator.invoke(report, ["xcrun", "simctl", command, device])
                    report["cleanup"][field] = "passed"
                except Exception as error:
                    report["cleanup"][field] = str(error)
                    report["status"] = "failed"
        report["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    try:
        check(report, args.deployment_report)
    except Exception as error:
        report.update(status="failed", error=str(error))
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        raise
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment-report", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--report", type=Path)
    modes.add_argument("--report-check", type=Path)
    parser.add_argument("--runtime")
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    if args.report and not args.runtime: parser.error("Select an installed iOS runtime with --runtime")
    report = read(args.report_check) if args.report_check else execute(args)
    result = check(report, args.deployment_report)
    if args.negative_controls: result["rejectedControls"] = negative_controls(report, args.deployment_report)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("iOS conformance refused: " + str(error), file=sys.stderr)
        sys.exit(1)
