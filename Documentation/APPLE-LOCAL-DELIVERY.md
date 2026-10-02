# Apple local delivery

M6 adds synchronous file, directory, caller-owned stream and explicit Bundle delivery, plus ordered preferred-language selection. [Local loading](LOCAL-LOADING.md) defines ownership, discovery, diagnostics and cumulative budgets; [preferred languages](PREFERRED-LANGUAGES.md) defines selection. All parsing and matching use Lokalized's pinned data. Apple provides resource locations and the optional preference list.

## Package resources

Store ordinary catalog files under `Lokalized/`, for example `Lokalized/en` and `Lokalized/fr.JSON`. A consumer SwiftPM target must preserve the directory:

```swift
.executableTarget(
    name: "Application",
    dependencies: [.product(name: "Lokalized", package: "lokalized-swift")],
    resources: [.copy("Lokalized")])
```

Call the loader from that target so its generated `Bundle.module` identifies the correct resource bundle:

```swift
import Foundation
import Lokalized

let loaded = try LocalizedStringLoader.loadFromBundle(.module)
let catalogs = loaded.mapValues { LocalizedCatalog(strings: $0.strings) }
let en = try LocaleTag("en")
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { catalogs }, localeSupplier: { _ in en }, fallbackLocale: en))
```

For an Xcode application, add `Lokalized` as a folder reference and include it in Copy Bundle Resources. Use `loadFromBundle(.main)` at the application boundary. Framework callers pass their own `Bundle` explicitly. There is no implicit process-bundle discovery. Avoid `.process` or localized variant groups when their resource flattening/selection would change the authored paths. The loader enumerates all catalogs together, independently of Apple's preferred localization.

Explicit maps permit arbitrary filenames and paths relative to the selected bundle:

```swift
let files = try LocalizedStringLoader.loadFromBundle(applicationBundle,
    resourcePathsByLocale: [
        try LocaleTag("en"): "Payloads/english.catalog",
        try LocaleTag("fr"): "Payloads/french.catalog"
    ])
```

Paths must be nonempty and relative, with no empty, `.` or `..` components, NUL or backslash. Literal components, including an explicit `.lproj`, are used directly. The loader follows symlinks as documented for local files; relative-path validation is not a filesystem containment guarantee. Map count, locale-key, path and exact-rendered-collision validation precede catalog reads; case-folded rendered collisions are checked after parsing as documented for local loads, and one load shares aggregate budgets. Returned files retain their own warnings, origins and canonical source paths.

## UI integration

Load local bytes and construct an immutable runtime once at an application boundary. Per-view language choices use `.forLocale` or `.forLocaleMatch` on the same runtime. `chooseAppleLocale(using:)` acquires preferences explicitly; `chooseLocaleForPreferredLanguages(_:using:)` supports injectable settings and tests. Selection does not mutate the runtime or determine the donor for every translated key.

The [SwiftUI example](../Examples/AppleLocalCatalogs/CatalogApp.swift) owns UI state on `MainActor`, handles thrown loading/lookup errors explicitly and uses an explicit `StringsDisplayAdapter` error display policy. Buttons change per-call options and perform in-memory lookups. No UI isolation bypass, forced `try`, process-wide language switch or per-render file loading is required. The helper and loaders introduce no third-party package or runtime dependency.

## Metadata API and privacy declaration

The local loader calls `fstatat` and `fstat` to distinguish directories/regular files and reject FIFOs and other special files before reading. Only `st_mode` is consulted. It does not inspect, store or transmit timestamps, sizes or inode values. Apple nevertheless lists these functions in its required-reason File Timestamp category. The SDK declares `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `0A2A.1`: the metadata use occurs solely in caller-invoked file-loading wrappers. There is no SDK background use or transmission. See Apple's [API category documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) and [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc).

The package copies `Sources/Lokalized/PrivacyInfo.xcprivacy` into its resource bundle. The packaged-consumer check verifies the actual copied declaration in all app products. This records the SDK's use; application privacy submissions and any other application API use require their own review.

## Reproducible consumers

`Examples/SwiftPMCatalogConsumer` builds a real local-path package consumer with `.copy("Lokalized")` and `Bundle.module`. `Examples/AppleLocalCatalogs` contains shared iOS/macOS SwiftUI source, checked-in Xcode targets/schemes and a folder resource reference. Both use identical English/French bytes with extensionless and uppercase-suffix filenames, plural fragments and canonically equivalent but distinct keys.

```sh
python3 Tools/verify_local_delivery.py --report .build/reports/local-delivery.json
```

The tool takes a fresh source/example snapshot without Reference archives or sibling repositories. It compiles and executes the SwiftPM consumer in Swift 6 mode with default `MainActor` isolation, then in Swift 5 language mode against the Swift 6 library using the selected compiler. It builds real macOS, iOS simulator and iOS device applications with default `MainActor` isolation and approachable concurrency, verifies catalog paths/bytes and privacy resources, and inspects actual Mach-O deployment floors. The macOS app executes `--qualify` against its packaged `Bundle.main`. iOS products are compiled and packaged without signing, installation or runtime execution. Reports retain commands, outputs, input/binary hashes and explicit runtime limits. Source changes during a run invalidate it.

Swift 5 language-mode consumption is distinct from using a Swift 5 compiler. Swift 6.2 compilation, minimum iOS/macOS runtime execution, Intel execution and an actual hosted CI run remain separate qualification gates. Java classloader/JAR observations remain pending native carrier mappings; M6 does not claim full transport or release parity.

M7A repeats these real packaging checks with the manifest foundation linked into the library. `/private/tmp/lokalized-swift-local-delivery-m7a.json` records the current result: both SwiftPM language-mode consumers execute, the packaged macOS app executes, and simulator/device iOS apps compile and preserve the exact catalog/SDK privacy resources. The SwiftPM consumer additionally hashes its actual resource bytes with system CryptoKit, constructs a manifest claim and validates its file-URL fetch plan. It performs no remote loading and produces no verified loaded record.
