# Using Lokalized in a Swift app

This example runs as a SwiftPM executable on macOS. Its catalog-loading and
translation code also works in an iOS or macOS app. Xcode apps pass `.main` at
the loading boundary; frameworks pass their own resource bundle. The
[SwiftUI example](../Examples/AppleLocalCatalogs/CatalogApp.swift) shows UI state
and an explicit display policy on `MainActor`.

## Preserve the catalog directory

Create `Package.swift` with a resource-owning `Catalogs` target. The dependency
uses a version requirement starting at the 1.0.0 release.

<!-- lokalized-example: catalogs manifest -->
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Catalogs",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/lokalized/lokalized-swift", from: "1.0.0")
    ],
    targets: [.executableTarget(name: "Catalogs", dependencies: [
        .product(name: "Lokalized", package: "lokalized-swift")
    ], resources: [.copy("Lokalized")],
       swiftSettings: [.defaultIsolation(MainActor.self)])],
    swiftLanguageModes: [.v6]
)
```

Save this UTF-8 JSON as `Sources/Catalogs/Lokalized/en`:

<!-- lokalized-example: catalogs catalog-en -->
```json
{
  "welcome": "Hello, {{name}}!",
  "items": {
    "translation": "{{count}} {{itemWord}}",
    "placeholders": {
      "itemWord": {
        "value": "count",
        "translations": {
          "CARDINALITY_ONE": "item",
          "CARDINALITY_OTHER": "items"
        }
      }
    }
  },
  "englishOnly": "Available in English.",
  "é": "Composed key",
  "e\u0301": "Decomposed key"
}
```

Save this as `Sources/Catalogs/Lokalized/fr.json`:

<!-- lokalized-example: catalogs catalog-fr -->
```json
{
  "welcome": "Bonjour, {{name}} !",
  "items": {
    "translation": "{{count}} {{itemWord}}",
    "placeholders": {
      "itemWord": {
        "value": "count",
        "translations": {
          "CARDINALITY_ONE": "article",
          "CARDINALITY_OTHER": "articles",
          "CARDINALITY_MANY": "articles"
        }
      }
    }
  }
}
```

`itemWord` is a generated fragment. Its `value` names the caller's numeric
`count`; Lokalized selects a cardinal form using the locale supplying the
translation. French includes `CARDINALITY_MANY` because that is a supported
category in the pinned CLDR rules. Keep these raw tokens in the catalog on
every platform. [Fragments](FRAGMENTS.md) covers other axes and nested selections.

Use `.copy` to keep both catalogs and their paths together. The loader discovers
locale filenames such as `en` and `fr.json`; Apple's resource localization does
not select the language. For arbitrary filenames, pass an explicit
`resourcePathsByLocale` map as shown in [Apple local delivery](APPLE-LOCAL-DELIVERY.md).

## Construct once, translate many times

Save the following Swift blocks, in order, as `Sources/Catalogs/main.swift`.
`Bundle.module` belongs to this target and points at its copied resources.

<!-- lokalized-example: catalogs source -->
```swift
import Foundation
import Lokalized

let en = try LocaleTag("en"), fr = try LocaleTag("fr")
let files = try LocalizedStringLoader.loadFromBundle(.module)
let catalogs = files.mapValues { LocalizedCatalog(strings: $0.strings) }
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { catalogs },
    localeSupplier: { _ in en }, fallbackLocale: en))

print(try strings.get("welcome", placeholders: ["name": .text("Ada")]))
```

The catalog supplier runs once during construction. The locale supplier is
consulted on applicable lookups. Capture immutable `Sendable` state in shared
callbacks; sample actor-owned preferences on their actor before supplying them.
Load files at an application boundary instead of loading them on every view render.

## Choose a language for each lookup

A locale override leaves the shared runtime usable by other language contexts:

<!-- lokalized-example: catalogs source -->
```swift
let french = try TranslationOptions.forLocale(fr)
print(try strings.get("welcome", placeholders: ["name": .text("Ada")], options: french))
print(try strings.get("items", placeholders: ["count": .integer(2)]))
print(try strings.get("items", placeholders: ["count": .integer(2)], options: french))

let preferred = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(
    ["fr-CA", "en"], using: strings)
let preferredResult = try strings.getResult("welcome",
    placeholders: ["name": .text("Ada")], options: .forLocaleMatch(preferred))
print(preferredResult.translation, preferredResult.resolvedLocale?.tag ?? "none")
```

Call `PreferredLanguageChooser.chooseAppleLocale(using: strings)` when you want
to acquire the system's current preferences explicitly. For an application
language setting, pass your own list or locale override. Existing instances
do not subscribe to language changes or mutate a process-wide language.

## Preserve numeric meaning

Pass counts as numeric values so selectors and expressions can inspect them.
Written decimals retain their visible zeros: English `1` selects one, while
`1.00` selects other. Display formatting belongs to the caller when needed;
formatted text is a separate placeholder from the raw count.

<!-- lokalized-example: catalogs source -->
```swift
let decimalCount = try NumericValue.forDecimal("1.00")
let integerForm = try Cardinality.forNumber(.integer(1), locale: "en")
let decimalForm = try Cardinality.forNumber(decimalCount, locale: "en")
print(integerForm.rawValue, decimalForm.rawValue)
print(try strings.get("items", placeholders: ["count": .number(decimalCount)]))
```

[Numbers](NUMBERS.md) explains Float/Double carriers, exact decimals, visible
fraction digits and explicit plural operands. Lokalized uses pinned plural and
locale data rather than device-specific number or locale formatting.

## Inspect fallback and handle failures

`get` returns text; `getResult` also records the outcome and supplying locale.
The default policy tries another candidate for a missing translation or an
unmatched alternative and stops on resolution failure. An exhausted lookup
returns its key by default. This is distinct from successful fallback:

<!-- lokalized-example: catalogs source -->
```swift
let fallback = try strings.getResult("englishOnly", options: french)
print(fallback.translation, fallback.resolvedLocale?.tag ?? "none", fallback.isFallback)

let missing = try strings.getResult("not-authored")
print(missing.translation, missing.status.rawValue)

let throwOnFailure = try TranslationOptions(translationFailureHandler: .throwException())
do {
    _ = try strings.get("not-authored", options: throwOnFailure)
} catch is MissingTranslationError {
    print("MissingTranslationError")
}
```

The throwing handler rethrows the retained cause for a resolution failure;
missing/no-matching outcomes produce `MissingTranslationError`. Parser,
construction and application callback errors can still throw with the default
handler. UI code should handle them at its boundary; the SwiftUI example uses
`StringsDisplayAdapter` with an explicit error-display policy. The
[runtime contracts](RUNTIME-API.md) explain policy, handler and observer timing.

## Keep authored Unicode keys exact

The two English keys `é` and `e\u0301` have different UTF-16 sequences.
Lokalized keeps them distinct even though Swift's normal `String` equality
treats them as canonically equivalent:

<!-- lokalized-example: catalogs source -->
```swift
print(try strings.get("é"), try strings.get("e\u{0301}"))
```

Use Lokalized's `ExactString` and exact collection types for programmatic keys
and placeholders. A normal `[String: ...]` dictionary may collapse the keys
before Lokalized receives them. JSON catalogs preserve their authored identity.

Run `swift run Catalogs`. The complete program prints:

<!-- lokalized-example: catalogs output -->
```text
Hello, Ada!
Bonjour, Ada !
2 items
2 articles
Bonjour, Ada ! fr
CARDINALITY_ONE CARDINALITY_OTHER
1.00 items
Available in English. en true
not-authored returned-key
MissingTranslationError
Composed key Decomposed key
```

## Other local inputs

For a caller-owned byte buffer, use `LocalizedStringLoader.parse(data,
locale:source:)`; for a local file, use `parse(file:locale:)`; for directory
discovery, use `loadFromDirectory`. A supplied synchronous `InputStream`
remains caller-owned and is never closed by Lokalized. Direct parses have
their own budgets; a directory, resource-map or Bundle load shares aggregate
budgets. Strict parsing rejects malformed UTF-8/JSON, duplicate members and
invalid schema; it returns incomplete-form warnings in `ParsedStringsFile`.
[Local loading](LOCAL-LOADING.md) records limits, ownership and warning callbacks.

Applications own remote acquisition and then pass the resulting bytes or local
file to these APIs. Pure manifest helpers perform validation, identity
computation and planning without downloading or loading catalog bodies.
