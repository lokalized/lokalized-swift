# Native translation contracts

The public `Strings` protocol combines synchronous throwing translation with `LocaleMatcher`. `DefaultStrings` supplies the implementation from an immutable `StringsConfiguration`. Native argument labels and value types replace the Java builder and JS option records; shared operation and setting names remain recognizable.

## Construction and exact collections

`LocalizedStringSupplier` is a throwing `@Sendable () -> [LocaleTag: LocalizedCatalog]` callback. The runtime invokes it once at construction. `LocalizedCatalog(strings:)` retains authored root order and duplicate entries until runtime validation. Its exact-key `entries:` and dictionary-literal forms also retain supplied labels for key/model consistency validation. Constructing a catalog does not structurally hash or deduplicate a model graph.

`PlaceholderValues` stores exact `ExactString` keys and tagged `PlaceholderValue` values. Its `entries:` and dictionary-literal initializers preserve NFC/NFD distinctions; a later entry with the same exact name replaces the earlier value. An absent key differs from `.null`. There is no competing `[String: Any]` or `[String: ...]` literal overload that can normalize distinct keys before the library receives them. The immutable collection snapshots the map shallowly: a referenced custom `Sendable` value remains the same application value.

```swift
let placeholders: PlaceholderValues = [
    "name": .text("Ava"),
    "count": .integer(2),
    "optionalName": .null
]
let catalog = LocalizedCatalog(strings: [
    try LocalizedString(key: "Welcome, {{name}}", translation: "Hello, {{name}}")
])
let configuration = StringsConfiguration(
    localizedStringSupplier: { [try LocaleTag("en"): catalog] },
    localeSupplier: { _ in try LocaleTag("fr-CA") },
    fallbackLocale: try LocaleTag("en")
)
let strings = try DefaultStrings(configuration: configuration)
let result = try strings.getResult("Welcome, {{name}}", placeholders: placeholders)
```

Configuration construction does not invoke callbacks or perform runtime validation. A missing catalog supplier, zero or two locale suppliers, or a leniently projected malformed typed locale remains representable so `DefaultStrings` can refuse it in the reference's construction order. The runtime requires exactly one of `LocaleSupplier` and `LocaleMatchSupplier`. Both receive the current `any LocaleMatcher`, return nonoptional typed values, and may throw. Assigning nil to one field does not erase the other field.

Omitted instance handler, policy, bidi, limits, range-equivalence source and phonetic resolver use the library defaults when the runtime is constructed. `warningHandler` belongs to `LocalizedStringLoader` parsing/definition and loading entry points; it is not an instance translation setting.

## Per-call options and inspection

`TranslationOptions()` and `.none` omit all overrides. A throwing initializer accepts at most one of `locale`, `languageRanges` and `localeMatchResult`, plus optional bidi/handler/policy/observer overrides. Nil settings inherit the instance; `.disabled` explicitly disables bidi isolation. An explicitly empty range array is a supplied negotiation context, distinct from an absent array. Options copy arrays and retain callback/match references.

`forLocale` validates a typed locale or string. `forLanguageRanges` enforces the 32-range limit. `forLocaleMatch` is nonthrowing because the final public match class has already validated its structural invariants; its reference is retained, and instance-dependent compatibility is checked when the options are consumed. Options factories do not negotiate against catalogs or manufacture a bound `Strings` view. The development corpus adapter interprets an explicit archived Java `perCallOverrideOrder` setter recipe before constructing the final single-source options. Native options themselves reject simultaneous sources.

Core `get` and `getResult` accept an `ExactString` key, `PlaceholderValues` and `TranslationOptions`. Convenience overloads omit placeholders, options or both. Literals use `ExactString` directly; wrap a computed native `String` in `ExactString(...)` to preserve its exact code units. `get` returns the result's text, while `getResult` exposes its diagnostic outcome.

`supportedLocales` is a `Set<LocaleTag>`. `fallbackLocale` retains the `LocaleMatcher` string property; `fallbackLocaleTag` exposes the typed carrier. `getKeysForLocale` and `getMissingKeys(sourceLocale:targetLocale:)` return exact-key sets for the specified supported typed locale identities. Inspection does not negotiate or translate.

## Results, failures and identity

`TranslationResult` is an immutable final class with `key`, `translation`, `lookupLocale`, optional `localeMatchResult` and `resolvedLocale`, ordered `attemptedLocales`, `status`, optional `failureReason`, and optional `cause`. Its throwing initializer preserves Java's invariant checks and validation order. Attempted locales must be well formed and have distinct rendered language tags. A translated result needs a resolved locale present by typed identity in its attempts and no failure reason/cause. A handler result needs a failure reason, no resolved locale, and a cause exactly when its reason is resolution failure.

`TranslationResultStatus` cases are `.translated`, `.returnedKey` and `.returnedString`. `TranslationFailureReason` cases are `.missingTranslation`, `.noMatchingAlternative` and `.resolutionFailure`. Their raw values preserve the JS serialized spellings; `displayName` preserves Java's uppercase diagnostic spelling.

`isFallback` is true when negotiation reports no match, CLDR fallback, likely-subtag or primary-language matching, or when a resolved donor is not canonically equivalent to the lookup locale. Exact, canonical, extended-range and wildcard matches do not themselves mark fallback. This flag differs from the successful-fallback observer's later-candidate condition.

`TranslationFailure` is a final immutable snapshot of the failed lookup, including placeholders and the first retained resolution cause. Like Java's internal record, it does not apply the result constructor's locale/attempt-list validation again. Its `message` includes the key, lookup locale, reason and attempted tags, without formatting or revealing placeholder values. A failure handler sees the same retained match and application error references as the eventual handler result.

`MissingTranslationError` exposes the failed key, lookup locale, match, placeholders, reason and attempts. Its public constructors validate locale/attempt invariants and reject resolution failure. Under the throwing response, a resolution failure rethrows its retained cause; missing/no-matching failures construct this error. The reason-refusal diagnostic retains the reference's `MissingTranslationException` identifier. `ConfigurationError` separately categorizes native construction refusal as `.invalidArgument` or `.invalidState`, with an optional retained cause. Runtime expression/argument/state errors use [TranslationEvaluationError](EXPRESSIONS.md).

Match/result/failure/event carriers retain reference identity where the shared contract observes it. No equality or NSError bridging replaces the original error reference. Callback wrappers compare and hash by object identity; `TranslationOptions` equality includes those references. `TranslationFailureResponse.returnString` compares and hashes its text using exact UTF-16 identity.

## Failure policy, handlers and successful fallback

`TranslationFallbackPolicy` wraps a throwing `@Sendable (TranslationFailureReason, LocaleTag, Error?) -> Bool` callback, invoked through `shouldTryNextLocale(reason:attemptedLocale:cause:)`. Built-ins retain the existing names: `fallbackOnMissingTranslationOrNoMatchingAlternative`, `fallbackOnAnyFailure` and `neverFallback`. The default stops on resolution failure and advances for missing/no-matching outcomes.

`TranslationFailureHandler` wraps a throwing `@Sendable (TranslationFailure) -> TranslationFailureResponse` callback, invoked through `handle`. Static `returnKey()` and `throwException()` factories provide the common responses. `returnKey(observer:)` invokes its throwing observer before returning the key response. The exhaustive response enum is `.returnKey`, `.returnString(String)` or `.throwException`; replacement text is returned verbatim, without interpolation or bidi isolation. Callback failures propagate unchanged.

`TranslationFallbackObserver` wraps a throwing `@Sendable (TranslationFallbackEvent) -> Void` callback. The runtime invokes it once, synchronously, before returning a translation supplied by a later candidate. It does not run for a first-candidate success merely because negotiation used fallback, nor for a failed lookup. An observer failure does not resume fallback.

The event exposes the key, typed lookup and resolved locales, retained match, ordered attempts and `precedingFailures`. Each nested `PrecedingFailure` retains its locale, reason and optional cause. Event validation requires a translated result, one failure per preceding candidate, matching attempted order by typed locale identity, and a resolved final candidate. Each preceding failure carries a cause exactly for resolution failure. The runtime creates validated public events after a successful result, so enabling observation does not add validation to an unsuccessful candidate walk.

All shared callbacks are `@Sendable`, synchronous and potentially concurrent/reentrant. Capture thread-safe application state, or sample actor-isolated state on its actor before supplying it. The typed callbacks return nonoptional decisions, responses, locales, matches, catalogs and phonetic forms. Native `nil` refusal is a compile-time adaptation rather than a simulated runtime failure.

## Qualification

`TranslationContractTests` covers exact collection identity, duplicate/order preservation, deferred configuration validation, options omission and callback identity, all eight `isFallback` match categories, result validation priority, typed locale membership, privacy-safe failure snapshots, handler/policy failures, successful-event ordering, and missing-error invariants.

```sh
python3 Tools/verify_callback_types.py --check --report .build/reports/callback-types.json
```

The development tool snapshots and emits the actual library sources as an isolated macOS 12 module using Swift language mode 6, then typechecks one valid public consumer and eight targeted invalid-nil consumers. It checks the intended type diagnostic as well as failed compilation. The report records source hashes, compiler/target/SDK, consumer source and diagnostics. It uses no XCTest, expected corpus values, sibling repository, download or runtime package dependency. This evidence proves the native type boundary; it does not reproduce the Java null-return cases' runtime callback timing, and does not alone ratify or count a corpus representation mapping. Whole-runtime and platform-floor evidence are reported separately.
