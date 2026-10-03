# Lokalized for Swift

Native Lokalized for iOS 15+ and macOS 12+, using Swift 6.2+ in Swift 6 language mode. The library has **zero external runtime package dependencies**.

This port is under development. Catalog parsing, model validation, exact numbers, plural evaluation, locale matching, expression evaluation, recursive fragment resolution, the public translation runtime and Apple local delivery are implemented. Manifest parsing, identity and deterministic load planning are implemented as M7A; Swift follows Java's local-loading model; HTTP acquisition belongs to applications. See [implementation status](Documentation/IMPLEMENTATION-STATUS.md), [API mappings](Documentation/API-MAPPING.md) and [public API coverage](Documentation/API-COVERAGE.md).

The `Lokalized` library provides immutable catalog and placeholder models, strict `Data`/`String`/stream/file parsing, explicit directory/Bundle/resource-map loading, source-aware errors, eager expression validation, warnings, programmatic catalog validation, and same-locale shard merging. It also includes all 61 language forms, exact UTF-16 keys, validated limits, exact decimals/plural operands and complete CLDR 48.2 cardinal, ordinal and range rules. Identifier classification and plural evaluation use checked-in data independently of the device OS.

```swift
import Lokalized

let form = Gender.masculine
print(form.rawValue)    // GENDER_MASCULINE
print(form.displayName) // MASCULINE

let composed: ExactString = "é"
let decomposed: ExactString = "e\u{0301}"
assert(composed != decomposed)

let catalog = try LocalizedStringLoader.parse(
    #"{"hello":"Hello, {{name}}!"}"#,
    locale: "en", source: "en.json")
assert(catalog.strings.first?.key == "hello")

let definition = try LocalizedString(key: "bye", translation: "Goodbye!")
let defined = try LocalizedStringLoader.defineCatalog([definition], locale: "en")
let merged = try LocalizedStringLoader.mergeParsedStringsFiles([catalog, defined])
assert(merged.strings.count == 2)

let en = try LocaleTag("en")
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { [en: LocalizedCatalog(strings: merged.strings)] },
    localeSupplier: { _ in en }, fallbackLocale: en))
let result = try strings.getResult("hello", placeholders: ["name": .text("Ada")])
assert(result.translation == "Hello, Ada!" && result.status == .translated)

let one = try Cardinality.forNumber(.integer(1), locale: "en")
let writtenDecimal = try NumericValue.forDecimal("1.00")
let other = try Cardinality.forNumber(writtenDecimal, locale: "en")
assert(one == .one && other == .other)

let matcher = try DefaultLocaleMatcher(
    supportedLocales: ["en", "fr", "zh-Hant"], fallbackLocale: "en")
let match = try matcher.matchFor("zh-TW")
assert(match.locale == "zh-Hant")
let preferred = try matcher.bestMatchForAcceptLanguage("fr;q=0.9,en;q=0.8")
assert(preferred == "fr")
let ranges = try LanguageRange.parse("fr;q=0.9,en;q=0.8")
let options = try TranslationOptions.forLanguageRanges(ranges, using: matcher)
assert(options.localeMatchResult?.locale == "fr")
// Accept-Language text may instead be supplied to forAcceptLanguage(_:using:).
```

Build and qualify from this directory:

```sh
swift build
swift test
swift run LokalizedConformance --self-test
swift run LokalizedConformance --inventory
swift run LokalizedConformance --plural-data
swift run LokalizedConformance --locale-data
swift run LokalizedConformance --resolution-components
swift run LokalizedConformance --runtime-adapter
swift run LokalizedConformance --loader
swift run LokalizedConformance --loader-boundaries
swift run LokalizedConformance --manifest-contract
swift run LokalizedConformance --manifest-urls
swift run LokalizedConformance --idna-normalization
swift run LokalizedConformance --audit --report .build/audit.json
python3 Tools/reference_baseline.py --check
python3 Tools/api_inventory.py --check
python3 Tools/verify_api_coverage.py --check
python3 Tools/verify_api_coverage.py --qualify --report .build/reports/api-coverage.json
python3 Tools/manifest_contract.py --check
python3 Tools/verify_manifest_urls.py --check
python3 Tools/generate_idna_tables.py --check
python3 Tools/generate_idna_compatibility.py --check
python3 Tools/generate_idna_normalization_compatibility.py --check
python3 Tools/oracle_runtime.py --check
python3 Tools/verify_idna_compatibility.py --check
python3 Tools/verify_idna_compatibility_normalization_tables.py --check
python3 Tools/verify_idna_urls.py --check
python3 Tools/verify_idna_tables.py --check
python3 Tools/verify_idna_normalization.py --check
python3 Tools/generate_identifier_tables.py --check
python3 Tools/materialize_fixtures.py --check
python3 Tools/generate_warning_forms.py --check
python3 Tools/generate_plural_data.py --check
python3 Tools/generate_locale_data.py --check
python3 Tools/generate_language_range_data.py --check
python3 Tools/verify_floating_point.py --check
python3 Tools/verify_locales.py --check
python3 Tools/verify_language_ranges.py --check
python3 Tools/verify_callback_types.py --check
python3 Tools/verify_package.py --offline-build
python3 Tools/test_source_package.py
python3 Tools/source_package.py --check
python3 Tools/verify_local_delivery.py
python3 Tools/verify_loader_dispositions.py --qualify --report .build/reports/loader-dispositions.json
python3 Tools/verify_loader_dispositions.py --report-check .build/reports/loader-dispositions.json --negative-controls
python3 Tools/measure_package.py --check
python3 Tools/measure_package.py --measure --samples 3 --report .build/reports/package-performance.json
python3 Tools/measure_package.py --report-check .build/reports/package-performance.json --negative-controls
python3 Tools/profile_lookup.py --output-directory .build/profiles/lookup
```

The main behavioral audit exits **1** with status `incomplete`: **2,197 cases pass**, including 1,432 end-to-end translation/construction cases and 145 actual filesystem loader observations. The remaining **184 IDs** cover 159 JVM classloader/resource carriers, five native diagnostic-order mappings and twenty native nil-shape/callback configurations. `--loader` retains actual and frozen observations for the five ordering differences; no expected filenames are substituted. [Loader dispositions](Documentation/LOADER-DISPOSITIONS.md) account for all 164 pending local-carrier/ordering IDs with isolated native boundary checks; they add no corpus pass. `--plural-data` separately checks every pinned CLDR plural locale/sample, range pair and example inventory. Exit 0 is reserved for completed qualification of the selected command; exit 2 indicates invalid arguments or a rejected reference archive. CI verifies the exact passing-case set and complete accounting.

`--resolution-components` separately compares 578 input-selected single-catalog projections against the frozen corpus: outcomes, exact text, error messages/immediate causes and resolver call traces. It retains its narrower component scope; the main audit separately verifies full runtime observations. See [runtime contracts](Documentation/RUNTIME-API.md), [bidi and display semantics](Documentation/RUNTIME-SEMANTICS.md), [expressions](Documentation/EXPRESSIONS.md) and [fragments](Documentation/FRAGMENTS.md).

Consumer builds need only the sources and Apple's system SDKs. The frozen [reference archive](Documentation/REFERENCE-BASELINE.md), Python tools, Java, and Node are development inputs. There are no build plugins, external packages, or reference-data downloads during a consumer build. The runtime uses the same localization file syntax and selection semantics as the Java and JavaScript ports.

[Source distribution](Documentation/SOURCE-DISTRIBUTION.md) creates and qualifies
a deterministic archive of the current source tree. It includes the Apache
[license](LICENSE), [attribution](NOTICE), [third-party notices](THIRD-PARTY-NOTICES.md)
and complete data licenses. A fresh extracted consumer compiles after the
development reference/tool directories are removed and verifies the packaged
privacy declaration. This is a local release rehearsal; no release is published.

Each direct parsing call owns its budgets; one directory/Bundle/map load shares aggregate file, byte, node, warning and discovery accounting. Byte budgets apply to byte inputs; UTF-16 character budgets apply to `String`. Catalog warnings, plurals and matching share the pinned [locale kernel](Documentation/LOCALE-DATA.md). Pass parsed models to `DefaultStrings` for translation. Each immutable runtime compiles catalogs once and keeps lookup state separate under concurrent or reentrant calls.

[Apple local delivery](Documentation/APPLE-LOCAL-DELIVERY.md) shows `.copy("Lokalized")` and caller `Bundle.module` integration, Xcode folder resources and `Bundle.main`, explicit language contexts, and the packaged SDK privacy declaration. [Preferred-language helpers](Documentation/PREFERRED-LANGUAGES.md) apply pinned direct matching to ordered application or Apple preferences. [Examples](Examples/README.md) include real SwiftPM and shared iOS/macOS SwiftUI consumers.

`LocaleTag` separates strict tag validation from Java-compatible lenient projection, CLDR canonicalization and likely subtags. [Matching](Documentation/LOCALE-MATCHING.md) includes weighted ranges, exclusions, diagnostics, fallback election and tiebreakers. [Language-range parsing](Documentation/LANGUAGE-RANGES.md) uses the pinned IANA registry by default, with an explicit pinned Java 21 compatibility mode. None of these services uses device locale data for negotiation.

[Numeric APIs](Documentation/NUMBERS.md) preserve written decimal zeros and distinguish Float from Double. The pinned Java-compatible floating converter and generated plural bytecode require no external runtime libraries. The current converter prioritizes exact behavior; its performance baseline and development oracle are documented separately.

Declared and compiled deployment targets are separate from runtime qualification. The minimum Swift compiler and older iOS/macOS runtime checks must be verified on their actual toolchains and systems; see [deployment evidence](Documentation/DEPLOYMENT.md).

[Package size and performance](Documentation/PERFORMANCE.md) records reproducible optimized consumer builds, cold initialization, catalog construction, repeated lookups and memory observations. CI enforces source size caps and binary caps for measured compiler/SDK/architecture profiles; timings remain observations tied to each host.

[Apple deployment verification](Documentation/DEPLOYMENT.md) checks all four SDK
targets and executes the matching native macOS target. CI is configured for
Swift 6.2 on arm64 and Intel, plus a current arm64 compiler; a compiled kernel
probe refuses translated or mismatched hosts. Hosted execution and minimum-OS
runtime qualification remain unverified.

[Concurrency qualification](Documentation/CONCURRENCY.md) exercises shared
instances across locales, independent resolvers, callback reentry and concurrent
local loads. The selected macOS tests pass under Thread Sanitizer, with a detected
intentional race and inspected instrumentation confirming the detector is active.

Manifest APIs perform synchronous validation and planning without reading catalog bodies. `StringsManifestV1` is an immutable claim; each planning door checks its data identity and recomputed fingerprint again. See [validation](Documentation/MANIFEST-VALIDATION.md), [catalog identity](Documentation/MANIFEST-IDENTITY.md), [planning](Documentation/MANIFEST-PLANNING.md), [Unicode domain processing](Documentation/MANIFEST-URLS.md) and [frozen JS contract evidence](Documentation/MANIFEST-CONTRACT.md). Unicode and Punycode domains use pinned Unicode 17 mapping, a separately recorded URL compatibility profile and original Swift algorithms with zero external runtime dependencies. These pure helpers perform no catalog I/O. The Swift port does not provide HTTP loading; applications acquire remote content themselves and supply `Data`, `String`, a synchronous stream or a local file to the existing parsers. See [local loading](Documentation/LOCAL-LOADING.md) for ownership and limits. Release qualification is the remaining work.

The shared [diagnostic text profile](Documentation/DIAGNOSTIC-TEXT.md) qualifies bounded catalog/manifest duplicate-member messages across Java, JS and Swift. The [manifest normalization profile](Documentation/MANIFEST-NORMALIZATION.md) makes private-use spelling stable and documents fingerprint migration. Remaining platform execution gates are tracked in the implementation status.

[Packaged iOS runtime evidence](Documentation/IOS-RUNTIME.md) records actual iOS
26.5 simulator catalog execution, source-bound receipts and the remaining
minimum-version/device/full-corpus qualification limits.

[Standalone iOS conformance](Documentation/IOS-CONFORMANCE.md) executes all fourteen
qualification commands in a real simulator app, preserving the exact corpus
passing/pending sets and complete native, manifest, data and Unicode observations.
