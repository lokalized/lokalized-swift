# Using Lokalized

Construct a translation runtime, supply the application's language preferences,
and preserve the numeric details that control plural wording.

## Construct a runtime

``DefaultStrings`` validates and compiles its catalogs once. Share the resulting
instance and supply the current language through ``StringsConfiguration/localeSupplier``
or ``StringsConfiguration/localeMatchSupplier``. A lookup with explicit locale
options uses those options instead of invoking the instance's locale supplier.

This small example defines a catalog in code. Applications can load the same
entries from JSON using ``LocalizedStringLoader`` and preserve them in
``LocalizedCatalog`` values.

```swift
import Lokalized

func makeStrings(localeSupplier: @escaping LocaleSupplier) throws -> DefaultStrings {
    let english = try LocaleTag("en")
    let greeting = try LocalizedString(
        key: "Welcome, {{name}}",
        translation: "Welcome, {{name}}"
    )
    let catalog = LocalizedCatalog(strings: [greeting])
    return try DefaultStrings(configuration: StringsConfiguration(
        localizedStringSupplier: { [english: catalog] },
        localeSupplier: localeSupplier,
        fallbackLocale: english
    ))
}
```

The application supplies the locale callback when constructing the runtime.
Callbacks are synchronous and `@Sendable`; any state they read must support
concurrent calls. For actor-owned view state, read the locale on that actor and
pass it through ``TranslationOptions`` for the lookup.

```swift
import Lokalized

func greeting(using strings: any Strings, locale: LocaleTag) throws -> TranslationResult {
    try strings.getResult(
        "Welcome, {{name}}",
        placeholders: ["name": .text("Ada")],
        options: .forLocale(locale)
    )
}
```

``TranslationResult`` includes the text, locale selection, attempted locales,
and outcome. The default failure handler returns the key. Choose
``TranslationFailureHandler/throwException()`` when missing translations should
throw. For a nonthrowing UI callback, use ``StringsDisplayAdapter`` with an
explicit ``TranslationErrorDisplayPolicy``.

## Negotiate application language preferences

Use ``PreferredLanguageChooser`` for an ordered application or Apple language
list. It skips malformed tags and tries the first 32 entries in preference order.
Use ``DefaultLocaleMatcher`` directly for weighted language ranges or an
already combined `Accept-Language` header.

```swift
import Lokalized

func chooseLanguage(_ applicationPreferences: [String]) throws -> LocaleMatchResult {
    let matcher = try DefaultLocaleMatcher(
        supportedLocales: ["en", "fr"],
        fallbackLocale: "en"
    )
    return try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(
        applicationPreferences, using: matcher
    )
}
```

An unmatched result has no selected locale; its `fallbackLocaleTag` remains
available. Matching uses the library's bundled locale data and does not depend
on the operating system's locale-data version.

## Preserve displayed decimal digits

Plural rules can distinguish an integer from a number displayed with fractional
zeros. ``ExactDecimal`` preserves that scale; ``PluralOperands`` exposes the
CLDR operands. Use a formatted string separately when interpolation needs a
particular presentation style.

```swift
import Lokalized

func categoryForDisplayedQuantity() throws -> Cardinality {
    let displayed = try ExactDecimal("1.00")
    let operands = try PluralOperands.forNumber(displayed)
    // n = 1.00, i = 1, v = 2, w = 0, f = 0, t = 0
    return try Cardinality.forOperands(operands, locale: "en") // .other
}
```

``Cardinality`` selects quantity categories, ``Ordinality`` selects position
categories, and ``Cardinality/forRange(_:_:locale:)`` combines endpoint
categories using CLDR range rules. Category names describe locale-specific
rules; `.one` is not a universal test for numeric equality to one.

See the [Swift guide](https://www.lokalized.com/?platform=swift) for app bundles,
Swift Package Manager resources, SwiftUI, and macOS command-line loading examples.
