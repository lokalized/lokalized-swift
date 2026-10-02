#!/usr/bin/env python3
"""Compile actual public Swift consumers to qualify nonoptional contracts.

Development-only, standard-library Python; emits a temporary current-source
module, then requires one positive consumer to compile and each negative
consumer to fail for its intended nil/type mismatch. Never reads expected
conformance observations and never writes the package's shared build directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile


POSITIVE = r'''import Lokalized
let en = try LocaleTag("en")
let handler = TranslationFailureHandler { _ in .returnString("fallback") }
let policy = TranslationFallbackPolicy { _, _, _ in true }
let observer = TranslationFallbackObserver { _ in }
let resolver: PhoneticResolver = { _, _ in .other }
let catalogs: LocalizedStringSupplier = { [:] }
let locale: LocaleSupplier = { _ in en }
let match: LocaleMatchSupplier = { matcher in try matcher.matchFor("en") }
let values: PlaceholderValues = ["name": .text("Ava"), "explicitNull": .null]
let options = try TranslationOptions(locale: en, bidiIsolation: .disabled,
    translationFailureHandler: handler, translationFallbackPolicy: policy,
    translationFallbackObserver: observer)
let emptyOptions = TranslationOptions()
let configuration = StringsConfiguration(localizedStringSupplier: catalogs,
    localeSupplier: locale, fallbackLocale: en, phoneticResolver: resolver)
func construct() throws { _ = try DefaultStrings(configuration: configuration) }
func consume(_ strings: any Strings) throws {
    _ = try strings.get("hello")
    _ = try strings.get("hello", placeholders: values, options: options)
    _ = try strings.getResult("hello", options: emptyOptions)
}
'''

# Each example changes one promised nonoptional type and has no unrelated
# source dependencies. The diagnostic token is checked as well as exit status.
NEGATIVE = {
    "failure-handler-nil": ("let value = TranslationFailureHandler { _ in nil }", "TranslationFailureResponse"),
    "fallback-policy-nil": ("let value = TranslationFallbackPolicy { _, _, _ in nil }", "Bool"),
    "phonetic-resolver-nil": ("let value: PhoneticResolver = { _, _ in nil }", "Phonetic"),
    "catalog-supplier-nil": ("let value: LocalizedStringSupplier = { nil }", "LocalizedCatalog"),
    "locale-supplier-nil": ("let value: LocaleSupplier = { _ in nil }", "LocaleTag"),
    "locale-match-supplier-nil": ("let value: LocaleMatchSupplier = { _ in nil }", "LocaleMatchResult"),
    "replacement-string-nil": ("let value = TranslationFailureResponse.returnString(nil)", "String"),
    "placeholder-value-nil": ("let value: PlaceholderValues = [\"name\": nil]", "PlaceholderValue"),
}


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="run the qualification (also the default)")
    parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--target", help="explicit Swift target; defaults to this Mac's architecture with macOS 12")
    parser.add_argument("--sdk", type=Path, help="SDK directory; defaults to xcrun macosx SDK")
    parser.add_argument("--report", type=Path, help="save the complete JSON evidence report")
    args = parser.parse_args()
    compiler = shutil.which(args.swiftc)
    if not compiler:
        parser.error(f"Swift compiler not found: {args.swiftc}")
    root = args.source_root.resolve()
    source_paths = sorted((root / "Sources" / "Lokalized").rglob("*.swift"))
    if not source_paths:
        parser.error(f"No library sources under {root}")
    if not args.target and platform.system() != "Darwin":
        parser.error("Apple qualification requires macOS, or an explicit --target and --sdk")
    target = args.target or f"{platform.machine()}-apple-macosx12.0"
    sdk = args.sdk
    if sdk is None:
        sdk_result = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
        if sdk_result.returncode:
            parser.error(sdk_result.stderr.strip())
        sdk = Path(sdk_result.stdout.strip())
    version = run([compiler, "--version"])
    report: dict = {"formatVersion": 1, "qualification": "native-public-nonoptional-contracts",
                    "compiler": version.stdout.strip(), "target": target, "sdk": str(sdk),
                    "sourceFiles": [], "positive": None, "negative": [], "passed": False}
    with tempfile.TemporaryDirectory(prefix="lokalized-callback-types-", dir="/private/tmp") as temporary:
        scratch = Path(temporary)
        sources: list[str] = []
        for path in source_paths:
            relative = path.relative_to(root)
            data = path.read_bytes()
            copied = scratch / relative
            copied.parent.mkdir(parents=True, exist_ok=True)
            copied.write_bytes(data)
            report["sourceFiles"].append({"path": str(relative), "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
            sources.append(str(copied))
        serialized = json.dumps(report["sourceFiles"], sort_keys=True, separators=(",", ":")).encode()
        report["sourceManifestSha256"] = hashlib.sha256(serialized).hexdigest()
        common = [compiler, "-swift-version", "6", "-target", target, "-sdk", str(sdk),
                  "-module-cache-path", str(scratch / "module-cache")]
        emitted = run(common + ["-parse-as-library", "-emit-module", "-module-name", "Lokalized",
                                "-package-name", "lokalized_swift", "-emit-module-path", str(scratch / "Lokalized.swiftmodule")] + sources)
        report["moduleCompilation"] = {"exitCode": emitted.returncode, "diagnostics": emitted.stdout + emitted.stderr}
        if emitted.returncode == 0:
            positive = scratch / "Positive.swift"
            positive.write_text(POSITIVE)
            outcome = run(common + ["-typecheck", "-I", str(scratch), str(positive)])
            report["positive"] = {"source": POSITIVE, "sourceSha256": hashlib.sha256(POSITIVE.encode()).hexdigest(),
                                  "exitCode": outcome.returncode, "diagnostics": outcome.stdout + outcome.stderr}
            for name, (body, token) in NEGATIVE.items():
                source = "import Lokalized\n" + body + "\n"
                file = scratch / f"{name}.swift"
                file.write_text(source)
                result = run(common + ["-typecheck", "-I", str(scratch), str(file)])
                diagnostics = result.stdout + result.stderr
                valid = result.returncode != 0 and "'nil' is not compatible with" in diagnostics and token in diagnostics
                report["negative"].append({"name": name, "source": source,
                    "sourceSha256": hashlib.sha256(source.encode()).hexdigest(), "requiredType": token,
                    "exitCode": result.returncode, "diagnostics": diagnostics, "passed": valid})
            report["passed"] = outcome.returncode == 0 and all(item["passed"] for item in report["negative"])
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"qualification": report["qualification"], "passed": report["passed"],
                      "positiveConsumers": 1 if report["positive"] else 0,
                      "negativeConsumers": len(report["negative"]), "sourceManifestSha256": report["sourceManifestSha256"]}))
    if not report["passed"]:
        if report["moduleCompilation"]["exitCode"]:
            print(report["moduleCompilation"]["diagnostics"])
        else:
            if report["positive"]["exitCode"]:
                print(report["positive"]["diagnostics"])
            for item in report["negative"]:
                if not item["passed"]:
                    print(f"{item['name']}: unexpected compilation outcome\n{item['diagnostics']}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
