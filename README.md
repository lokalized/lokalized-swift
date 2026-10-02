# Lokalized for Swift

Native Lokalized for iOS 15+ and macOS 12+, using Swift 6.2+ in Swift 6 language mode. The library has **zero external runtime package dependencies**.

This port is under development. Catalog parsing, model validation, exact numbers, plural evaluation, locale matching, expression evaluation, recursive fragment resolution, the public translation runtime and Apple local delivery are implemented. Manifest parsing, identity and deterministic load planning are implemented as M7A; verified network delivery remains pending. See [implementation status](Documentation/IMPLEMENTATION-STATUS.md) and [API mappings](Documentation/API-MAPPING.md).

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
swift run LokalizedConformance --manifest-contract
swift run LokalizedConformance --manifest-urls
swift run LokalizedConformance --audit --report .build/audit.json
python3 Tools/reference_baseline.py --check
python3 Tools/api_inventory.py --check
python3 Tools/manifest_contract.py --check
python3 Tools/verify_manifest_urls.py --check
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
python3 Tools/verify_local_delivery.py
```

The main behavioral audit exits **1** with status `incomplete`: **2,197 cases pass**, including 1,432 end-to-end translation/construction cases and 145 actual filesystem loader observations. The remaining **184 IDs** cover 159 JVM classloader/resource carriers, five native diagnostic-order mappings and twenty native nil-shape/callback configurations. `--loader` retains actual and frozen observations for the five ordering differences; no expected filenames are substituted. `--plural-data` separately checks every pinned CLDR plural locale/sample, range pair and example inventory. Exit 0 is reserved for completed qualification of the selected command; exit 2 indicates invalid arguments or a rejected reference archive. CI verifies the exact passing-case set and complete accounting.

`--resolution-components` separately compares 578 input-selected single-catalog projections against the frozen corpus: outcomes, exact text, error messages/immediate causes and resolver call traces. It retains its narrower component scope; the main audit separately verifies full runtime observations. See [runtime contracts](Documentation/RUNTIME-API.md), [bidi and display semantics](Documentation/RUNTIME-SEMANTICS.md), [expressions](Documentation/EXPRESSIONS.md) and [fragments](Documentation/FRAGMENTS.md).

Consumer builds need only the sources and Apple's system SDKs. The frozen [reference archive](Documentation/REFERENCE-BASELINE.md), Python tools, Java, and Node are development inputs. There are no build plugins, external packages, or reference-data downloads during a consumer build. The runtime uses the same localization file syntax and selection semantics as the Java and JavaScript ports.

Each direct parsing call owns its budgets; one directory/Bundle/map load shares aggregate file, byte, node, warning and discovery accounting. Byte budgets apply to byte inputs; UTF-16 character budgets apply to `String`. Catalog warnings, plurals and matching share the pinned [locale kernel](Documentation/LOCALE-DATA.md). Pass parsed models to `DefaultStrings` for translation. Each immutable runtime compiles catalogs once and keeps lookup state separate under concurrent or reentrant calls.

[Apple local delivery](Documentation/APPLE-LOCAL-DELIVERY.md) shows `.copy("Lokalized")` and caller `Bundle.module` integration, Xcode folder resources and `Bundle.main`, explicit language contexts, and the packaged SDK privacy declaration. [Preferred-language helpers](Documentation/PREFERRED-LANGUAGES.md) apply pinned direct matching to ordered application or Apple preferences. [Examples](Examples/README.md) include real SwiftPM and shared iOS/macOS SwiftUI consumers.

`LocaleTag` separates strict tag validation from Java-compatible lenient projection, CLDR canonicalization and likely subtags. [Matching](Documentation/LOCALE-MATCHING.md) includes weighted ranges, exclusions, diagnostics, fallback election and tiebreakers. [Language-range parsing](Documentation/LANGUAGE-RANGES.md) uses the pinned IANA registry by default, with an explicit pinned Java 21 compatibility mode. None of these services uses device locale data for negotiation.

[Numeric APIs](Documentation/NUMBERS.md) preserve written decimal zeros and distinguish Float from Double. The pinned Java-compatible floating converter and generated plural bytecode require no external runtime libraries. The current converter prioritizes exact behavior; its performance baseline and development oracle are documented separately.

Declared and compiled deployment targets are separate from runtime qualification. The minimum Swift compiler and older iOS/macOS runtime checks must be verified on their actual toolchains and systems; see [deployment evidence](Documentation/DEPLOYMENT.md).

Manifest APIs perform synchronous validation and planning without reading catalog bodies. `StringsManifestV1` is an immutable claim; each planning door checks its data identity and recomputed fingerprint again. See [validation](Documentation/MANIFEST-VALIDATION.md), [catalog identity](Documentation/MANIFEST-IDENTITY.md), [planning](Documentation/MANIFEST-PLANNING.md) and [frozen JS contract evidence](Documentation/MANIFEST-CONTRACT.md). Unicode/punycode domain handling remains unfinished native URL capability. Streaming transport, verified loaded records, cancellation and publishing are the remaining M7 work.
