# Lokalized for Swift

Lokalized translates shared JSON catalogs into natural-sounding text. This native
Swift port supports **iOS 15+ and macOS 12+**, using **Swift 6.2+** in Swift 6
language mode, with **zero external runtime dependencies**. CLDR plural rules,
locale negotiation and Unicode data ship as compiled Swift data.

The port is under development. Parsing, translation, plural selection, locale
matching, local loading and pure manifest helpers are implemented. The
[implementation status](Documentation/IMPLEMENTATION-STATUS.md) records current
compatibility evidence and remaining release gates.

## Add the package

In Xcode, add `https://github.com/lokalized/lokalized-swift` under Package
Dependencies and select the `Lokalized` library product. In a Swift package,
add the dependency and product to your target. This complete executable example
uses the development branch; pin a reviewed commit for reproducible builds
while the port is awaiting its first release.

<!-- lokalized-example: quickstart manifest -->
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickStart",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/lokalized/lokalized-swift", branch: "main")
    ],
    targets: [.executableTarget(name: "QuickStart", dependencies: [
        .product(name: "Lokalized", package: "lokalized-swift")
    ])],
    swiftLanguageModes: [.v6]
)
```

Save the following as `Sources/QuickStart/main.swift`, then run `swift run QuickStart`:

<!-- lokalized-example: quickstart source -->
```swift
import Lokalized

let en = try LocaleTag("en")
let file = try LocalizedStringLoader.parse(
    #"{"welcome":"Hello, {{name}}!"}"#,
    locale: "en", source: "en.json")
let catalogs = [en: LocalizedCatalog(strings: file.strings)]
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { catalogs },
    localeSupplier: { _ in en }, fallbackLocale: en))

print(try strings.get("welcome", placeholders: ["name": .text("Ada")]))
```

Output:

<!-- lokalized-example: quickstart output -->
```text
Hello, Ada!
```

Load catalogs and construct the immutable runtime once. Per-call options let
independent views or requests use different languages on the same instance.

## Use catalog files in an app

The [usage guide](Documentation/USAGE.md) is a complete runnable example with
English/French resources, plural fragments, language preferences, fallback
diagnostics, exact Unicode keys and explicit failure handling. The same catalog
syntax is used by the Java and JavaScript ports; preserve authored keys and
language-form tokens when sharing files.

For SwiftPM resources, use `.copy("Lokalized")` and call
`LocalizedStringLoader.loadFromBundle(.module)` from the resource-owning target.
For an Xcode app, preserve the folder in Copy Bundle Resources and pass `.main`.
[Apple local delivery](Documentation/APPLE-LOCAL-DELIVERY.md) explains framework
bundles, explicit path maps and the packaged privacy declaration.
[Examples](Examples/README.md) include real SwiftPM and iOS/macOS SwiftUI consumers.

Local loaders accept `Data`, `String`, caller-owned synchronous streams and
local files. Applications acquire any remote content and pass it to those
loaders; Lokalized does not provide HTTP loading. Manifest APIs compute identity
and plan references synchronously without reading catalog bodies.

## API guides

- [Translation and callbacks](Documentation/RUNTIME-API.md),
  [bidi and display](Documentation/RUNTIME-SEMANTICS.md),
  [expressions](Documentation/EXPRESSIONS.md) and [fragments](Documentation/FRAGMENTS.md).
- [Numbers and plural operands](Documentation/NUMBERS.md),
  [locale matching](Documentation/LOCALE-MATCHING.md) and
  [preferred languages](Documentation/PREFERRED-LANGUAGES.md).
- [Local loading and limits](Documentation/LOCAL-LOADING.md),
  [manifest validation](Documentation/MANIFEST-VALIDATION.md),
  [identity](Documentation/MANIFEST-IDENTITY.md) and [planning](Documentation/MANIFEST-PLANNING.md).
- [Cross-port API mappings](Documentation/API-MAPPING.md),
  [public API coverage](Documentation/API-COVERAGE.md) and
  [native compatibility contracts](Documentation/NATIVE-CONTRACTS.md).

Consumer builds need only the Swift sources and Apple's SDKs. Reference archives,
Python, Java and Node serve development checks; there are no build plugins,
generation steps or downloads in a consumer build. Deployment-floor compilation
and execution on each supported OS are recorded separately in
[deployment evidence](Documentation/DEPLOYMENT.md).

## Develop and qualify

```sh
swift build
swift test
swift run LokalizedConformance --self-test
python3 Tools/verify_documentation.py --report .build/reports/documentation.json
```

The [development guide](Documentation/DEVELOPMENT.md) describes the frozen corpus,
expected incomplete-audit exit status, generation checks and focused platform,
packaging, concurrency and performance recipes. Shared native adaptations are
reported separately from exact runtime agreement; this repository does not
claim certified universal parity.

Source distributions include the Apache [license](LICENSE),
[attribution](NOTICE), [third-party notices](THIRD-PARTY-NOTICES.md) and complete
data licenses. See [source distribution](Documentation/SOURCE-DISTRIBUTION.md)
for the fresh extracted-package consumer check.
