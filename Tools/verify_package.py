#!/usr/bin/env python3
"""Verify zero package dependencies, declared floors, toolchain and scoped qualification reports.

Uses Python's standard library and the selected system Swift/Xcode toolchain only.
--offline-build compiles a fresh source copy with no resolver inputs or sibling repos.
It is not an OS-runtime test or a claim of completed localization functionality.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PLATFORMS = {"ios": "15.0", "macos": "12.0"}


def invoke(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def package_check(track):
    manifest = json.loads(invoke(["swift", "package", "--disable-sandbox", "dump-package"]))
    if manifest.get("dependencies") != []:
        raise RuntimeError("Lokalized must have zero external Swift package dependencies")
    if manifest.get("toolsVersion", {}).get("_version") != "6.2.0":
        raise RuntimeError("The minimum package tools version must be Swift 6.2")
    platforms = {p["platformName"]: p["version"] for p in manifest.get("platforms", [])}
    if platforms != EXPECTED_PLATFORMS:
        raise RuntimeError(f"Deployment declarations differ: {platforms}")
    if manifest.get("swiftLanguageVersions") != ["6"]:
        raise RuntimeError("Swift 6 language mode must be explicit")
    names = {t["name"] for t in manifest.get("targets", [])}
    for target in manifest.get("targets", []):
        if target["type"] in ("binary", "plugin") or target.get("pluginUsages"):
            raise RuntimeError("Consumer builds must not require plugins or binary packages")
        for dependency in target.get("dependencies", []):
            if "product" in dependency:
                raise RuntimeError("A target depends on an external package product")
            name = (dependency.get("byName") or dependency.get("target") or [None])[0]
            if name not in names:
                raise RuntimeError(f"Unknown non-local target dependency: {dependency}")
    version = invoke(["swift", "--version"]).strip()
    match = re.search(r"Swift version (\d+)\.(\d+)", version)
    if not match or tuple(map(int, match.groups())) < (6, 2):
        raise RuntimeError(f"Swift 6.2 or later required: {version}")
    if track == "minimum" and tuple(map(int, match.groups())) != (6, 2):
        raise RuntimeError(f"Minimum-compiler CI must actually use Swift 6.2: {version}")
    return {"status": "verified", "externalPackageDependencies": 0,
            "toolsVersion": "6.2.0", "declaredPlatforms": platforms,
            "compiler": version, "compilerTrack": track,
            "minimumCompilerExecuted": tuple(map(int, match.groups())) == (6, 2),
            "osRuntimeCoverage": "not measured by this check"}


def audit_check(path, reference):
    report = json.loads(path.read_text())
    corpus = json.loads((reference / "behavioral-vectors.json").read_text())
    fields = {"status", "corpusVersion", "totalCases", "requiredPortable", "runtimePassed",
              "nativeRepresentationMapped", "failed", "unimplemented", "failures"}
    if set(report) != fields or report["corpusVersion"] != corpus["behavioralVectorsVersion"]:
        raise RuntimeError("Audit fields or version differ from runner/frozen corpus contract")
    known = {case["id"] for case in corpus["cases"]}
    required = {case["id"] for case in corpus["cases"] if case["partition"] == "requiredPortableIds"}
    if report.get("totalCases") != len(known) or report.get("requiredPortable") != len(required):
        raise RuntimeError("Audit totals differ from frozen corpus")
    combined = set()
    for key in ("runtimePassed", "nativeRepresentationMapped", "failed", "unimplemented"):
        values = report.get(key)
        if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
            raise RuntimeError(f"Audit must enumerate exact case IDs in {key}")
        ids = set(values)
        if len(ids) != len(values) or ids & combined or not ids <= known:
            raise RuntimeError(f"Duplicate, cross-category or unknown case IDs in {key}")
        combined |= ids
    if combined != known:
        raise RuntimeError("Audit silently omitted corpus case IDs")
    if report.get("status") != "incomplete" or not report["unimplemented"]:
        raise RuntimeError("The main corpus remains incomplete; this CI gate cannot certify release parity")
    if report["failed"] or report["failures"] != []:
        raise RuntimeError("Implemented comparisons failed")
    if report["nativeRepresentationMapped"]:
        raise RuntimeError("Native callback/representation mappings remain unratified")
    implemented = {case["id"] for case in corpus["cases"]
                   if case["operation"] in ("languageForms", "parse", "define", "cardinalityForNumber",
                                            "cardinalityForOperands", "cardinalityForRange", "ordinalityForNumber",
                                            "ordinalityForOperands", "supportedCardinalitiesForLocale",
                                            "supportedOrdinalitiesForLocale", "matchFor", "acceptLanguage")}
    passes = set(report["runtimePassed"])
    digest = hashlib.sha256("".join(value + "\n" for value in sorted(passes)).encode()).hexdigest()
    if not implemented <= passes or len(passes) != 2197 or digest != "2c4848b0b481d01523e11813efbf5dd874cc5c75ca8b15aaa41e5ff5f25ee76f":
        raise RuntimeError("Whole-runtime passes differ from the retained exact 2,197-ID main-corpus ratchet")
    pending_digest = hashlib.sha256("".join(value + "\n" for value in sorted(report["unimplemented"])).encode()).hexdigest()
    if len(report["unimplemented"]) != 184 or pending_digest != "618df840c1a5bb7808f0e747ad8c18f5f90532d2676ea05454d9efe0f41b7d76":
        raise RuntimeError("Pending cases differ from the exact 184-ID transport/native-representation inventory")
    return {"status": "verified-incomplete", "runtimePassed": len(report["runtimePassed"]),
            "unimplemented": len(report["unimplemented"]), "runtimePassedIDsSHA256": digest, "releaseParity": False}


def inventory_check(path, reference):
    report = json.loads(path.read_text())
    corpus = json.loads((reference / "behavioral-vectors.json").read_text())
    baseline = json.loads((reference / "baseline.json").read_text())["corpus"]
    operations = {}
    for case in corpus["cases"]:
        operation = case["operation"]
        operations[operation] = operations.get(operation, 0) + 1
    expected = {"status": "inventory", "corpusVersion": baseline["behavioralVectorsVersion"],
                "totalCases": len(corpus["cases"]), "fixtures": len(corpus["fixtures"]),
                "requiredPortable": sum(c["partition"] == "requiredPortableIds" for c in corpus["cases"]),
                "requiredImplementation": sum(c["partition"] == "requiredImplementationIds" for c in corpus["cases"]),
                "informational": sum(c["partition"] == "informationalIds" for c in corpus["cases"]),
                "operations": operations}
    if report != expected:
        raise RuntimeError("Standalone inventory differs from frozen corpus counts or fields")
    return {"status": "verified", "totalCases": expected["totalCases"],
            "coverage": "inventory only; no runtime parity assertion"}


def resolution_components_check(path, reference):
    report = json.loads(path.read_text())
    corpus = json.loads((reference / "behavioral-vectors.json").read_text())
    expected_fields = {"scope", "status", "totalCorpusCases", "eligibleComponentIDs", "eligibleIDsSHA256",
                       "projectedComponentsPassed", "failed", "projectedFields", "unexaminedWholeCaseChannels"}
    if set(report) != expected_fields or report["scope"] != "single-catalog-component-projection":
        raise RuntimeError("Resolution component report fields or scope differ")
    ids = report["eligibleComponentIDs"]
    known = {case["id"] for case in corpus["cases"] if case["operation"] == "getResult"}
    if not isinstance(ids, list) or not all(isinstance(value, str) for value in ids):
        raise RuntimeError("Resolution component IDs must be explicit strings")
    digest = hashlib.sha256("".join(value + "\n" for value in ids).encode()).hexdigest()
    pinned_digest = "fe8cbe90b8c000e88f094edb980b034ba86205ceeae65d6b460c2b825e24b467"
    if len(ids) != 578 or len(set(ids)) != len(ids) or not set(ids) <= known or digest != pinned_digest:
        raise RuntimeError("Resolution component eligibility differs from the input-selected 578-ID ratchet")
    if report["eligibleIDsSHA256"] != digest or report["totalCorpusCases"] != len(corpus["cases"]):
        raise RuntimeError("Resolution component digest or corpus total differs")
    if report["status"] != "passed" or report["projectedComponentsPassed"] != ids or report["failed"] != []:
        raise RuntimeError("Resolution component projections did not all pass")
    if report["projectedFields"] != ["outcome", "translation", "error.type", "error.message",
                                     "error.causeType", "error.causeMessage", "resolverCalls"]:
        raise RuntimeError("Resolution component observations silently changed")
    if report["unexaminedWholeCaseChannels"] != ["match", "result metadata", "fallback policy", "failure handler",
                                                "result/failure identity", "successful fallback observation", "bidi policy"]:
        raise RuntimeError("Resolution component omissions silently changed")
    return {"status": "verified-component-projection", "projectedComponentsPassed": len(ids),
            "eligibleIDsSHA256": digest, "wholeRuntimeCasesAdded": 0, "releaseParity": False}


def runtime_adapter_check(path, reference):
    report = json.loads(path.read_text())
    corpus = json.loads((reference / "behavioral-vectors.json").read_text())
    fields = {"scope", "nativeMappingsRatified", "status", "totalRuntimeCases", "eligibleIDs",
              "eligibleIDsSHA256", "runtimePassed", "failed", "pending"}
    if set(report) != fields or report["scope"] != "public-runtime-full-observation" or report["nativeMappingsRatified"] is not False:
        raise RuntimeError("Runtime adapter scope, fields or mapping disposition differs")
    known = {row["id"] for row in corpus["cases"] if row["operation"] in ("get", "getResult", "construct")}
    eligible = report["eligibleIDs"]
    if not isinstance(eligible, list) or not all(isinstance(value, str) for value in eligible):
        raise RuntimeError("Runtime adapter eligibility must enumerate exact IDs")
    digest = hashlib.sha256("".join(value + "\n" for value in eligible).encode()).hexdigest()
    if (eligible != sorted(set(eligible)) or len(eligible) != 1432
            or digest != "364e6f0954c2adc1c825a86aee4ea9b423fb850e741b13a01cb2973b6a1a6b60"
            or report["eligibleIDsSHA256"] != digest or report["totalRuntimeCases"] != 1452
            or report["runtimePassed"] != eligible or report["failed"] != [] or report["status"] != "passed"):
        raise RuntimeError("Full runtime observations differ from the input-selected 1,432-ID ratchet")
    pending = report["pending"]
    categories = {"callback-null-configuration", "catalog-null-shape", "phonetic-unmapped-null-return",
                  "placeholder-name-null", "tiebreaker-null-shape"}
    if not isinstance(pending, list) or len(pending) != 20:
        raise RuntimeError("Runtime adapter must retain twenty native representation cases")
    for row in pending:
        if set(row) != {"id", "guards"} or not isinstance(row["id"], str) or not row["guards"]:
            raise RuntimeError("Pending runtime case lacks exact ID or guards")
        for guard in row["guards"]:
            if (set(guard) != {"category", "inputPath", "evidence"} or guard["category"] not in categories
                    or not isinstance(guard["inputPath"], str) or not guard["inputPath"]
                    or not isinstance(guard["evidence"], str) or not guard["evidence"]):
                raise RuntimeError("Pending runtime guard lacks input/consultation evidence")
    pending_ids = [row["id"] for row in pending]
    pending_digest = hashlib.sha256("".join(value + "\n" for value in pending_ids).encode()).hexdigest()
    if (pending_ids != sorted(set(pending_ids)) or pending_digest != "e19eacaf8f0773df2bdb0ca83e38a025fa8b964f20f2dfc188ec05e5fd83dd79"
            or set(eligible) & set(pending_ids) or set(eligible + pending_ids) != known):
        raise RuntimeError("Runtime eligibility and pending inventory overlap, omit or change IDs")
    return {"status": "verified-full-runtime-observations", "runtimePassed": len(eligible),
            "eligibleIDsSHA256": digest, "nativeRepresentationPending": len(pending), "releaseParity": False}


def loader_check(path, reference):
    report = json.loads(path.read_text())
    corpus = json.loads((reference / "behavioral-vectors.json").read_text())
    fields = {"scope", "status", "eligibleIDs", "eligibleIDsSHA256", "runtimePassed", "failed",
              "pendingCarriers", "adaptationObservations"}
    if set(report) != fields or report["scope"] != "native-filesystem-full-observation":
        raise RuntimeError("Loader report fields or native observation scope differ")
    rows = {row["id"]: row for row in corpus["cases"]
            if row["operation"] in ("load", "loadClasspath", "loadClasspathResources")}
    eligible = report["eligibleIDs"]
    if not isinstance(eligible, list) or not all(isinstance(value, str) for value in eligible):
        raise RuntimeError("Loader eligibility must enumerate exact IDs")
    digest = hashlib.sha256("".join(value + "\n" for value in eligible).encode()).hexdigest()
    if (eligible != sorted(set(eligible)) or len(eligible) != 145
            or digest != "6c6043d0326a9a524690c485292cc2cd748161504fbaa5c0c7fcb97d91e16991"
            or report["eligibleIDsSHA256"] != digest or report["runtimePassed"] != eligible
            or report["failed"] != [] or report["status"] != "passed"
            or any(rows[value]["operation"] != "load" for value in eligible)):
        raise RuntimeError("Native loader passes differ from the exact input-selected 145-ID ratchet")
    pending = report["pendingCarriers"]
    native_categories = {"native-competing-invalid-json-filenames", "native-aggregate-file-cap-diagnostic-order",
                         "native-extensionless-json-alias-diagnostic-order"}
    categories = native_categories | {"jvm-classpath-discovery", "jvm-classpath-resource-resolution"}
    if not isinstance(pending, list) or len(pending) != 164:
        raise RuntimeError("Loader report must retain 159 JVM carriers and five native ordering cases")
    for row in pending:
        if (set(row) != {"id", "category", "evidence"} or row["category"] not in categories
                or not isinstance(row["id"], str) or row["id"] not in rows
                or not isinstance(row["evidence"], str) or not row["evidence"]):
            raise RuntimeError("Pending loader carrier lacks input-derived evidence")
        operation = rows[row["id"]]["operation"]
        if ((operation == "load") != (row["category"] in native_categories)
                or (operation == "loadClasspath") != (row["category"] == "jvm-classpath-discovery")
                or (operation == "loadClasspathResources") != (row["category"] == "jvm-classpath-resource-resolution")):
            raise RuntimeError("Pending loader category does not describe the actual input carrier")
    pending_ids = [row["id"] for row in pending]
    if (pending_ids != sorted(set(pending_ids)) or set(eligible) & set(pending_ids)
            or set(eligible + pending_ids) != set(rows)):
        raise RuntimeError("Loader inventory overlaps, omits or changes corpus IDs")
    adaptations = report["adaptationObservations"]
    if not isinstance(adaptations, list) or len(adaptations) != 5:
        raise RuntimeError("Loader report must retain actual and frozen observations for all five native differences")
    adaptation_ids = [row["id"] for row in adaptations]
    adaptation_digest = hashlib.sha256("".join(value + "\n" for value in sorted(adaptation_ids)).encode()).hexdigest()
    if (len(set(adaptation_ids)) != 5 or adaptation_digest != "f2e4b155d9ff9f7a77acf00a53fcead51f8482fce9e47230466543a51f779131"
            or set(adaptation_ids) != {row["id"] for row in pending if row["category"] in native_categories}):
        raise RuntimeError("Native diagnostic adaptation IDs differ")
    for row in adaptations:
        if set(row) != {"id", "nativeObservationJSON", "referenceObservationJSON", "difference"}:
            raise RuntimeError("Native adaptation observation fields differ")
        native = json.loads(row["nativeObservationJSON"])
        expected = json.loads(row["referenceObservationJSON"])
        if expected != rows[row["id"]]["expected"] or not isinstance(row["difference"], str) or not row["difference"]:
            raise RuntimeError("Adaptation lacks the unmodified frozen expectation and an actual difference")
        # The unresolved difference is filename attribution only. All other
        # result fields and warning arrays remain exact full observations.
        if set(native) != {"load"} or set(expected) != {"load"}:
            raise RuntimeError("Adaptation changed loader observation channels")
        native_message = native["load"].pop("failureMessage")
        expected_message = expected["load"].pop("failureMessage")
        if (not isinstance(native_message, str) or not isinstance(expected_message, str)
                or native_message == expected_message or native != expected or native["load"]["failed"] is not True):
            raise RuntimeError("Native adaptation exceeds the documented failure-message difference")
    return {"status": "verified-native-filesystem-observations", "runtimePassed": len(eligible),
            "eligibleIDsSHA256": digest, "jvmCarriersPending": 159, "nativeOrderingPending": 5, "releaseParity": False}


def binary_check(path, platform):
    output = invoke(["xcrun", "vtool", "-show-build", str(path.resolve())])
    versions = re.findall(r"\bminos\s+([\d.]+)", output)
    expected = EXPECTED_PLATFORMS[platform]
    if not versions or any(version != expected for version in versions):
        raise RuntimeError(f"Built Mach-O floor {versions} differs from declared {platform} {expected}")
    linked = invoke(["xcrun", "otool", "-L", str(path.resolve())])
    images = [line.strip().split(" (", 1)[0] for line in linked.splitlines()[1:] if line.strip()]
    if any("XCTest" in image or "Testing.framework" in image for image in images):
        raise RuntimeError("Standalone qualification binary must not link a test framework")
    return {"binary": str(path), "platform": platform, "builtMinimumOS": expected,
            "linkedImages": images, "linkedTestFramework": False,
            "coverage": "compiled deployment floor only; no old-OS runtime execution"}


def offline_build():
    with tempfile.TemporaryDirectory(prefix="lokalized-offline-package-") as temporary:
        copy = Path(temporary) / "Package"
        copy.mkdir()
        shutil.copy2(ROOT / "Package.swift", copy / "Package.swift")
        shutil.copytree(ROOT / "Sources", copy / "Sources")
        if (ROOT / "Tests").is_dir():
            shutil.copytree(ROOT / "Tests", copy / "Tests")
        invoke(["swift", "build", "--disable-sandbox", "--scratch-path", str(Path(temporary) / "Build")], copy)
        consumer = Path(temporary) / "Consumer"
        (consumer / "Sources/Consumer").mkdir(parents=True)
        (consumer / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Consumer", platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [.package(path: "../Package")],
    targets: [.executableTarget(name: "Consumer", dependencies: [
        .product(name: "Lokalized", package: "package")])], swiftLanguageModes: [.v6])
''')
        (consumer / "Sources/Consumer/main.swift").write_text('''import Lokalized
let key: ExactString = "hello"
let limits = TranslationRuntimeLimits.defaults
precondition(key.utf16Count == 5 && Gender.masculine.rawValue == "GENDER_MASCULINE")
precondition(BuildMetadata.current.producerImplementation == "lokalized-swift")
precondition(limits.maximumExpressionTokens == 256)
let model = try LocalizedString(key: key, translation: "Hello")
let defined = try LocalizedStringLoader.defineCatalog([model], locale: "en")
let parsed = try LocalizedStringLoader.parse("{\\"hello\\":\\"Hello\\"}", locale: "en", source: "consumer")
precondition(defined.strings == parsed.strings && parsed.originsByKey[key] == ["consumer"])
let merged = try LocalizedStringLoader.mergeParsedStringsFiles([defined, parsed])
precondition(merged.strings.count == 1 && merged.originsByKey[key] == ["<defined>", "consumer"])
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
print("consumer-import-passed")
''')
        scratch = str(Path(temporary) / "ConsumerBuild")
        invoke(["swift", "build", "--disable-sandbox", "--scratch-path", scratch], consumer)
        output = invoke(["swift", "run", "--skip-build", "--disable-sandbox", "--scratch-path", scratch, "Consumer"], consumer)
        if output.strip() != "consumer-import-passed":
            raise RuntimeError("Fresh consumer did not execute the actual public APIs")
    return {"freshPackageBuild": "passed", "dependencies": "none",
            "freshConsumerImport": "compiled and executed (temporary local path dependency only)",
            "referenceArtifactsRequiredToBuild": False,
            "coverage": "no resolution inputs; does not measure network traffic"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler-track", choices=("minimum", "current"), default="current")
    parser.add_argument("--offline-build", action="store_true")
    parser.add_argument("--audit-report", type=Path)
    parser.add_argument("--inventory-report", type=Path)
    parser.add_argument("--resolution-components-report", type=Path)
    parser.add_argument("--runtime-adapter-report", type=Path)
    parser.add_argument("--loader-report", type=Path)
    parser.add_argument("--manifest-contract-report", type=Path)
    parser.add_argument("--manifest-urls-report", type=Path)
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--binary-platform", choices=tuple(EXPECTED_PLATFORMS), default="macos")
    args = parser.parse_args()
    result = package_check(args.compiler_track)
    if args.offline_build:
        result["freshBuild"] = offline_build()
    if args.audit_report:
        result["audit"] = audit_check(args.audit_report, args.reference)
    if args.inventory_report:
        result["inventory"] = inventory_check(args.inventory_report, args.reference)
    if args.resolution_components_report:
        result["resolutionComponents"] = resolution_components_check(args.resolution_components_report, args.reference)
    if args.runtime_adapter_report:
        result["runtimeAdapter"] = runtime_adapter_check(args.runtime_adapter_report, args.reference)
    if args.loader_report:
        result["loader"] = loader_check(args.loader_report, args.reference)
    if args.manifest_contract_report:
        from verify_manifest_contract_report import report_check
        result["manifestContract"] = report_check(args.manifest_contract_report, args.reference)
    if args.manifest_urls_report:
        from verify_manifest_urls import report_check
        result["manifestURLs"] = report_check(args.manifest_urls_report, args.reference)
    if args.binary:
        result["binaryFloor"] = binary_check(args.binary, args.binary_platform)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"Package verification refused: {error}", file=sys.stderr)
        sys.exit(1)
