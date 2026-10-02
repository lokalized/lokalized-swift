# Runtime callbacks, bidi and UI display

`Strings.get` and `getResult` are synchronous throwing operations. `DefaultStrings` combines the pinned locale matcher, immutable catalog models and the expression/fragment kernels. Public results retain the supplied or computed `LocaleMatchResult` reference. Raw caller values are snapshotted once for each lookup; generated text never changes the context used by expressions or selectors.

## Per-key fallback and callbacks

The per-key candidate walk is separate from negotiation. A direct locale begins lookup from that locale; a language-range or supplied-match lookup begins from the selected locale, or the configured fallback when no locale matched. Each candidate is recorded before its catalog is consulted. The supplying catalog's locale drives expressions, plural rules, phonetic callbacks and successful translation bidi behavior.

Each failed candidate has its own reason and optional cause. A fallback policy receives that candidate's values only when another candidate remains. It is never called after the final candidate or after successful translation. The default policy advances past missing entries and nonmatching alternatives, and stops on resolution errors. A policy exception propagates immediately.

On total failure, any resolution failure takes precedence over nonmatching alternatives, which take precedence over missing entries. The first resolution error is retained, even if a later attempt throws a different error. The failure handler runs exactly once after the walk. A throw response rethrows that original cause when available; without a cause it throws `MissingTranslationError`. A return-string response is literal: it is neither interpolated nor isolated.

`TranslationFallbackObserver` observes successful per-key fallback. It runs once, synchronously, after a later candidate succeeds and before lookup returns. Its event contains the key, lookup/resolved/attempted locales, retained match reference and every preceding candidate's reason and original cause. It does not retain rendered translation text or caller values. It never runs after an unsuccessful lookup or when the first candidate answers, even when negotiation made `TranslationResult.isFallback` true.

Observer execution is outside the resolution catch. An observer error propagates unchanged and cannot resume fallback or invoke the failure handler. Enabling observation does not change candidate validation or the walk. Attempted-locale validation when constructing a result remains in the resolution channel to preserve the frozen Java 3.1.0 contract, including legacy `x-lvariant` refusals. Raw preceding candidate records become validated event values only after a result succeeds.

Callback wrappers hold `@Sendable` throwing closures. Shared application callbacks must protect their own mutable state. Runtime attempt state and budgets remain local, so the same immutable runtime supports simultaneous lookups and synchronous callback reentry. Value snapshots retain custom application values; they do not deep-copy those values.

## Caller text isolation

The default `BidiIsolation.rtlLocales` checks the supplying locale's script, using pinned likely-subtags only when that locale has no explicit script. `ar` isolates caller text; `ar-Latn` and `ar-Zzzz` do not. `BidiIsolation.always` isolates caller text in every locale, and `.disabled` turns isolation off. Direction is never inferred from the text itself. Nil per-call overrides inherit configuration; `.disabled` is an explicit override.

Only caller replacement values are isolated. A generated fragment's translation-owned text remains bare, while caller values used inside that fragment are isolated normally. A returned failure key has no supplying catalog and therefore uses the requested lookup locale.

Isolation uses FSI (`U+2068`) and PDI (`U+2069`). Empty values stay empty. A value consisting of exactly one balanced LRI/RLI/FSI isolate run remains unchanged. Other values receive an outer FSI/PDI pair; stray PDI markers are dropped and unclosed inner isolates are balanced before the outer PDI.

Length is measured in UTF-16 code units. The caller value is checked against the remaining output budget before balancing or the already-isolated fast path. Isolate markers consume that same budget, and an overflow reports the configured whole-output maximum. Oversized text is refused after examining a bounded prefix. Isolated custom values are rendered once per exact placeholder name within each interpolated template; later occurrences in that template recheck the cached text against the remaining budget. Distinct names and distinct generated templates remain independent, including canonically equivalent Unicode spellings. A memoized generated fragment is expanded only once. Unisolated custom values render at each occurrence. Missing/null values never invoke custom display conversion.

Returned keys use the lenient interpolation scanner. Malformed delimiters/names remain literal and absent values retain their tokens. If interpolation, display conversion or isolation throws, the exact original key is returned. This fallback can exceed the configured output limit, matching the reference's fail-soft behavior.

## Portable nonthrowing display adapter

`StringsDisplayAdapter` has no UIKit or SwiftUI dependency. It calls the underlying throwing `Strings.get` once and requires a `TranslationErrorDisplayPolicy` at construction:

```swift
let display = StringsDisplayAdapter(strings, errorDisplayPolicy: .custom { failure in
    recordDisplayError(failure.error) // The original error, including a throwing handler's error.
    return "Translation unavailable"
})
let text = display.get("welcome", placeholders: ["name": .text("Alex")])
```

`.returnKey` displays the original key verbatim, `.returnString` displays the supplied string verbatim, and `.custom` receives immutable lookup inputs and the original error. This display policy runs only after an error; it does not replace the runtime's failure handler or successful-fallback observer. Its nonthrowing closure makes the display boundary explicit. Apple view adapters and preferred-language acquisition belong to later platform integration.

## Qualification

`ConformanceRunner.runtimeSelfTest()` covers native obligations absent from the shared corpus: successful fallback event ordering and each retained cause, no-event paths, negotiation versus per-key fallback, observer/policy error propagation, first-cause identity, same-runtime reentry, forty simultaneous lookups, paired legacy attempted-result refusals with and without observation, donor/request bidi and explicit UI error policies. XCTest adds per-call callback replacement/inheritance, bidi override behavior, isolated versus unisolated custom conversion counts, bounded failure-key conversion order and event privacy checks. `BidiRendererTests` separately checks exact balancing, explicit-script directionality, Unicode name identity and UTF-16 limits.

The whole-runtime frozen-corpus audit remains the source of portable parity accounting. Native observer checks supplement it because the frozen corpus contains no successful-fallback observer cases; they do not fabricate new donor-case passes. See [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) for verified milestone counts and remaining scope.
