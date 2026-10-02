# Ordered preferred-language selection

`PreferredLanguageChooser.chooseLocaleForPreferredLanguages(_:using:)` accepts an injectable ordered `[String]` and any `LocaleMatcher`, returning a `LocaleMatchResult`. It preserves the JS chooser's operation name while exposing Swift's existing diagnostic result instead of returning only a tag. `chooseAppleLocale(using:)` is the native counterpart to `chooseBrowserLocale`: it samples `Foundation.Locale.preferredLanguages` when called and delegates to the injectable chooser. Foundation supplies preferences only; pinned Lokalized services perform matching. Neither `Bundle.preferredLocalizations` nor Foundation's locale matcher elects a catalog.

```swift
let match = try PreferredLanguageChooser.chooseLocaleForPreferredLanguages(
    ["zh-TW", "en"], using: strings)
let result = try strings.getResult("welcome", options: .forLocaleMatch(match))

// Explicit system-preference acquisition, when desired:
let systemMatch = try PreferredLanguageChooser.chooseAppleLocale(using: strings)
```

The chooser examines at most **32 raw entries**, most preferred first. Malformed entries consume a slot and are skipped. For every valid native locale tag, it calls strict direct `matchFor` with the original preference spelling. A genuine match ends the walk; an unsupported preference does not silently become the configured fallback and block later entries. Raw spelling is retained to avoid a second Java-compatible normalization changing uppercase `UND` followed by private use.

When no entry matches, the chooser returns `matcher.matchFor([])` unchanged. A conforming matcher reports `.noMatch`, no selected locale/range/weight and its resolved fallback. Its considered locales, original typed locale carriers and result reference remain intact. Diagnostics on a successful selection describe that direct request; exhausted preferences produce the empty-range result rather than a fabricated weighted preference list.

This helper is distinct from strict weighted whole-list negotiation and the fail-soft HTTP-header convenience. It does not parse weights, expand the input list through IANA equivalents, or reorder preferences. Those routes can elect different locales: over `{en, nsi, nsl}`, direct `sgn-NO` selects `nsl`, while the IANA-expanded weighted header selects `nsi`. Direct `zh-cmn` and the expanded header can likewise select `cmn` and `zh`. The 33rd preference is silently unexamined, while a strict matcher list of 33 ranges throws and an oversized HTTP preference input uses its fail-soft behavior.

Native malformedness includes complete tag syntax and Java-compatible builder rebuildability, using `LocaleTag`. The JS convenience's preliminary `normalizeTag` checks syntax only; its internal direct kernel can accept non-rebuildable legacy `lvariant` values. Swift skips a value such as `en-x-lvariant-NY`, consistently with its strict public matcher boundary. This is an explicit native helper adaptation; Java has no ordered-preference convenience to replay. Unknown but syntactically valid languages remain valid inputs and may produce no match.

Only the chooser's own tag-validation error is skipped. Every exception from a custom matcher propagates, including an error whose type is `LocaleTagError`; the chooser does not catch matching calls and mistake their failures for malformed input. The empty-range fallback call can throw too. The Apple convenience preserves the same error contract.

The injectable helper reads no process preferences, mutates no runtime and retains no global configuration. Independent per-view and per-request choices can coexist against the same immutable `Strings` instance. Read UI-owned preferences on their actor, make the match there and pass `.forLocaleMatch(match)` to a lookup. Alternatively, snapshot preferences into a `Sendable` value before capturing them in a shared matcher-aware supplier. No `MainActor.assumeIsolated` bypass is needed. The system convenience reads Foundation's ordered preference list only when explicitly invoked; an already constructed runtime changes behavior only through its chosen suppliers/options or by replacing the immutable instance.

`ConformanceRunner.preferredLanguageSelfTest()` qualifies raw limits, malformed-entry handling, first-match order, honest fallback diagnostics, resolved fallback election, raw `UND` preservation, direct/weighted differences, custom exception identity and forty concurrent independent contexts. XCTest additionally executes the real Apple preference accessor without assuming a host language, verifies error propagation from the convenience and exercises two explicit language contexts on one runtime. These native checks add no fabricated passes to the frozen donor corpus.
