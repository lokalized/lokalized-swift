#!/usr/bin/env python3
"""Check actual macOS XCTest logs, a race control and retained TSan artifacts.

Development only. Run --snapshot before compilation and --check afterward.
Uses Python stdlib and Apple tools; neither controls nor sanitizer ship in SDKs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CLASSES = ("ConcurrencyTests", "RuntimeSemanticsTests", "PreferredLanguageChooserTests", "LocalCatalogLoaderTests")
ALLOWED_SKIP = "LocalCatalogLoaderTests.testCanonicalSymlinkTargetInvalidUTF8CannotSelectRepairedFilename"


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_inputs():
    paths = [ROOT / "Package.swift", Path(__file__), Path(__file__).with_name("ThreadSanitizerRace.c")]
    paths += sorted((ROOT / "Sources").rglob("*.swift"))
    paths += sorted((ROOT / "Tests/LokalizedTests").glob("*.swift"))
    return {str(path.relative_to(ROOT)): sha(path) for path in paths}


def expected_tests():
    result = set()
    for name in CLASSES:
        source = (ROOT / "Tests/LokalizedTests" / (name + ".swift")).read_text()
        methods = re.findall(r"^\s+func (test\w+)\(", source, re.MULTILINE)
        require(methods and len(methods) == len(set(methods)), "Missing or duplicated selected method declarations")
        result.update(name + "." + method for method in methods)
    return result


def test_observations(text):
    require("ThreadSanitizer:" not in text, "Sanitizer reported a problem in the selected tests")
    pattern = (r"^Test Case '(?:-\[(?:[\w-]+\.)?(\w+) (test\w+)\]|"
               r"(?:[\w-]+\.)?(\w+)\.(test\w+))' (started|passed|failed|skipped)\b")
    started, finished = [], {}
    for match in re.finditer(pattern, text, re.MULTILINE):
        first, second, third, fourth, status = match.groups()
        name = (first or third) + "." + (second or fourth)
        if status == "started":
            started.append(name)
        else:
            require(name not in finished, "Repeated terminal test observation: " + name)
            finished[name] = status
    expected = expected_tests()
    require(set(started) == expected and len(started) == len(expected) and set(finished) == expected,
            "Selected XCTest method inventory is incomplete or changed")
    require(all(status == "passed" or (name == ALLOWED_SKIP and status == "skipped")
                for name, status in finished.items()), "Selected tests failed or an unapproved test was skipped")
    return {"passed": sorted(name for name, status in finished.items() if status == "passed"),
            "skipped": sorted(name for name, status in finished.items() if status == "skipped")}


def positive_control(text, exit_code):
    require(type(exit_code) is int and exit_code == 66 and "WARNING: ThreadSanitizer: data race" in text
            and "ThreadSanitizerRace.c:" in text and "unprotected" in text,
            "Intentional race was not detected with the expected exit code and source attribution")


def invoke(command):
    return subprocess.check_output([str(value) for value in command], text=True, stderr=subprocess.STDOUT)


def instrumentation(objects, binaries):
    require(objects and binaries, "Missing retained runtime objects or XCTest binaries")
    observations = []
    for path in objects:
        symbols = invoke(["xcrun", "nm", "-u", path])
        require("__tsan_read" in symbols and "__tsan_write" in symbols,
                "DefaultStrings object lacks sanitizer read/write instrumentation")
        observations.append({"path": str(path), "sha256": sha(path), "symbols": symbols})
    for path in binaries:
        dependencies = invoke(["xcrun", "otool", "-L", path])
        require("libclang_rt.tsan_osx_dynamic.dylib" in dependencies,
                "XCTest binary does not link Thread Sanitizer")
        observations.append({"path": str(path), "sha256": sha(path), "dependencies": dependencies})
    return observations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--snapshot", type=Path)
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--input-snapshot", type=Path)
    parser.add_argument("--scratch-directory", type=Path)
    parser.add_argument("--test-log", type=Path)
    parser.add_argument("--control-log", type=Path)
    parser.add_argument("--control-exit-code", type=int)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.snapshot:
            args.snapshot.parent.mkdir(parents=True, exist_ok=True)
            args.snapshot.write_text(json.dumps(source_inputs(), indent=2, sort_keys=True) + "\n")
            print("Sanitizer source inputs recorded")
            return 0
        require(all(value is not None for value in (args.input_snapshot, args.scratch_directory,
                    args.test_log, args.control_log, args.control_exit_code, args.report)), "Missing check inputs")
        frozen = json.loads(args.input_snapshot.read_text())
        require(frozen == source_inputs(), "Sources changed during sanitizer qualification")
        positive_control(args.control_log.read_text(), args.control_exit_code)
        tests = test_observations(args.test_log.read_text())
        scratch = args.scratch_directory.resolve()
        objects = sorted(scratch.rglob("DefaultStrings*.o"))
        binaries = sorted(path for bundle in scratch.rglob("*.xctest")
                          if bundle.is_dir() for path in (bundle / "Contents/MacOS").glob("*") if path.is_file())
        artifacts = instrumentation(objects, binaries)
        report = {"scope": "selected-macos-thread-sanitizer-tests", "status": "passed", "releaseParity": False,
                  "compiler": invoke(["swift", "--version"]).strip(), "hostOS": platform.mac_ver()[0],
                  "processArchitecture": platform.machine(), "sourceInputs": frozen, "sourceInputsRevalidated": True,
                  "tests": tests, "positiveControlExitCode": args.control_exit_code,
                  "testLogSHA256": sha(args.test_log), "controlLogSHA256": sha(args.control_log), "artifacts": artifacts,
                  "limits": "Selected tests on this macOS host only; no race-freedom, minimum compiler/OS, iOS, Intel or hosted-CI claim."}
        require(frozen == source_inputs(), "Sources changed during artifact inspection")
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"status": "passed", "passed": len(tests["passed"]), "skipped": len(tests["skipped"]),
                          "instrumentedRuntimeObjects": len(objects), "testBinaries": len(binaries), "releaseParity": False}))
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Sanitizer qualification refused: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
