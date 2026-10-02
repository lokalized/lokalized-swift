# Locale negotiation

M3 implements strict negotiation and fail-soft `Accept-Language` handling independently of translation. `DefaultLocaleMatcher` is an immutable, `Sendable` configuration; `LocaleMatcher` is the public protocol for custom implementations. Matching uses the pinned [locale kernel](LOCALE-DATA.md), IANA equivalents and JDK 21 equivalents described in [language ranges](LANGUAGE-RANGES.md). It does not use `Foundation.Locale`, host ICU negotiation, network access or external dependencies.

```swift
let matcher = try DefaultLocaleMatcher(
    supportedLocales: ["en-US", "en-GB", "fr"],
    fallbackLocale: "en-US",
    tiebreakerLocalesByLanguageCode: ["en": ["en-US", "en-GB"]]
)
let result = try matcher.matchFor([
    LanguageRange("fr", weight: 0.8),
    LanguageRange("en", weight: 0.6)
])
// result.locale == "fr"; result.matchType == .exact
let locale = try matcher.bestMatchForAcceptLanguage("fr;q=0.8,en;q=0.6")
```

## Ingress and configuration

The String locale APIs require full BCP 47 syntax and rebuildable Java locale fields. `matchFor("sgn-nsl")` projects the validated locale through its JDK language tag, producing the requested range `nsl`. In contrast, `matchFor([LanguageRange("sgn-nsl")])` preserves the RFC range spelling and can report a canonical match. An extended range such as `de-*` belongs in the range overload, not the locale overload. Unknown but syntactically valid locales can be negotiated; catalog filename recognition is a separate loader concern.

`LocaleTag` overloads preserve the configured supported locales, fallback and tiebreaker values. `supportedLocaleTags`, `fallbackLocaleTag` and `tiebreakerLocaleTagsByLanguageCode` expose these carriers alongside the String views. A typed locale request still projects its tag into a language range, matching Java's request ingress. Locale identity and rendered tags are distinct: `LocaleTag.forLanguageTag("und")` and `LocaleTag.forLanguageTag("UND")` both render `und` but have different underlying language fields; legacy Norwegian `no-NO-x-lvariant-NY` and modern `nn-NO` also render the same tag with different fields. Configuration and result membership retain that distinction.

Supported locales are validated in caller order, reject duplicate rendered tags case-insensitively, and are then sorted by their ASCII JDK tags. The configured fallback must have a canonically equivalent loaded locale. Election prefers an identical `LocaleTag`, then a unique canonical equivalent, then the configured language tiebreaker among equivalent locales.

Every primary language with multiple loaded locales needs an explicit tiebreaker list containing exactly those locale values once each. A single loaded locale receives its own identity tiebreaker. Language codes normalize legacy and CLDR aliases, so duplicate normalized codes are refused. Undetermined and private-use locales do not create broad primary-language ambiguity. Swift dictionaries have no caller insertion order; configuration validation visits dictionary keys in lexical order when several entries are invalid. Locale arrays retain caller order for duplicate diagnostics and tiebreaker preference.

`languageRangeEquivalents` defaults to `.ianaRegistry`. `.jdk` selects checked-in JDK 21 data; it never consults the machine's installed Java or operating-system registry.

## Election and diagnostics

Negotiation considers the complete supplied list, retaining it in caller order in the result. It sorts a working copy by descending Java `Double.compare` quality with stable caller order at equal quality. It groups overlapping IANA identities and canonical identities, elects semantic representatives, then computes relationships against every supported locale.

Exact, canonical, CLDR-parent and structural relationships reserve their locale before heuristic allocation. An anchor-owning group cannot also spread into a script sibling through inference. Specific requests without an anchor receive at most one unreserved heuristic choice: likely-language/script opportunities are allocated across the whole request list before primary-language opportunities. Specificity and depth determine a locale's governing range before its quality determines whether that locale survives. This preserves narrower quality overrides and zero-quality exclusions: `en;q=1,en-US;q=0` can select `en-GB` while excluding `en-US`.

Among surviving maximum-quality candidates, the serving walk follows request positions and tries exact spelling, IANA identity, extended structural filtering, canonical identity, CLDR fallback, likely language/script, then compatible primary language. CLDR fallback checks all exact ancestor tags before canonically equivalent ancestors. Tiebreakers, configured fallback preference and sorted tag order resolve ambiguity where applicable. Bare `*` first prefers the configured fallback; if excluded, it uses that fallback language's tiebreakers, then sorted tag order. Extended ranges remain structural and cannot broaden through CLDR or likely-subtag inference. RFC extended filtering stops at extension singletons.

Private-use requests can match exactly or through an explicitly extended structural range; they do not gain semantic language matching. Undetermined requests have no exact or primary-language preference semantics. A wildcard can still select an undetermined loaded locale.

The public relationship is rederived from the selected locale and its governing range. Internal governor specificity is not itself the public `matchType`; for example, a wildcard-free structural relationship can report `.likelySubtag`.

| Swift case | Shared wire value | Meaning |
|---|---|---|
| `.noMatch` | `none` | No supported locale survives |
| `.exact` | `exact` | Exact JDK tag and requested range spelling |
| `.canonical` | `canonical` | IANA or CLDR identity equivalence |
| `.cldrFallback` | `cldr-fallback` | A CLDR parent relationship |
| `.likelySubtag` | `likely-subtag` | Compatible likely language and script |
| `.extendedRange` | `extended-range` | RFC extended structural relationship |
| `.primaryLanguage` | `primary-language` | Compatible primary-language preference |
| `.wildcard` | `wildcard` | Bare `*` preference |

`.noMatch` avoids Swift's `Optional.none` ambiguity while retaining the shared `none` wire value. `matchFor` returns an unmatched result with nil locale, range and effective weight; it does not manufacture a fallback selection. `bestMatchFor` returns the result's selected tag or the configured fallback tag.

`LocaleMatchResult` is an immutable `Sendable` final class with value equality and hashing. Its diagnostic fields are `requestedLanguageRanges`, `locale`, `languageRange`, `effectiveWeight`, `matchType`, `fallbackLocale` and `consideredLocales`; `isMatch` reflects selection. The typed initializer and `localeTag`, `fallbackLocaleTag`, `consideredLocaleTags` views preserve underlying locale identity. Considered order participates in equality and is retained for caller-created results. Matcher-produced considered locales use sorted supported order.

Constructor validation checks the requested count, selected locale, fallback locale, matched/unmatched shape, governing-range membership, finite effective weight in `(0,1]`, considered locale validation and duplicate tags, then fallback/selected containment. Membership compares locale fields rather than CLDR identity. `validateSuppliedMatch` subsequently compares fallback identity and the supported locale set, in that order, and returns the same result object. It accepts a caller's considered ordering and does not recompute that result's negotiation. Translation integration will use this contract in M5.

Directly constructed `LanguageRange` values reproduce Java's unusual acceptance of NaN weights. Java ordering and NaN propagation are retained through election, and a selected NaN effective weight is refused by result validation. Signed zero remains an exclusion. Range equality preserves copied NaN identity and distinguishes separately constructed NaNs; its Swift hash normalizes signed zero to satisfy Swift's equality/hash contract. Header grammar does not admit NaN.

## Strict parsing and supplied header handling

`LanguageRange.parse(_:equivalents:)` exposes standalone strict parsing with pinned IANA (default) or JDK expansion. A configured matcher’s `parseLanguageRanges` uses its configured equivalence mode. It has no header-length or matching-count cap. `matchFor` and result construction accept at most 32 expanded ranges and reject a larger list whole; they do not truncate it.

`bestMatchForAcceptLanguage` accepts an optional header and imposes a 4,096 UTF-16-code-unit limit before parsing. Missing or blank input, an empty normalized list, a `LanguageRangeError`, or more than 32 expanded preferences delegates to `bestMatchFor([])`. HTTP normalization removes empty comma members, trims spaces/tabs at member boundaries and replaces interior tabs with spaces before strict parsing. It preserves weighted negotiation and exclusions for a valid header. A custom matcher's unrelated parser errors or negotiation errors propagate through the throwing API; grammar refusal alone fails soft.

`TranslationOptions.forAcceptLanguage(_:using:)` shares that ingress policy but calls `matchFor` to retain the actual diagnostic result. Unusable headers produce an empty-range unmatched result for the default matcher; no exact fallback match is invented. `forLanguageRanges(_:using:)` negotiates strict supplied ranges immediately, while the existing one-argument factory retains ranges for negotiation during translation. These factories perform no I/O. Instance-dependent supplied-match validation remains at consumption. See [public API qualification](API-COVERAGE.md).

Malformed locale syntax/rebuildability and range grammar use their native `LocaleTagError`/`LanguageRangeError`. Matcher configuration and result invariant refusals use `LocaleMatcherError` with a stable `message` and `kind`. Nonoptional Swift types make Java/JS null-element and null-callback shapes unrepresentable; they do not turn those cases into runtime successes.

## Per-key candidate walk and scope

A package-level candidate-chain helper prepares M5's translation walk separately from negotiation. It adds CLDR ancestors in order, a loaded likely-language/script choice, compatible configured primary-language tiebreakers, and the configured fallback. Unloaded ancestors remain in the walk. Missing tags can be rewritten to elected canonical equivalents, and the final walk deduplicates after rewriting. With loaded `en`, `zh` and `zh-Hant`, appropriate Chinese tiebreakers and an `en` fallback, negotiation of `zh-TW` selects `zh-Hant` while the candidate chain remains `zh-TW,zh-Hant,en`. The fallback is added last but need not move if already present. No mutable negotiation or candidate-chain cache is present in M3.

M3 does not implement per-key translation, placeholder evaluation, runtime locale suppliers or loading transports. Its protocol, retained result identity and candidate helper support that later integration.

## Qualification

The frozen shared audit covers all 312 `matchFor` and 31 `Accept-Language` cases, comparing requested order, governing range and weight, relationship, fallback and considered locales as well as refusals. Native standalone checks also exercise measured Java anchor/semantic-group witnesses absent from that corpus, composed IANA language plus region/variant aliases, fallback election, candidate-chain ordering, constructor refusal priority, retained result identity, signed-zero/NaN behavior, custom protocol failures and typed locale identity collisions. XCTest invokes those standalone checks and adds typed configuration, range barriers, error-phase, result equality/hash and concurrent immutable-use checks.

```sh
swift test
swift run LokalizedConformance --self-test
swift run LokalizedConformance --audit --reference Reference
```

The overall shared audit remains incomplete while later milestones are unimplemented; an incomplete report exits with failure and explicitly lists pending cases. Locale-table and equivalent-table generators and their independent development audits are documented in the linked data documents. Passing matcher vectors does not stand in for those full data checks or later translation qualification.
