# Swift API mapping and M7A status

The public vocabulary follows the frozen [naming policy](../Reference/API-NAMING.md). The mechanically generated [API inventory](../Reference/api-inventory.json) records 53 externally public Java types and nine JavaScript code entry points, with 127 runtime-export occurrences across those entry points. Repeated exports are intentional; they are not 127 distinct concepts. Java package-private helpers and unexported JavaScript declarations are excluded.

This document separates the implemented M0–M6 and M7A APIs from planned verified network delivery. Whole-runtime qualification compares every recorded translation observation separately from component checks.

## Reference identities

| Reference | Frozen identity | Use |
|---|---|---|
| Java public API | 3.1.1, commit `491346ba50df65e1e51791f21246ff8bc47e44e9` | Features, method signatures, callback and observer vocabulary |
| Java corpus oracle | 3.1.0, commit `63b63e47c982f7a87873c52ac2289cc0392f3329` | Recorded behavioral expectations; retain the three documented 3.1.1 walk regressions |
| JavaScript public API and transports | package 1.0.0-rc.2, commit `617670da887b0c684e2589882447b6b93297f2f7` | Reviewed HEAD, including unreleased manifest/stamp renames; package version alone is insufficient |
| Corpus | 1.1.0; 2,381 cases, 586 fixtures | 2,155 required portable and 226 informational IDs; zero implementation-specific IDs |
| Data | CLDR 48.2; IANA registry 2026-09-17 | Exact fingerprints in [baseline.json](../Reference/baseline.json) |
| Identifier policy | Unicode 15.0 | Generated runtime identifier tables pinned to the Java 21 oracle's category policy |

`baseline.json` pins individual reference artifact hashes and the known corpus gaps. The independent API inventory content SHA-256 is `41a9424592ce7b22b0d909ad6192dcb77b782e02e7f4e4d3099c34f0158ee9ed`. It also records source-file hashes, Java's compile-only annotation inputs, the compiler, and each exported declaration's source location.

Regeneration uses clean source checkouts, a fresh isolated Java 21 `javac --release 9` build followed by `javap -public -constants`, and Node's built-in module loader to inspect actual JavaScript entry exports. It resolves public `.d.ts` export/re-export declarations rather than treating every internal type as public. No npm install or Python package is required. The cached Java annotation JARs are development-only census inputs, never Swift consumer dependencies.

```sh
python3 Tools/api_inventory.py --check
python3 Tools/api_inventory.py --refresh --source-root /path/to/workspace --java-home /path/to/jdk21
```

The first command needs only Python's standard library and this checkout. The second is an explicit development operation requiring the pinned sibling repositories, Java 21, Node, and the Java source's compile-only annotation JARs; `--annotation-classpath` can specify their locations.

## Implemented public foundation

| Public API | Implemented behavior | Limit of this implementation |
|---|---|---|
| `BuildMetadata.current` | Immutable build identity with producer, CLDR, IANA, corpus, and identifier-Unicode fields | Describes the intended baseline; metadata does not certify data-backed matching or plural evaluation |
| `ExactString` | String-literal construction; exact UTF-16 equality, hashing, ordering and length; access to the original `String` | All catalog/placeholder keys use this carrier; ordinary Swift dictionaries keyed by `String` still use native canonical equivalence |
| `LanguageFormAxis`, `LanguageForm` | Ten axes, raw wire tokens, portable display names | Package-visible expression evaluation is implemented in M4 |
| `Cardinality`, `Ordinality`, `Gender`, `GrammaticalCase`, `Definiteness`, `Classifier`, `Formality`, `Clusivity`, `Animacy`, `Phonetic` | All 61 forms as `CaseIterable`, immutable, `Sendable` enums; cardinal/ordinal services below | Selection is internal; public `DefaultStrings` translation is implemented |
| `BidiIsolation` | `.disabled`, `.rtlLocales`, `.always`, preserving `"none"`, `"rtl-locales"`, `"always"` raw values | Implemented with donor/request locale direction, per-template caller caching and bounded FSI/PDI repair |
| `LocaleMatchType` | All eight match-kind values; `.noMatch` preserves `"none"` | Negotiation is implemented below; public per-key translation is implemented in M5 |
| `TranslationRuntimeLimits` | Default budgets, hard ceilings, validated initialization, typed `ValidationError` | Expression compilation/evaluation and fragment resolution apply instance budgets; complete runtime applies these budgets |

## Implemented M1 catalog APIs

| Public API | Implemented behavior | Adaptation or scope |
|---|---|---|
| `LocalizedString` | Immutable key, optional translation/commentary, placeholder map, ordered alternatives; exact UTF-16 equality/hash for all authored text | Throwing initializer enforces the constructor's translation-or-alternative requirement. Catalog validation enforces schema, templates and expressions |
| `PlaceholderDefinition` | Closed `.languageForm` / `.expression` sum | Prevents mixed placeholder modes at typed construction; JSON still rejects mixed or null fields at runtime |
| `LanguageFormTranslation`, `LanguageFormTranslationRange`, `LanguageFormValue` | Value/range selectors and typed branches across all ten axes | No Java builder; native immutable initializers. Mixed axes and invalid selectors are refused by catalog validation |
| `ExpressionTranslation`, `ExpressionAlternative` | Translation-only fragment or nonempty ordered expression alternatives | Explicit empty alternatives are refused by the constructor; fragment templates and expressions are validated when admitted to a catalog |
| `LocalizedStringLoader.parse` | `Data`, `String`, caller-owned `InputStream` and owned regular-file entry points; strict UTF-8/JSON, duplicates, unknown fields, templates, eager expressions, source diagnostics and warnings | Overloads replace Java stream/reader plumbing and JS `parseStrings` vocabulary; native byte inputs share bounded parsing and retain canonical file provenance |
| `LocalizedStringLoader.defineCatalog` | Validates typed definitions and emits warnings using the same schema rules | Typed input has no fabricated byte or JSON nesting charge. Placeholder dictionaries traverse in UTF-16 key order; parsed files retain authored order. Shared nodes/deeper placements are memoized as in JS; alternative edges still consume the budget |
| `LocalizedStringLoader.mergeParsedStringsFiles` | Requires one exact normalized locale, deduplicates whole equal definitions, unions origins, rejects conflicts, applies model budget after dedup | Same shard behavior as JS; no implicit winner |
| `ParsedStringsFile` | Immutable locale, sources, strings, exact-key origins and warning snapshot | Construction is internal so callers cannot forge a validated record |
| `LocalizedStringLoader.loadFromDirectory` / `loadFromResources` / `loadFromBundle` | Immediate ordinary directory discovery, explicit locale-to-URL maps and explicit bundle-relative paths; canonical provenance and shared budgets | Apple resource acquisition replaces JVM classloader resolution; the 159 classloader observations remain pending native mappings |
| `PreferredLanguageChooser` | Injectable ordered preference matching and `chooseAppleLocale(using:)`; retained match diagnostics and 32 raw-entry cap | Native counterpart to JS browser acquisition; direct matching is distinct from weighted range/header expansion |
| `LocalizedStringLoadingOptions` | Eight validated loading/discovery budgets; byte and character limits kept distinct | Each direct parse/define/merge owns a session; M6 directory/Bundle/map calls share aggregate accounting across files |
| `StringsParseError` | Message, source, optional one-based line/UTF-16 column, bounded duplicate path and underlying cause | Native error type replaces Java loading exception; the conformance adapter explicitly projects the recorded Java class name |
| `LocalizedStringWarning`, `LocalizedStringWarningHandler` | Cardinal/ordinal warning fields and a synchronous throwing `@Sendable` callback | Public missing-form order follows enum order. The corpus adapter sorts that set field as the Java oracle does; callback errors propagate unchanged |

The strict JSON reader retains ordered/duplicate members and untouched number lexemes. Expression compilation is package-visible and creates validated postfix instructions, an immutable evaluation tree and exact numeric literals; M4 evaluates it with true short circuiting. Loader validation uses the hard ceilings (4,096 UTF-16 units, 512 tokens, depth 64); M4 instance compilation separately enforces the lower configured lookup budgets. [Identifier data](IDENTIFIER-DATA.md) is generated from the pinned Unicode 15.0 policy. Catalog normalization and warnings now use the complete pinned locale kernel and plural services.

## Implemented M2 numeric and plural APIs

| Public API | Implemented behavior | Adaptation or scope |
|---|---|---|
| `ExactDecimal` | Bounded arbitrary precision, preserved scale, exact comparison/remainder and BigDecimal-compatible canonical/plain rendering | Representation equality includes scale; numeric comparison uses `compare(to:)` |
| `NumericValue` | Closed signed/unsigned integer, arbitrary integer text, exact decimal, Float and Double carriers; validated text factories | Native initializers replace generic Java `Number`; Float keeps binary32 semantics |
| `PluralOperands` | Exact `n/i/v/w/f/t/c/e`, visible-place controls, signed source mantissa and compact expansion | Immutable throwing initialization and `forNumber` conveniences replace a mutable builder; supplied limits apply at construction |
| `Cardinality.forNumber/forOperands/forRange`, `Ordinality.forNumber/forOperands` | Complete generated CLDR 48.2 rules with exact numeric evaluation and pinned locale aliasing | No host plural engine and no optional data imports |
| Supported-category and locale-tag methods | Enum-ordered forms, sorted direct tags, root ordinal fallback for cardinal-supported locales | Unsupported well-formed category queries return empty; classification throws `UnsupportedLocaleError` |
| Cardinal integer/decimal and ordinal integer example helpers | Ordered exact values with preserved decimal scale and infinite flags | Matches Java helpers, including the distinction between finite and infinite empty samples |
| `Lokalized.Range<Value>` | Immutable ordered sample values, `isInfinite`, sequence and conditional equality/hash/Sendable | Qualify `Lokalized.Range` when Swift's interval type would be ambiguous |
| `NumericError`, `UnsupportedLocaleError`, `PluralLocaleError` | Typed numeric admission/rounding, data-support and syntax refusals | Corpus adapter explicitly projects only known native error kinds to Java observations |

See [numeric semantics](NUMBERS.md), [plural provenance and qualification](PLURAL-DATA.md), and [floating-point conversion](FLOATING-POINT.md). Default limits and hard ceilings are checked before derived padding. The upcoming runtime must revalidate externally constructed operands against instance limits; public static classification consumes an already validated operand.

## Implemented M3 locale APIs

| Public API | Implemented behavior | Adaptation or scope |
|---|---|---|
| `LocaleTag` | Strict complete tag validation; separate lenient `forLanguageTag`; JDK locale fields/identity, CLDR aliases, likely subtags, parents, validity and RTL | Replaces Java's `Locale` carrier. Authored catalog identity uses JDK projection; CLDR aliases do not merge catalogs |
| `LanguageRange` | Immutable extended range, pinned ROOT lowercase, weight validation, Java diagnostics and rendering | Construction does not expand equivalents. NaN copies preserve identity; signed-zero hashes obey Swift's equality contract |
| `LanguageRangeEquivalents` | `.ianaRegistry` default and `.jdk` compatibility data | Java 21 data is pinned explicitly because Swift has no host JDK |
| `LocaleMatcher` | Named strict matching/parsing and best-match operations; fail-soft Accept-Language convenience | `String` ingress is strict; `LocaleTag` supports deliberate prior lenient projection. Custom matcher failures propagate according to the HTTP helper contract |
| `DefaultLocaleMatcher` | Immutable supported locales, fallback election, exact tiebreakers, weighted/excluded/wildcard matching and contextual supplied-result validation | Matching limit is 32 expanded ranges; HTTP input limit is 4,096 UTF-16 units. Translation candidate walk is package-visible for M5 |
| `LocaleMatchResult` | Immutable reference type with constructor invariants, diagnostics and retained supplied-result identity | A no-match result has no elected locale; `bestMatchFor` returns the fallback separately |
| `LocaleTagError`, `LanguageRangeError`, `LocaleMatcherError` | Typed syntax, range and configuration refusals with portable diagnostics | Typed Swift collections cannot represent Java null elements; raw adapter refusals are not blanket native mappings |

See [locale data](LOCALE-DATA.md), [range parsing](LANGUAGE-RANGES.md) and [matching](LOCALE-MATCHING.md) for the contract distinctions and independent evidence.

The library product is `Lokalized`. `LokalizedConformance` is a standalone development executable with XCTest wrappers. `--self-test` checks implemented behavior without XCTest; `--inventory` reports the frozen corpus inventory. `--audit` compares 2,197 implemented cases and enumerates 184 pending loading/native-representation cases. It exits 1 with `incomplete`; no failures or native representation mappings are accepted by the M6 gate. `--plural-data` separately executes the exhaustive pinned CLDR audit; `--locale-data` audits the pinned locale tables/goldens; `--resolution-components` reports the limited single-catalog projection described below; `--runtime-adapter` inventories full translation observations and explicit pending input guards; `--loader` compares 145 native filesystem cases and records 164 pending carrier/ordering cases with actual and frozen observations for five native differences. Every output field is compared. Input materialization preserves the original fixture bytes and authored member order; it never consults expected observations. `--report PATH` preserves JSON evidence.

## Implemented M4 value and resolution APIs

| API | Implemented behavior | Adaptation or scope |
|---|---|---|
| `PlaceholderValue` | Explicit null/text/Boolean, integral widths, exact numeric values, plural operands, all ten language forms and custom display values | The immutable `Sendable` caller snapshot remains separate from generated text. `Int8`/`Int16`/`Int32` preserve diagnostic widths; other integers use `NumericValue` |
| `PlaceholderConvertible` | Throwing display conversion with the remaining UTF-16 output budget and a diagnostic type name | Custom values are display-only; expressions/selectors refuse them. Pass explicit `.text` for phonetic input |
| `PhoneticResolver` | Synchronous throwing `@Sendable (String, LocaleTag) -> Phonetic` | Receives raw caller text and the supplying catalog locale; no global callback memoization. Nonoptional return mappings remain unratified |
| `TranslationEvaluationError` | Immutable reference with `.expression`, `.invalidArgument`, `.invalidState`, exact message and retained `cause` | Replaces the ambient Java exception hierarchy. Recognized failures acquire nested context; unrelated application errors and `UnsupportedLocaleError` propagate unchanged |
| Package expression/compiler/scanner/catalog kernels | Eager instance compilation, exact typed comparisons, short circuiting, first-match terminal branches, inherited/replaced scopes, breadth-first generated selection followed by recursive expansion | Like Java's internal evaluator/interpolator, these are package-visible. Public `Strings` integrates negotiation/fallback, results/failures/handlers/observers, inspection and bidi in M5 |

Parsed models retain authored placeholder declaration order internally, while typed dictionaries use deterministic UTF-16 order. This order affects eager compilation diagnostics; it is excluded from public model equality/hash. Shared nodes compile once by storage identity.

[Expression qualification](EXPRESSIONS.md) and [fragment qualification](FRAGMENTS.md) cover native discriminators and the separately reported 578 input-selected single-catalog projections. Whole-runtime audit accounting is 2,197 passes and 184 pending IDs. The narrower projection omits match/result envelopes, fallback policy, handlers, retained result/failure identity, observers and bidi; the main audit and native runtime checks qualify those channels separately.

## Runtime APIs and remaining delivery

The table distinguishes implemented runtime/local APIs from remaining conveniences and verified manifest delivery; see [runtime contracts](RUNTIME-API.md) and [runtime semantics](RUNTIME-SEMANTICS.md) for exact signatures and native adaptations.

| Java / JavaScript concept | Swift surface and disposition |
|---|---|
| `Strings`, `createStrings`, Java `Strings.Builder` | Public `Strings` protocol and immutable `DefaultStrings` implementation; synchronous throwing `get` / `getResult`, `StringsConfiguration` initializer instead of a Java builder |
| JS `t` | Optional convenience alias; `get` remains the shared operation. JS currently makes `t` the same function as `get` |
| `TranslationOptions`, `forLocale`, `forLocaleMatch`, Java per-call ranges | `TranslationOptions` with `forLocale`, `forLanguageRanges`, `forLocaleMatch` option factories. These are per-call options, not bound `Strings` views |
| `localizedStringSupplier` | Supplies catalogs once during construction; do not call it on every lookup |
| `localeSupplier`, `localeMatchSupplier` | Named callbacks with a matcher context where needed. Preserve Java's matcher argument explicitly; JS currently uses closures without a matcher argument |
| `TranslationResult`, `TranslationResultStatus` | Immutable text, requested/resolved locale, match diagnostic, status and failure; exact optional-field semantics. Verified-record provenance belongs to later delivery |
| `TranslationFailure`, reason, policy, handler, response | Shared vocabulary with typed nonoptional decisions/responses, throwing callbacks and preserved causes |
| `TranslationFallbackEvent`, observer, preceding failures | Observer receives a successful fallback event after translation; immutable snapshots and exact candidate/callback order. The shared corpus has no observer cases; native standalone and XCTest evidence checks them |
| Programmatic model conveniences | Core models and `defineCatalog` are implemented above; additional convenience factories can follow the actual consumer API |
| `PhoneticResolver`, warnings and warning handler | Named callback types; `Phonetic.other` is a valid category, not a substitute for an invalid nil callback return |
| Inspection methods | Supported locales, exact keys for one locale, exact missing keys between locales; inspection does not negotiate or translate |
| `LocalizedStringLoader`, JS parse/local loaders | Implemented M6 text/data/stream/file/directory and explicit Bundle/resource maps; loading options, warnings and limits. JVM classloader/JAR behavior remains pending native carrier mappings |
| JS preferred-language/browser chooser | Apple preferred-language adapter plus portable preferred-language chooser; UI state read on its actor and supplied explicitly |
| JS `StringsManifestV1`, identity and loading | Native manifest parsing/validation, JCS/SHA-256 identity, plan/chain/fetch set, subset and entire loading, immutable loaded records, partial diagnostics and cancellation |
| JS directory-to-manifest publishing | Development macOS publishing command; consumer loads do not require it |
| JS `createSsrStamp` / `validateSsrStamp` | Preserve identity/provenance needed by native results and transferred verified records. Defer a native producer-only SSR stamp API until a concrete consumer exists; SSR is a JS transport-specific API |
| JS data subpath imports | All ordinal/range data included in the Swift runtime; no caller prerequisite imports or package dependencies |
| JS metadata exports and configuration snapshots | Expose independent build metadata plus runtime `localeDataMode`/`cardinalityMode`, settings and immutable effective configuration when those runtime services exist |
| i18next/plugin interoperation | JavaScript integration; Swift gets platform-appropriate UI adapters with deliberate error display policy |

### Per-call locale source and nil semantics

The implemented per-call locale source is a mutually exclusive sum: direct locale, language ranges, or a presupplied `LocaleMatchResult`. Constructing one options value cannot silently overwrite an earlier source or contain two simultaneously active sources. The immutable options initializer and factories retain the shared setting names and reject simultaneous locale sources. Absent overrides inherit instance configuration. Nil policy/handler/bidi overrides represent omission; `.disabled` explicitly disables bidi isolation. Assigning nil to one construction supplier must not clear the other supplier.

Match-result validity includes provenance and requested-context rules, not merely structural type validity. Call-scoped matching diagnostics, loaded-record verification and retained failures must remain isolated under concurrent and reentrant calls. Public callbacks should declare `@Sendable` where shared immutable instances use them; actor-isolated state must be sampled on its actor, not accessed through an isolation bypass.

### Native errors, context and identity

| Existing error / failure | Proposed Swift treatment |
|---|---|
| Java `LocalizedStringLoadingException`; JS `StringsParseError` and local I/O failures | `StringsParseError` for decoding/schema/budget failures; `LocalizedStringLoadingError` for native discovery/I/O/resource/duplicate failures. Both retain source/message and available immediate causes. The conformance projection records this phase distinction explicitly |
| JS manifest aggregate `LocalizedStringLoadingError` | M7 will extend native loading diagnostics with deterministic ordered failures preserving stage, resource and cause |
| JS `ConfigurationError`; Java invalid configuration arguments/state | Typed configuration validation; map invalid-argument versus invalid-state semantics in diagnostics, without inventing Java exception class identity |
| `ExpressionEvaluationException` / `ExpressionEvaluationError` | Implemented `TranslationEvaluationError(kind: .expression)` with exact context and retained cause |
| `MissingTranslationException` / `MissingTranslationError` | `MissingTranslationError` under the throwing failure policy, carrying the recorded translation failure |
| `UnsupportedLocaleException` / `UnsupportedLocaleError` | `UnsupportedLocaleError` for the same data-support refusal phase |
| JS `ResolutionError`, Java retained invalid argument/state causes | Implemented `TranslationEvaluationError` kinds `.invalidArgument` / `.invalidState`; M5 retains the first resolution cause and reuses it when the handler rethrows |
| Application errors thrown by policy, handler, supplier, resolver or observer | Propagate the original thrown error through the required callback precedence; do not wrap away its identity or payload |
| Invalid nil callback return | Compile-time mapping only after typed API and negative-compile evidence; no invented runtime error in the runner |

`StringsParseError`, `CatalogModelError`, loading/runtime limit validation errors and package-visible reader/compiler errors exist in M1. The M4 evaluation taxonomy is implemented above; public translation failures are implemented in M5; M6 adds `LocalizedStringLoadingError` with discovery/I/O/invalid-resource/duplicate-locale kinds and immediate native causes. Verified-delivery errors remain planned. Expected error/context fields require explicit comparisons; an error-name-only match cannot pass a corpus case. Identity-sensitive result and cause objects require immutable reference carriers or another documented identity projection; value equality is insufficient for a test that requires the same retained object. NSError/Foundation bridging is not an identity guarantee.

### Null and typed callback cases: explicit dispositions

The baseline proposes ten native representation mapping candidates. None is ratified or counted as mapped in M6. Negative-compile consumers now qualify eight actual type boundaries, without substituting for callback timing or approving per-ID mappings. Each requires a compiler-negative consumer example against the actual nonoptional public callback type, with the relevant operation/input and error-context difference documented. Runtime timing and callback traces from Java remain visible obligations; a compile-time mapping does not replay them. Mappings must be recorded per ID and approved as part of the shared contract before a future release claim.

| Required corpus ID | Proposed disposition after typed API exists |
|---|---|
| `null-callbacks.handler.null-response-is-rejected-after-the-walk` | Nonoptional handler response rejects nil at compile time; preserve after-walk handler ordering in separate representable cases |
| `null-callbacks.policy.null-decision-carries-the-resolution-failure-cause` | Nonoptional policy decision rejects nil; cause retention needs separate runtime evidence |
| `null-callbacks.policy.null-decision-is-rejected-at-the-consultation` | Nonoptional policy decision rejects nil; consultation timing needs runtime evidence |
| `null-callbacks.policy.null-decision-propagates-out-of-get` | Nonoptional policy decision rejects nil; throwing `get` remains required |
| `null-callbacks.precedence.the-null-policy-is-rejected-before-the-null-handler` | Both returns reject nil; policy-before-handler precedence needs runtime evidence |
| `callback-interaction.null-resolver.first-of-two-identical-type-causes-is-retained` | Nonoptional resolver category rejects nil; distinguish first retained cause from later same-type errors |
| `callback-interaction.null-resolver.retained-null-failure-rethrown-verbatim` | Nonoptional resolver category rejects nil; identity-sensitive rethrow needs representable runtime evidence |
| `callback-smoke.resolver.null-return-is-rejected` | Nonoptional resolver category rejects nil; do not coerce it to `.other` |
| `phonetic-resolver.constants.unmapped-term-returns-null` | Nonoptional resolver category rejects nil; absence in a resolver's own map is the caller's explicit decision |
| `phonetic-resolver.expression.null-return-diagnostic` | Nonoptional resolver category rejects nil; expression-resolution context needs runtime evidence |

Those ten are not an exhaustive inventory of nil-related behavior. Additional typed construction and input cases must be classified independently:

| Required corpus ID / group | Obligation |
|---|---|
| `owed-init-defaults.accepts.null-locale-supplier-does-not-clear-the-match-supplier` | Representable optional nil setting; retain the configured match supplier |
| `owed-init-defaults.accepts.null-match-supplier-does-not-clear-the-locale-supplier` | Representable optional nil setting; retain the configured locale supplier |
| `phonetic-resolver.input.explicit-null` | Explicit null placeholder/input is representable; runtime failure is required |
| `owed-construct.refusal.catalog-null` | Typed required catalog rejects nil; establish separate negative-compile mapping if the public initializer cannot represent it |
| `owed-construct.refusal.null-catalog-value`, `null-entry`, `null-locale-key` | Classify each against the actual catalog collection/model type; raw JSON null must still be rejected by parsing/validation |
| `owed-init-defaults.refusal.null-tiebreaker-entry`, `null-tiebreaker-language-code`, `null-tiebreaker-list` | Classify each typed collection refusal separately; manifest inputs remain runtime validated |
| `owed-null-options.*` | Nil behavior-key overrides inherit configuration; nil ranges do not create a second locale source |
| `expressions.operand.explicit-null-binding-is-rejected` and null selector/value cases | Runtime failures for an explicit null value, distinct from a missing binding and from a callback return |
| `malformed-structure.*` null cases | Invalid catalog JSON is a runtime parser/schema obligation |

Raw fixture adapters may describe inputs that are impossible through a typed Swift API, but must not manufacture a runtime pass for such cases. Defaulting nil to a valid category/response, returning expected JSON from a fixture, or blanket-skipping all null cases would erase the contract.

### Exact strings and numeric carriers

Swift `String` equality and hashing canonically equate some precomposed/decomposed spellings. Catalog keys, placeholder names, expression identifiers, exact matching and diagnostic comparisons use `ExactString`/explicit UTF-16 units wherever the reference distinguishes those spellings. No NFC/NFD normalization is implicit. Output remains ordinary `String`, but corpus comparison uses exact units. Parse delimiters as bytes/scalars rather than extended grapheme clusters. Diagnostic offsets and character budgets use the contract's UTF-16 units: `👩‍💻` has five units. Inspection and JCS property names sort by UTF-16; the proposed deterministic directory order uses UTF-8 bytes and is documented separately.

Swift enum cases use lower camel case while wire tokens and portable display names remain exact: `Gender.masculine.rawValue == "GENDER_MASCULINE"`, `displayName == "MASCULINE"`. `GrammaticalCase` and `.grammaticalCase` avoid the Swift `case` keyword. `BidiIsolation.disabled` and `LocaleMatchType.noMatch` preserve the wire value `"none"` while avoiding ambiguity with `Optional.none` in optional APIs.

Implemented numeric values preserve distinct integer, binary32 `Float`, binary64 `Double`, exact decimal text and explicit operands; the M4 placeholder sum adds null and nonnumeric carriers. Widening a `Float` to `Double` changes its reference rendering/operands; native default number descriptions are not the pinned Java stringification contract. `Foundation.Decimal` alone cannot preserve arbitrary precision, scale or visible trailing zeros. Exact decimal text such as `"1.00"` retains its two visible fractional digits. The default `compactExponent` is 0; the default maximum compact-exponent budget is 64. Explicit operands are validated on construction against supplied limits and must be validated again at lookup against the evaluation instance's limits. Locale-aware date/currency formatting is caller work and should enter as explicit formatted text.

### Loading, identity and platform adaptations

Bundle loading takes an explicit consumer bundle and resource directory; `Bundle.module` in the library cannot locate another package's resources. M6 qualifies a constructed framework-style bundle, real packaged main apps and a real caller SwiftPM bundle; additional application packaging recipes require their own qualification. Preserve subdirectories with consumer `.copy` resources and enumerate valid extensionless locale files as well as supported named files. Native file/Bundle loading adapts Java classpath semantics without exposing a classloader. Unsupported archive-container features need a documented transport disposition, not a claim of classpath parity.

Manifest APIs stay in full runtime scope. Freeze the reviewed HEAD wire contract and golden canonical bytes/digests before implementation: HEAD uses `tiebreakerLocalesByLanguageCode` in the fingerprint projection and `localeMatchResult` in stamps, whereas the published package has earlier names under the same format version. Preserve the distinction between `chain` (including absent attempted candidates), `fetchSet` (declared files in first-use order), the plan, the actual `LoadedStrings` fields, and construction-time load-verification/coverage records. Loaded records include catalogs, fallback/tiebreakers, whole-manifest locale configuration, identity, data pins, limits, coverage, requested files, failures, warnings and completeness. Revalidate them at construction; a claimed identity is not trusted provenance.

Use the seven declared failure stages (`fetch`, `read`, `limit`, `digest`, `decode`, `parse`, `validate`) as a public vocabulary. Reviewed JS currently emits five: decoding/catalog validation are included in `parse`; a Swift refinement needs an explicit mapping. Verify delivered body bytes before parsing, retain deterministic plan-order diagnostics, bound active reads and sizes, and reject partial loads if the fallback failed. `URLSession` and Apple system CryptoKit are permitted platform facilities; adding `swift-crypto` or any other package violates the zero-dependency requirement. Foundation URL resolution must be qualified against the accepted manifest URL contract.

Swift structured cancellation should complete promptly even if an injected transport ignores cancellation. This is a documented native strengthening: the reviewed JS abort path can remain pending for a nonsettling transport. The Swift design must define task ownership and bounded cleanup rather than relying on a cooperative transport as the only way out.

Apple's `Locale.preferredLanguages` is an ordered source of tags, not the matching implementation. Apply pinned semantics to each direct preferred entry, then resolve fallback; malformed entries and expansion limits follow the documented preferred-language versus strict-range policies. Keep browser header acquisition and JavaScript plugin APIs in their own platform integrations. The proposed Swift UI helper must use an explicit thrown-error display policy so a nonthrowing rendering function does not silently discard a configured throwing failure handler.

See [Apple local delivery](APPLE-LOCAL-DELIVERY.md), [local ownership/budgets](LOCAL-LOADING.md), [ordered preferences](PREFERRED-LANGUAGES.md) and [native loader observations](LOAD-ADAPTER.md) for implemented M6 contracts.

## M6 qualification and remaining coverage

The package declares Swift tools 6.2, Swift 6 language mode, iOS 15 and macOS 12, with no external package dependencies, build plugins or binary targets. Consumer builds need neither Reference artifacts, Java/Node nor network resolution. Python development checks use only the standard library. The fresh-copy build checks that the package builds without the reference archive; it does not claim to have measured all network traffic.

CI selects a documented Xcode 26.0.1 path on `macos-15` for an actual Swift 6.2 compiler run, plus the current `macos-26` hosted default and reports its actual version. It runs build/tests, standalone self-test/inventory/audit and exhaustive CLDR qualification, archive/API/identifier/materialization/plural/locale/range checks, Java-derived floating/locale/range goldens, a fresh package and consumer build/run, the direct iOS/macOS deployment/link probe and actual packaged SwiftPM/Apple app resource consumers. The behavioral audit must exit 1 and enumerate all IDs; CI checks the exact 2,197 whole-runtime passing-ID set, the 1,432-ID runtime adapter inventory, 145-ID native load ratchet and separate 578 component-projection ratchet and rejects failures, omitted IDs, arbitrary native mappings or a claim of completed parity. Update that ratchet only alongside real new runtime comparisons.

The local installed toolchain is Swift 6.4 / Xcode 27; it cannot establish minimum-compiler coverage. Hosted CI configuration remains unexecuted until GitHub runs it. [Deployment evidence](DEPLOYMENT.md) records successful compilation/import/link inspection of all four triples and current-host arm64 execution; emitted deployment versions are compilation evidence only. Older iOS/macOS runtime execution, Intel execution, XCTest's separate framework floor, verified transports, decomposed strings through future network ingresses and release-wide portable behavior remain qualification work. An M6 CI pass qualifies the core runtime, local delivery and an honest incomplete report; verified delivery and release qualification remain pending.

## Implemented M7A manifest foundation

| Public API | Implemented behavior | Scope or adaptation |
|---|---|---|
| `StringsManifestV1`, `StringsManifestFile` | Immutable manifest/file claims using the pinned format version 1 wire fields | Initializers do not seal or verify claims; all validation/planning doors revalidate |
| `StringsManifestValue`, `StringsManifestMember` | Ordered decoded JSON shapes with exact keys, nulls and binary64 schema numbers | Preserves JS property order/last-value semantics; source parser independently rejects duplicates |
| `parseStringsManifest` / `validateStringsManifest` | Data/text, decoded object and typed claim doors; schema, complete tiebreakers, elected fallback, all seven data pins and recomputed fingerprint | Native raw parser error taxonomy/cause adaptations are explicit; unknown members drop as in pinned JS |
| `CatalogIdentity`, `CatalogIdentityInputV1` | Exact version/fingerprint identity and typed narrow projection input | Arbitrary exact identity keys are independent of manifest locale recognition; unrepresentable dynamic JS shapes remain inventoried |
| `computeCatalogIdentity` / `catalogIdentityBytes` / `catalogIdentityInputFor` | Full SHA-256, exact canonical UTF-8 and named manifest field projection | System CryptoKit, narrow JCS with fixed numeric 1, no I/O or verified content claim |
| `ManifestLocaleConfiguration`, `localeConfigurationForManifest` | Full declared matching configuration with elected fallback and explicit ties | Keeps serialized case-distinct variant keys; public native matcher retains its stricter typed constructor |
| `chain` / `fetchSet`, `FetchEntry` | Absent attempted candidates versus manifest-backed first-use fetch entries, with serialized absolute URLs and optional decoded sizes | Raw string lookup preserves pinned JS normalization behavior; unfinished Unicode/punycode hosts are refused explicitly |

See [manifest validation](MANIFEST-VALIDATION.md), [identity](MANIFEST-IDENTITY.md), [planning](MANIFEST-PLANNING.md) and the separately frozen [contract archive](MANIFEST-CONTRACT.md). `wholeManifestPlan` remains package-only preparation for the future complete loader. Network transport, `LoadedStrings`/verified records, partial-load policies, cancellation and publishing remain unimplemented.
