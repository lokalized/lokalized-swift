#!/usr/bin/env python3
"""Build actual SwiftPM and Xcode resource consumers from a fresh source snapshot.

Standard-library Python and Apple developer tools only. No remote packages,
reference archives, signing, device installation, or generated runtime data.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def inputs():
    paths = [ROOT / "Package.swift", Path(__file__).resolve()]
    for directory in ("Sources", "Examples"):
        paths += [path for path in (ROOT / directory).rglob("*") if path.is_file()
                  and not any(part in (".build", ".swiftpm", "xcuserdata") for part in path.relative_to(ROOT).parts)]
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


def invoke(report, command, cwd, env=None):
    print(command[0] + " " + next((value for value in command[1:] if value in ("build", "-scheme", "--qualify")), ""), file=sys.stderr, flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    report["commands"].append({"arguments": [str(value) for value in command], "cwd": str(cwd),
                               "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stderr[-6000:]}\n{result.stdout[-6000:]}")
    return result.stdout


def verify_privacy(resources, report):
    sdk_bundle = resources / "lokalized-swift_Lokalized.bundle"
    sdk_resources = sdk_bundle / "Contents/Resources" if (sdk_bundle / "Contents").is_dir() else sdk_bundle
    manifest = sdk_resources / "PrivacyInfo.xcprivacy"
    expected = ROOT / "Sources/Lokalized/PrivacyInfo.xcprivacy"
    if not manifest.is_file() or manifest.read_bytes() != expected.read_bytes():
        raise RuntimeError(f"Actual Lokalized SDK privacy manifest path/bytes differ: {manifest}")
    value = plistlib.loads(manifest.read_bytes())
    if value != {"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": [],
                 "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
                                                "NSPrivacyAccessedAPITypeReasons": ["0A2A.1"]}]}:
        raise RuntimeError("Packaged metadata wrapper declaration differs")
    report["privacyManifest"] = {"path": str(manifest), "sha256": hashlib.sha256(manifest.read_bytes()).hexdigest()}


def verify_resources(app, report):
    resources = app / "Contents/Resources" if (app / "Contents").is_dir() else app
    for name in ("en", "fr.JSON"):
        source = ROOT / "Examples/SharedCatalogs/Lokalized" / name
        destination = resources / "Lokalized" / name
        if not destination.is_file() or destination.read_bytes() != source.read_bytes():
            raise RuntimeError(f"Packaged resource path/bytes differ: {destination}")
    verify_privacy(resources, report)


def main(args):
    if platform.system() != "Darwin":
        raise RuntimeError("Apple packaged-consumer qualification requires macOS/Xcode")
    output = args.output_directory.resolve() if args.output_directory else Path(tempfile.mkdtemp(prefix="lokalized-local-delivery-", dir="/private/tmp"))
    output.mkdir(parents=True, exist_ok=True)
    report = {"status": "running", "startedAtUTC": datetime.now(timezone.utc).isoformat(),
              "outputDirectory": str(output), "commands": [], "targets": [],
              "runtimeCoverage": {"macOSHost": "not executed", "iOS": "not executed", "minimumOS": "not executed"}}
    path = args.report.resolve() if args.report else output / "local-delivery-report.json"
    try:
        original = inputs()
        report["inputSha256"] = original
        compiler = invoke(report, ["swift", "--version"], ROOT)
        report["compiler"] = compiler.strip()
        match = re.search(r"Swift version (\d+)\.(\d+)", compiler)
        if not match or tuple(map(int, match.groups())) < (6, 2):
            raise RuntimeError("Swift 6.2 or later required")
        report["minimumCompilerExecuted"] = tuple(map(int, match.groups())) == (6, 2)
        if args.compiler_track == "minimum" and not report["minimumCompilerExecuted"]:
            raise RuntimeError("Minimum compiler track must actually use Swift 6.2")
        snapshot = output / "lokalized-swift"
        snapshot.mkdir()
        shutil.copy2(ROOT / "Package.swift", snapshot / "Package.swift")
        for name in ("Sources", "Tests", "Examples"):
            shutil.copytree(ROOT / name, snapshot / name, ignore=shutil.ignore_patterns(".build", ".swiftpm", "xcuserdata"))
        # Same bytes serve both resource packaging recipes; avoid fixture drift.
        for name in ("en", "fr.JSON"):
            shared = snapshot / "Examples/SharedCatalogs/Lokalized" / name
            copied = snapshot / "Examples/SwiftPMCatalogConsumer/Sources/SwiftPMCatalogConsumer/Lokalized" / name
            if shared.read_bytes() != copied.read_bytes():
                raise RuntimeError("Example SwiftPM and app catalogs differ")
        import os
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(output / "ModuleCache")
        environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(output / "ModuleCache")
        example = snapshot / "Examples/SwiftPMCatalogConsumer"
        common = ["--disable-sandbox", "--scratch-path", str(output / "SwiftPMBuild"),
                  "--cache-path", str(output / "SwiftPMCache"), "--config-path", str(output / "SwiftPMConfig"),
                  "--security-path", str(output / "SwiftPMSecurity")]
        invoke(report, ["swift", "build"] + common, example, environment)
        bin_path = invoke(report, ["swift", "build"] + common + ["--show-bin-path"], example, environment).strip()
        observation = invoke(report, [str(Path(bin_path) / "SwiftPMCatalogConsumer")], example, environment).strip()
        if observation != "SwiftPM Bundle.module catalogs passed":
            raise RuntimeError("SwiftPM resource consumer did not qualify")
        report["swiftPM"] = {"status": "compiled-and-executed", "defaultIsolation": "MainActor",
                             "languageMode": "6", "resourceRecipe": '.copy("Lokalized")', "observation": observation}
        verify_privacy(Path(bin_path), report["swiftPM"])
        # Compile the same real resource/API consumer in Swift 5 language mode
        # against the unchanged Swift 6 library. This uses the selected compiler;
        # it does not claim support for a Swift 5 compiler.
        manifest = example / "Package.swift"
        original_manifest = manifest.read_text()
        manifest.write_text(original_manifest.replace(', swiftSettings: [.defaultIsolation(MainActor.self)]', '')
                            .replace('swiftLanguageModes: [.v6]', 'swiftLanguageModes: [.v5]'))
        swift5_common = [value.replace("SwiftPMBuild", "SwiftPMBuild5") for value in common]
        invoke(report, ["swift", "build"] + swift5_common, example, environment)
        swift5_bin = invoke(report, ["swift", "build"] + swift5_common + ["--show-bin-path"], example, environment).strip()
        swift5_observation = invoke(report, [str(Path(swift5_bin) / "SwiftPMCatalogConsumer")], example, environment).strip()
        if swift5_observation != "SwiftPM Bundle.module catalogs passed":
            raise RuntimeError("Swift 5 language-mode resource consumer did not qualify")
        report["swift5LanguageConsumer"] = {"status": "compiled-and-executed", "languageMode": "5",
                                           "libraryLanguageMode": "6", "compiler": compiler.strip(),
                                           "observation": swift5_observation}
        verify_privacy(Path(swift5_bin), report["swift5LanguageConsumer"])
        manifest.write_text(original_manifest)
        project = snapshot / "Examples/AppleLocalCatalogs/AppleLocalCatalogs.xcodeproj"
        for scheme, sdk, destination, expected_floor in (
            ("MacCatalogs", "macosx", "generic/platform=macOS", "12.0"),
            ("IOSCatalogs", "iphonesimulator", "generic/platform=iOS Simulator", "15.0"),
            ("IOSCatalogs", "iphoneos", "generic/platform=iOS", "15.0"),
        ):
            derived = output / ("Xcode-" + sdk)
            xcode_arguments = ["xcodebuild", "-project", str(project), "-scheme", scheme, "-configuration", "Debug",
                            "-sdk", sdk, "-destination", destination, "-derivedDataPath", str(derived),
                            "-packageCachePath", str(output / "XcodePackageCache"),
                            "-clonedSourcePackagesDirPath", str(output / "SourcePackages"),
                            "-disablePackageRepositoryCache", "-disableAutomaticPackageResolution", "-skipPackageUpdates",
                            "CODE_SIGNING_ALLOWED=NO"]
            settings_rows = json.loads(invoke(report, xcode_arguments + ["-showBuildSettings", "-json"], snapshot, environment))
            settings = next(row["buildSettings"] for row in settings_rows if row["target"] == scheme)
            expected_settings = {"SWIFT_VERSION": "6.0", "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                                 "SWIFT_APPROACHABLE_CONCURRENCY": "YES"}
            if any(settings.get(key) != value for key, value in expected_settings.items()):
                raise RuntimeError(f"Actual Xcode consumer Swift settings differ: {settings}")
            invoke(report, xcode_arguments + ["build"], snapshot, environment)
            product_directory = "Debug" if sdk == "macosx" else "Debug-" + sdk
            app = derived / "Build/Products" / product_directory / (scheme + ".app")
            binary = app / ("Contents/MacOS/" + scheme if sdk == "macosx" else scheme)
            target = {"scheme": scheme, "sdk": sdk, "app": str(app), "status": "compiled-and-packaged",
                      "languageMode": "6", "defaultIsolation": "MainActor", "approachableConcurrency": True,
                      "runtimeExecution": "not executed", "verifiedSwiftBuildSettings": expected_settings}
            verify_resources(app, target)
            build_info = invoke(report, ["xcrun", "vtool", "-show-build", str(binary)], snapshot)
            versions = re.findall(r"\bminos\s+([\d.]+)", build_info)
            if not versions or any(version != expected_floor for version in versions):
                raise RuntimeError(f"App deployment floors differ: {versions}")
            target["minimumOS"] = expected_floor
            target["binarySha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
            if sdk == "macosx":
                result = invoke(report, [str(binary), "--qualify"], snapshot, environment).strip()
                if result != "Packaged Apple catalogs passed":
                    raise RuntimeError("Packaged macOS app did not qualify actual Bundle.main")
                target["runtimeExecution"] = "passed-on-host"
                report["runtimeCoverage"]["macOSHost"] = platform.mac_ver()[0]
            report["targets"].append(target)
        if original != inputs():
            raise RuntimeError("Source/packaging inputs changed during verification; rerun on a stable snapshot")
        report["status"] = "passed"
        report["externalPackageDependencies"] = 0
    except Exception as error:
        report["status"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        report["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "report": str(path), "outputDirectory": str(output),
                      "packagedAppleTargets": len(report["targets"]), "minimumCompilerExecuted": report["minimumCompilerExecuted"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--compiler-track", choices=("minimum", "current"), default="current")
    try:
        main(parser.parse_args())
    except (RuntimeError, OSError, ValueError) as error:
        print(f"Local delivery verification refused: {error}", file=sys.stderr)
        sys.exit(1)
