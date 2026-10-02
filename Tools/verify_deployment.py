#!/usr/bin/env python3
"""Compile Apple deployment-floor consumers and inspect their actual Mach-O files.

Development-only: uses Python's standard library, Xcode SDKs, and direct swiftc.
No package resolution, third-party tools, XCTest, signing, or device deployment.
Generated binaries and complete command evidence remain in the output directory.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_NAME = "lokalized_swift"
TARGETS = (
    ("macos-arm64", "macosx", "arm64-apple-macosx12.0", "arm64", "MACOS", "12.0"),
    ("macos-x86_64", "macosx", "x86_64-apple-macosx12.0", "x86_64", "MACOS", "12.0"),
    ("ios-device-arm64", "iphoneos", "arm64-apple-ios15.0", "arm64", "IOS", "15.0"),
    ("ios-simulator-arm64", "iphonesimulator", "arm64-apple-ios15.0-simulator", "arm64", "IOSSIMULATOR", "15.0"),
)
CONSUMER = '''import Foundation
import Lokalized

let composed: ExactString = "\\u{00E9}"
let decomposed: ExactString = "e\\u{0301}"
precondition(composed != decomposed)
precondition(Set([composed, decomposed]).count == 2)
precondition(ExactString("\\u{10000}") < ExactString("\\u{E000}"))
precondition(ExactString("👩‍💻").utf16Count == 5)
precondition(Gender.masculine.rawValue == "GENDER_MASCULINE")
precondition(Gender.masculine.displayName == "MASCULINE")
precondition(Phonetic.allCases.count == 16)
precondition(BidiIsolation.disabled.rawValue == "none")
precondition(LocaleMatchType.noMatch.rawValue == "none")
let limits = try TranslationRuntimeLimits(maximumCompactExponent: 4_096)
precondition(limits.maximumCompactExponent == 4_096)
precondition(limits.maximumNumberPrecision == 1_024)
do {
    _ = try TranslationRuntimeLimits(maximumCompactExponent: 4_097)
    fatalError("Invalid runtime limits were accepted")
} catch is TranslationRuntimeLimits.ValidationError {}
precondition(BuildMetadata.current.producerImplementation == "lokalized-swift")
let model = try LocalizedString(key: composed, translation: "Hello")
let defined = try LocalizedStringLoader.defineCatalog([model], locale: "en")
let parsed = try LocalizedStringLoader.parse(#"{"é":"Hello","e\\u0301":"Other"}"#, locale: "en", source: "consumer")
precondition(parsed.strings.count == 2 && parsed.strings.first == model)
let merged = try LocalizedStringLoader.mergeParsedStringsFiles([defined, parsed])
precondition(merged.originsByKey[composed] == ["<defined>", "consumer"])
let exact = try ExactDecimal("1.00")
let operands = try PluralOperands(.decimal(exact))
precondition(operands.v == 2 && operands.w == 0)
let cardinal = try Cardinality.forNumber(.integer(1), locale: "en")
let scaledCardinal = try Cardinality.forOperands(operands, locale: "en")
let ordinal = try Ordinality.forNumber(.integer(2), locale: "en")
let ranged = try Cardinality.forRange(.one, .other, locale: "fr")
precondition(cardinal == .one && scaledCardinal == .other && ordinal == .two && ranged == .other)
precondition(NumericValue.float(0.1).description == "0.1")
let hebrew = try LocaleTag("iw-IL")
precondition(hebrew.tag == "he-IL" && hebrew.isRightToLeft)
let taiwan = try LocaleTag("zh-TW")
precondition(taiwan.likelySubtag == "zh-Hant-TW")
let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr", "zh-Hant"], fallbackLocale: "en")
let direct = try matcher.matchFor("fr")
precondition(direct.locale == "fr" && direct.matchType == .exact && direct.isMatch)
let retained = try matcher.validateSuppliedMatch(direct)
precondition(retained === direct)
let ranges = try matcher.parseLanguageRanges("fr;q=0.8, en;q=0.7")
let weighted = try matcher.matchFor(ranges)
precondition(weighted.locale == "fr" && weighted.effectiveWeight == 0.8)
let likely = try matcher.bestMatchFor(taiwan)
let malformedHeader = try matcher.bestMatchForAcceptLanguage("fr;q=abc")
precondition(likely == "zh-Hant" && malformedHeader == "en")
let equivalentRanges = try matcher.parseLanguageRanges("iw")
precondition(equivalentRanges.map(\\.range) == ["iw", "he"])
let rootLocale = LocaleTag.forLanguageTag("und")
let namedUnd = LocaleTag.forLanguageTag("UND")
precondition(rootLocale.tag == namedUnd.tag && rootLocale != namedUnd)
let typedMatcher = try DefaultLocaleMatcher(supportedLocales: [namedUnd], fallbackLocale: rootLocale)
precondition(typedMatcher.fallbackLocaleTag == namedUnd)
let typedMatch = try typedMatcher.matchFor([LanguageRange("*")])
precondition(typedMatch.localeTag == namedUnd && typedMatch.fallbackLocaleTag == namedUnd)
struct DisplayValue: PlaceholderConvertible {
    func lokalizedDescription(maximumCharacters: Int?) throws -> String {
        let text = "app"
        if let maximumCharacters, maximumCharacters < text.utf16.count {
            throw TranslationEvaluationError(kind: .invalidArgument, message: "Display budget exceeded")
        }
        return text
    }
}
func acceptsSendable<T: Sendable>(_ value: T) {}
let rawSnapshot: [ExactString: PlaceholderValue] = [
    "name": .text("Ada"), "count": PlaceholderValue(Int32(2)),
    "precise": PlaceholderValue(exact), "operands": PlaceholderValue(operands),
    "gender": .languageForm(.gender(.feminine)), "custom": .custom(DisplayValue()), "null": .null
]
acceptsSendable(rawSnapshot)
let resolver: PhoneticResolver = { term, locale in
    precondition(term == "apple" && locale.tag == "en")
    return .vowel
}
let phonetic = try resolver("apple", LocaleTag("en"))
precondition(phonetic == .vowel)
let leaf = TranslationEvaluationError(kind: .expression, message: "Leaf")
let contextual = TranslationEvaluationError(kind: .expression, message: "Context", cause: leaf)
precondition((contextual.cause as? TranslationEvaluationError) === leaf)
let enRuntime = try LocaleTag("en")
let frRuntime = try LocaleTag("fr")
let requestedRuntime = try LocaleTag("fr-CA")
let runtimeCatalogs: [LocaleTag: LocalizedCatalog] = [
    enRuntime: .init(strings: try LocalizedStringLoader.parse(#"{"greeting":"Hello {{name}}","other":"English"}"#, locale: "en").strings),
    frRuntime: .init(strings: try LocalizedStringLoader.parse(#"{"other":"Français"}"#, locale: "fr").strings)
]
let runtime = try DefaultStrings(configuration: StringsConfiguration(localizedStringSupplier: { runtimeCatalogs },
    localeSupplier: { _ in requestedRuntime }, fallbackLocale: enRuntime))
acceptsSendable(runtime)
let greeting = try runtime.getResult("greeting", placeholders: ["name": .text("Ada")])
precondition(greeting.translation == "Hello Ada" && greeting.status == .translated)
precondition(greeting.lookupLocale == requestedRuntime && greeting.resolvedLocale == enRuntime)
precondition(greeting.attemptedLocales.map(\\.tag) == ["fr-CA", "fr", "en"])
precondition(greeting.localeMatchResult?.localeTag == frRuntime)
let missingRuntimeKeys = try runtime.getMissingKeys(sourceLocale: enRuntime, targetLocale: frRuntime)
precondition(missingRuntimeKeys == ["greeting"])
let suppliedRuntimeMatch = try runtime.matchFor(frRuntime)
let retainedRuntime = try runtime.getResult("greeting", placeholders: ["name": .text("Ada")],
    options: .forLocaleMatch(suppliedRuntimeMatch))
precondition(retainedRuntime.localeMatchResult === suppliedRuntimeMatch)
let observerMarker = TranslationEvaluationError(kind: .invalidState, message: "observer marker")
let observer = TranslationFallbackObserver { event in
    precondition(event.key == "greeting" && event.resolvedLocale == enRuntime)
    precondition(event.precedingFailures.map(\\.locale) == [requestedRuntime, frRuntime])
    throw observerMarker
}
do {
    _ = try runtime.get("greeting", placeholders: ["name": .text("Ada")],
        options: TranslationOptions(translationFallbackObserver: observer))
    fatalError("Observer was not called")
} catch { precondition((error as? TranslationEvaluationError) === observerMarker) }
let returned = try runtime.getResult("missing", options: TranslationOptions(
    translationFailureHandler: TranslationFailureHandler { _ in .returnString("{{verbatim}}") }))
precondition(returned.translation == "{{verbatim}}" && returned.status == .returnedString)
precondition(returned.failureReason == .missingTranslation && returned.cause == nil)
let isolated = try runtime.get("greeting", placeholders: ["name": .text("Ada")],
    options: TranslationOptions(bidiIsolation: .always))
precondition(isolated == "Hello \\u{2068}Ada\\u{2069}")
let throwingOptions = try TranslationOptions(translationFailureHandler: .throwException())
let ui = StringsDisplayAdapter(runtime, errorDisplayPolicy: .custom { failure in
    precondition(failure.error is MissingTranslationError && failure.options == throwingOptions)
    return "Unavailable"
})
precondition(ui.get("missing", options: throwingOptions) == "Unavailable")
let streamCatalog = try LocalizedStringLoader.parse(InputStream(data: Data(#"{"stream":"bytes"}"#.utf8)), locale: "en")
precondition(streamCatalog.strings.first?.translation == "bytes")
let localDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lokalized-deployment-" + UUID().uuidString)
try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: localDirectory) }
let englishFile = localDirectory.appendingPathComponent("en")
try Data(#"{"local":"English"}"#.utf8).write(to: englishFile)
try Data(#"{"local":"French"}"#.utf8).write(to: localDirectory.appendingPathComponent("fr.JSON"))
let localFiles = try LocalizedStringLoader.loadFromDirectory(localDirectory)
precondition(Set(localFiles.keys) == [enRuntime, frRuntime])
let singleFile = try LocalizedStringLoader.parse(file: englishFile, locale: "en")
let explicitFiles = try LocalizedStringLoader.loadFromResources([enRuntime: englishFile])
precondition(singleFile.strings == explicitFiles[enRuntime]?.strings)
let preferredLanguage = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(["invalid_tag", "fr-CA", "en"], using: runtime)
precondition(preferredLanguage.localeTag == frRuntime)
let appleLanguage = try PreferredLanguageChooser.chooseAppleLocale(using: runtime)
precondition(appleLanguage.fallbackLocaleTag == enRuntime)
let manifestFiles: [ExactString: StringsManifestFile] = [
    "en": .init(url: "en.json", sha256: String(repeating: "a", count: 64), decodedBytes: 10),
    "fr": .init(url: "../fr.json", sha256: String(repeating: "b", count: 64))
]
let manifestIdentity = try LocalizedStringLoader.computeCatalogIdentity(.init(
    catalogVersion: "consumer-v1", resolvedFallbackLocale: "en",
    localeToSha256: manifestFiles.mapValues(\\.sha256)))
let manifestClaim = StringsManifestV1(catalogVersion: manifestIdentity.catalogVersion,
    catalogFingerprint: manifestIdentity.catalogFingerprint, fallbackLocale: "en",
    baseUrl: "https://cdn.example/catalogs/v1/", files: manifestFiles)
let validatedManifest = try LocalizedStringLoader.validateStringsManifest(manifestClaim)
let projectedIdentity = LocalizedStringLoader.catalogIdentityInputFor(validatedManifest)
let recomputedManifestIdentity = try LocalizedStringLoader.computeCatalogIdentity(projectedIdentity)
precondition(recomputedManifestIdentity == manifestIdentity)
let canonicalIdentity = try LocalizedStringLoader.catalogIdentityBytes(projectedIdentity)
precondition(canonicalIdentity.first == 123 && canonicalIdentity.last == 125)
let manifestConfiguration = try LocalizedStringLoader.localeConfigurationForManifest(validatedManifest)
precondition(manifestConfiguration.fallbackLocale == "en" && Set(manifestConfiguration.supportedLocales) == ["en", "fr"])
let manifestChain = try LocalizedStringLoader.chain(validatedManifest, lookupLocale: "fr-CA")
let manifestFetches = try LocalizedStringLoader.fetchSet(validatedManifest, lookupLocale: "fr-CA")
precondition(manifestChain == ["fr-CA", "fr", "en"])
precondition(manifestFetches.map(\\.locale) == ["fr", "en"])
precondition(manifestFetches.map(\\.url) == ["https://cdn.example/catalogs/fr.json", "https://cdn.example/catalogs/v1/en.json"])
precondition(manifestFetches.last?.expectedDecodedBytes == 10)
print("Lokalized deployment consumer passed")
'''


class VerificationError(RuntimeError):
    pass


def invoke(report, command, label, allowed_exit_codes=(0,)):
    print(label, file=sys.stderr, flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    report["commands"].append({
        "label": label, "arguments": [str(value) for value in command],
        "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
    })
    if result.returncode not in allowed_exit_codes:
        raise VerificationError(f"{label} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def source_files(module):
    files = sorted((ROOT / "Sources" / module).rglob("*.swift"))
    if not files:
        raise VerificationError(f"No Swift source files for {module}")
    return files


def source_hashes(modules):
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for files in modules.values() for path in files}


def normalized_version(version):
    values = tuple(int(value) for value in version.split("."))
    return values + (0,) * (3 - len(values))


def dependency_kind(name):
    if name in ("@rpath/libLokalized.dylib", "@rpath/libLokalizedConformanceSupport.dylib"):
        return "local-source-module"
    if name.startswith(("/System/Library/Frameworks/", "/usr/lib/")):
        return "apple-system"
    if re.fullmatch(r"@rpath/libswift[^/]+\.dylib", name):
        return "apple-swift-runtime"
    raise VerificationError(f"Unexpected runtime dependency: {name}")


def inspect_binary(report, binary, target):
    name, _, triple, architecture, expected_platform, minimum = target
    build = invoke(report, ["xcrun", "vtool", "-show-build", str(binary)], f"Inspect floor: {name}/{binary.name}")
    platforms = re.findall(r"\bplatform\s+(\S+)", build)
    versions = re.findall(r"\bminos\s+([\d.]+)", build)
    if platforms != [expected_platform] or len(versions) != 1 or normalized_version(versions[0]) != normalized_version(minimum):
        raise VerificationError(f"Wrong Mach-O deployment floor for {binary}: platforms={platforms}, minimums={versions}")
    architectures = invoke(report, ["xcrun", "lipo", "-archs", str(binary)], f"Inspect architecture: {name}/{binary.name}").strip().split()
    if architectures != [architecture]:
        raise VerificationError(f"Wrong Mach-O architecture for {binary}: {architectures}")
    linked = invoke(report, ["xcrun", "otool", "-L", str(binary)], f"Inspect dependencies: {name}/{binary.name}")
    dependencies = []
    own_install_name = f"@rpath/{binary.name}" if binary.suffix == ".dylib" else None
    for line in linked.splitlines()[1:]:
        match = re.match(r"\s+(.+?)\s+\(compatibility version", line)
        if match:
            dependency = match.group(1)
            if dependency != own_install_name:
                dependencies.append({"path": dependency, "kind": dependency_kind(dependency)})
    if not dependencies:
        raise VerificationError(f"No dependency records found for {binary}")
    return {"path": str(binary), "targetTriple": triple, "architecture": architecture,
            "platform": platforms[0], "minimumOS": versions[0], "dependencies": dependencies,
            "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}


def compile_target(report, swiftc, sdk, target, modules, output):
    name, _, triple, _, _, _ = target
    directory = output / name
    directory.mkdir(parents=True, exist_ok=True)
    cache = output / "ModuleCache" / name
    cache.mkdir(parents=True, exist_ok=True)
    common = [swiftc, "-swift-version", "6", "-package-name", PACKAGE_NAME,
              "-target", triple, "-sdk", str(sdk), "-module-cache-path", str(cache)]
    binaries = []
    for module in ("Lokalized", "LokalizedConformanceSupport"):
        binary = directory / f"lib{module}.dylib"
        command = common + ["-parse-as-library", "-emit-library", "-emit-module", "-module-name", module,
                            "-emit-module-path", str(directory / f"{module}.swiftmodule"),
                            "-Xlinker", "-install_name", "-Xlinker", f"@rpath/{binary.name}", "-o", str(binary)]
        if module == "LokalizedConformanceSupport":
            command += ["-I", str(directory), "-L", str(directory), "-lLokalized"]
        command += [str(path) for path in modules[module]]
        invoke(report, command, f"Compile and link {name}: {module}")
        binaries.append(inspect_binary(report, binary, target))

    consumer_source = directory / "Consumer.swift"
    consumer_source.write_text(CONSUMER, encoding="utf-8")
    for module, sources, libraries in (
        ("LokalizedDeploymentConsumer", [consumer_source], ["-lLokalized"]),
        ("LokalizedConformance", modules["LokalizedConformance"], ["-lLokalizedConformanceSupport", "-lLokalized"]),
    ):
        binary = directory / module
        command = common + ["-module-name", module, "-I", str(directory), "-L", str(directory)] + libraries
        command += ["-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o", str(binary)]
        command += [str(path) for path in sources]
        invoke(report, command, f"Import and link {name}: {module}")
        binaries.append(inspect_binary(report, binary, target))
    return {"name": name, "triple": triple, "status": "compiled-imported-linked-inspected",
            "binaries": binaries, "runtimeExecution": "not executed"}


def verify(report, args, output):
    if platform.system() != "Darwin":
        raise VerificationError("This Apple SDK deployment check requires macOS and Xcode")
    swiftc = invoke(report, ["xcrun", "--find", "swiftc"], "Locate selected Xcode Swift compiler").strip()
    compiler = invoke(report, [swiftc, "--version"], "Identify selected compiler").strip()
    match = re.search(r"Swift version (\d+)\.(\d+)", compiler)
    if not match or tuple(map(int, match.groups())) < (6, 2):
        raise VerificationError(f"Swift 6.2 or later is required: {compiler}")
    compiler_pair = tuple(map(int, match.groups()))
    report.update({"compiler": compiler, "compilerTrack": args.compiler_track,
                   "minimumCompilerExecuted": compiler_pair == (6, 2), "languageMode": "6",
                   "packageName": PACKAGE_NAME,
                   "host": {"architecture": platform.machine(), "macOS": platform.mac_ver()[0]},
                   "minimumOSRuntimeExecution": {"macOS12": "not verified", "iOS15": "not verified"}})
    if args.compiler_track == "minimum" and compiler_pair != (6, 2):
        raise VerificationError(f"The minimum-compiler check must execute Swift 6.2: {compiler}")
    sdks = {}
    for sdk_name in dict.fromkeys(target[1] for target in TARGETS):
        path = invoke(report, ["xcrun", "--sdk", sdk_name, "--show-sdk-path"], f"Locate SDK: {sdk_name}").strip()
        version = invoke(report, ["xcrun", "--sdk", sdk_name, "--show-sdk-version"], f"Identify SDK: {sdk_name}").strip()
        sdks[sdk_name] = {"path": path, "version": version}
    report["sdks"] = sdks
    modules = {name: source_files(name) for name in ("Lokalized", "LokalizedConformanceSupport", "LokalizedConformance")}
    hashes = source_hashes(modules)
    report["sourceSha256"] = hashes
    reference = args.reference.resolve()
    inputs = [Path(__file__).resolve(), ROOT / "Package.swift",
              reference / "baseline.json", reference / "behavioral-vectors.json",
              reference / "materialized-fixtures.json", reference / "locale-goldens.json",
              reference / "cldr-locale-data.json", reference / "cldr-plural-data.json",
              reference / "cldr-conformance-vectors.json",
              reference / "manifest-contract-vectors.json", reference / "manifest-contract-lock.json",
              ROOT / "Tools/verify_manifest_contract_report.py",
              reference / "manifest-url-goldens.json", ROOT / "Tools/verify_manifest_urls.py"]
    input_hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    report["inputSha256"] = input_hashes
    report["consumerSourceSha256"] = hashlib.sha256(CONSUMER.encode("utf-8")).hexdigest()
    report["referenceDirectory"] = str(reference)
    for target in TARGETS:
        compiled = compile_target(report, swiftc, sdks[target[1]]["path"], target, modules, output)
        report["targets"].append(compiled)
        if target[0] == "macos-arm64" and platform.machine() == "arm64":
            directory = output / target[0]
            consumer = invoke(report, [str(directory / "LokalizedDeploymentConsumer")], "Run arm64 macOS consumer on host")
            if consumer.strip() != "Lokalized deployment consumer passed":
                raise VerificationError("Deployment consumer returned an unexpected observation")
            self_test = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--self-test"], "Run arm64 macOS conformance self-tests on host"))
            if self_test.get("status") != "passed" or self_test.get("checks", 0) <= 0:
                raise VerificationError(f"Conformance self-tests did not pass: {self_test}")
            inventory = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--inventory", "--reference", str(reference)], "Run arm64 macOS frozen-corpus inventory on host"))
            if inventory.get("status") != "inventory" or inventory.get("totalCases", 0) <= 0:
                raise VerificationError(f"Conformance inventory was invalid: {inventory}")
            data_audits = {}
            for command, name in (("--plural-data", "pluralData"), ("--locale-data", "localeData")):
                audit = json.loads(invoke(report, [str(directory / "LokalizedConformance"), command, "--reference", str(reference)],
                                          f"Run arm64 macOS {name} qualification on host"))
                if audit.get("status") != "passed" or audit.get("checks", 0) <= 0 or audit.get("failedChecks") != 0:
                    raise VerificationError(f"{name} qualification failed: {audit}")
                data_audits[name] = audit
            compiled["runtimeExecution"] = {"status": "passed-on-host", "consumer": "passed", "selfTests": self_test,
                                             "inventory": inventory, "dataAudits": data_audits}
            components = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--resolution-components",
                                                    "--reference", str(reference)],
                                          "Run arm64 macOS single-catalog component projections on host"))
            if (components.get("status") != "passed" or components.get("scope") != "single-catalog-component-projection"
                    or components.get("eligibleIDsSHA256") != "fe8cbe90b8c000e88f094edb980b034ba86205ceeae65d6b460c2b825e24b467"
                    or len(components.get("eligibleComponentIDs", [])) != 578
                    or components.get("projectedComponentsPassed") != components.get("eligibleComponentIDs")
                    or components.get("failed") != []):
                raise VerificationError(f"Resolution component qualification failed: {components}")
            compiled["runtimeExecution"]["resolutionComponents"] = components
            runtime_audit = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--audit",
                                                       "--reference", str(reference)],
                                             "Run arm64 macOS whole-runtime corpus audit on host", allowed_exit_codes=(1,)))
            passed = runtime_audit.get("runtimePassed", [])
            pending = runtime_audit.get("unimplemented", [])
            passed_digest = hashlib.sha256("".join(value + "\n" for value in sorted(passed)).encode()).hexdigest()
            pending_digest = hashlib.sha256("".join(value + "\n" for value in sorted(pending)).encode()).hexdigest()
            if (runtime_audit.get("status") != "incomplete" or runtime_audit.get("totalCases") != 2381
                    or len(passed) != 2197 or len(set(passed)) != 2197
                    or passed_digest != "2c4848b0b481d01523e11813efbf5dd874cc5c75ca8b15aaa41e5ff5f25ee76f"
                    or len(pending) != 184 or len(set(pending)) != 184
                    or pending_digest != "618df840c1a5bb7808f0e747ad8c18f5f90532d2676ea05454d9efe0f41b7d76"
                    or runtime_audit.get("failed") != [] or runtime_audit.get("failures") != []
                    or runtime_audit.get("nativeRepresentationMapped") != []):
                raise VerificationError("Whole-runtime audit differs from the retained exact-ID main-corpus ratchet")
            compiled["runtimeExecution"]["wholeRuntimeAudit"] = runtime_audit
            loader = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--loader",
                                                "--reference", str(reference)], "Run arm64 macOS native-filesystem observations"))
            if (loader.get("status") != "passed" or loader.get("scope") != "native-filesystem-full-observation"
                    or loader.get("eligibleIDsSHA256") != "6c6043d0326a9a524690c485292cc2cd748161504fbaa5c0c7fcb97d91e16991"
                    or len(loader.get("eligibleIDs", [])) != 145 or loader.get("runtimePassed") != loader.get("eligibleIDs")
                    or loader.get("failed") != [] or len(loader.get("pendingCarriers", [])) != 164
                    or len(loader.get("adaptationObservations", [])) != 5):
                raise VerificationError("Native-filesystem observations differ from the retained local-loader ratchet")
            compiled["runtimeExecution"]["nativeFilesystemAudit"] = loader
            manifest_path = directory / "manifest-contract-report.json"
            manifest = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--manifest-contract",
                "--reference", str(reference), "--report", str(manifest_path)],
                "Run arm64 macOS manifest contract qualification on host"))
            from verify_manifest_contract_report import report_check
            report_check(manifest_path, reference)
            compiled["runtimeExecution"]["manifestContract"] = manifest
            urls_path = directory / "manifest-url-report.json"
            urls = json.loads(invoke(report, [str(directory / "LokalizedConformance"), "--manifest-urls",
                "--reference", str(reference), "--report", str(urls_path)],
                "Run arm64 macOS frozen manifest URL qualification on host"))
            from verify_manifest_urls import report_check as url_report_check
            url_report_check(urls_path, reference)
            compiled["runtimeExecution"]["manifestURLs"] = urls
            if platform.mac_ver()[0].split(".")[0] == "12":
                report["minimumOSRuntimeExecution"]["macOS12"] = "verified by arm64 consumer and development harness"
    final_modules = {name: source_files(name) for name in modules}
    if hashes != source_hashes(final_modules):
        raise VerificationError("Swift sources changed during verification; rerun against a stable source snapshot")
    if input_hashes != {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}:
        raise VerificationError("Verification inputs changed during execution; rerun against a stable input snapshot")
    report["status"] = "passed"
    report["coverage"] = "Apple SDK compilation, module import, linking, Mach-O inspection; host arm64 execution when available"
    report["runtimeDependencies"] = "local source modules and Apple system/Swift runtime only"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, help="Retain generated binaries here; default is a fresh /private/tmp directory")
    parser.add_argument("--report", type=Path, help="Write evidence here; default is OUTPUT/deployment-report.json")
    parser.add_argument("--compiler-track", choices=("minimum", "current"), default="current")
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    args = parser.parse_args()
    output = args.output_directory.resolve() if args.output_directory else Path(tempfile.mkdtemp(prefix="lokalized-deployment-", dir="/private/tmp"))
    output.mkdir(parents=True, exist_ok=True)
    report_path = args.report.resolve() if args.report else output / "deployment-report.json"
    report = {"status": "running", "startedAtUTC": datetime.now(timezone.utc).isoformat(),
              "outputDirectory": str(output), "targets": [], "commands": []}
    try:
        verify(report, args, output)
    except (OSError, ValueError, VerificationError) as error:
        report["status"] = "failed"
        report["failure"] = str(error)
        print(f"Deployment verification failed: {error}", file=sys.stderr)
    report["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(report_path), "outputDirectory": str(output),
                      "compiledTargets": len(report["targets"]), "minimumCompilerExecuted": report.get("minimumCompilerExecuted", False)}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
