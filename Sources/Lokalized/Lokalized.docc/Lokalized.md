# ``Lokalized``

Natural-sounding translations for iOS and macOS, with zero runtime dependencies.

Lokalized keeps plural rules, grammatical forms, expressions, and fallback
behavior in portable localized strings files. Load local files or application
resources, construct an immutable ``DefaultStrings`` instance, and translate
with typed placeholder values.

Requires Swift 6.2 or later, iOS 15 or later, and macOS 12 or later.
Application display formatting uses Foundation separately from Lokalized's
pinned locale and plural rules. Remote acquisition belongs to the application;
the library performs no HTTP loading.

See the [Swift guide and cookbook](https://www.lokalized.com/?platform=swift)
for installation, iOS and macOS app bundles, Swift Package Manager resources,
SwiftUI, and macOS command-line examples. Additional
[usage examples](https://github.com/lokalized/lokalized-swift/blob/main/Documentation/USAGE.md)
cover exact strings, numeric operands, callbacks, and local loading.

## Topics

### Getting started

- <doc:UsingLokalized>

### Translation runtime

- ``DefaultStrings``
- ``Strings``
- ``StringsConfiguration``
- ``LocalizedStringSupplier``
- ``LocaleSupplier``
- ``LocaleMatchSupplier``
- ``TranslationOptions``
- ``TranslationResult``
- ``TranslationResultStatus``
- ``TranslationRuntimeLimits``
- ``BidiIsolation``

### Locale matching and language preferences

- ``LocaleTag``
- ``DefaultLocaleMatcher``
- ``LocaleMatcher``
- ``LocaleMatchResult``
- ``LocaleMatchType``
- ``LanguageRange``
- ``LanguageRangeEquivalents``
- ``PreferredLanguageChooser``

### Local files, resources, and parsing

- ``LocalizedStringLoader``
- ``LocalizedStringLoadingOptions``
- ``LocalizedCatalog``
- ``ParsedStringsFile``
- ``LocalizedStringWarning``
- ``LocalizedStringWarningHandler``

### Exact keys, values, and numbers

- ``ExactString``
- ``PlaceholderValues``
- ``PlaceholderValue``
- ``PlaceholderConvertible``
- ``NumericValue``
- ``ExactDecimal``
- ``PluralOperands``
- ``Range``

### Language forms

- ``LanguageForm``
- ``LanguageFormAxis``
- ``LanguageFormValue``
- ``Cardinality``
- ``Ordinality``
- ``Gender``
- ``GrammaticalCase``
- ``Definiteness``
- ``Classifier``
- ``Formality``
- ``Clusivity``
- ``Animacy``
- ``Phonetic``
- ``PhoneticResolver``

### Translation definitions

- ``LocalizedString``
- ``PlaceholderDefinition``
- ``LanguageFormTranslation``
- ``LanguageFormTranslationRange``
- ``ExpressionTranslation``
- ``ExpressionAlternative``

### Failures, fallback, and callbacks

- ``TranslationFailure``
- ``TranslationFailureReason``
- ``TranslationFailureHandler``
- ``TranslationFailureResponse``
- ``TranslationFallbackPolicy``
- ``TranslationFallbackObserver``
- ``TranslationFallbackEvent``
- ``StringsDisplayAdapter``
- ``TranslationDisplayFailure``
- ``TranslationErrorDisplayPolicy``

### Pure manifest helpers

- ``StringsManifestV1``
- ``StringsManifestValue``
- ``StringsManifestMember``
- ``StringsManifestFile``
- ``ManifestLocaleConfiguration``
- ``FetchEntry``
- ``CatalogIdentity``
- ``CatalogIdentityInputV1``
- ``BuildMetadata``

### Errors

- ``ConfigurationError``
- ``LocaleMatcherError``
- ``LocaleTagError``
- ``LanguageRangeError``
- ``LocalizedStringLoadingError``
- ``StringsParseError``
- ``CatalogModelError``
- ``MissingTranslationError``
- ``TranslationEvaluationError``
- ``UnsupportedLocaleError``
- ``NumericError``
- ``PluralLocaleError``
