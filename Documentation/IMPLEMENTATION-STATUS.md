# Implementation status

October 5, 2026. M0–M6 are implemented: package/reference/conformance foundations, immutable models, catalog parsing/validation/merging, exact numbers, complete generated plural rules, pinned locale negotiation, expression evaluation, recursive fragment resolution, the public synchronous translation runtime, bounded local delivery and Apple preferred-language acquisition. M7A adds manifest models, parsing/validation, canonical identity and deterministic load planning. M7B1 adds Unicode/punycode host processing with pinned mapping, normalization and compatibility properties. Swift network delivery is outside scope: loading follows Java's local model, with remote acquisition owned by applications.

## Implemented behavior

- SwiftPM library `Lokalized`, Swift tools 6.2, Swift 6 language mode, iOS 15 and macOS 12 declarations; zero external package dependencies or plugins.
- All ten language-form axes and 61 forms, shared raw tokens/display names, bidi/match-kind enums, validated loading/runtime limits, pinned metadata and exact UTF-16 string keys.
- Immutable localized-string, language-form and expression-fragment models. Every authored text field participates in exact equality/hash; maps ignore insertion order and alternatives retain order. Deep/shared model graphs use iterative equality/hash.
- Public `LocalizedStringLoader.parse` overloads for `Data` and `String`: strict UTF-8/JSON, exactly one leading BOM, paired escaped surrogates, ordered/duplicate members, unknown-field/schema refusals, template references, source-aware errors and incomplete cardinal/ordinal warnings. Byte and UTF-16 reader budgets stay distinct; root/node/warning admission follows the recorded order.
- `defineCatalog` validates typed definitions without fabricated input-byte or raw-JSON budgets. Identity/deepest-placement memoization keeps shared graphs bounded and checks deeper reuse; warnings visit shared nodes once per root. Placeholder dictionaries use deterministic UTF-16 key order; parsed files preserve authored order.
- `mergeParsedStringsFiles` requires one exact normalized locale, deduplicates complete equal definitions before the model budget, unions exact source origins, rejects conflicts and retains original warnings.
- Package-visible expression compilation produces validated postfix instructions, a flat immutable evaluation tree and exact decimal literals. The iterative evaluator preserves left-to-right short circuiting, exact typed numeric/form comparisons and callback order. Loading uses hard ceilings; catalog construction eagerly recompiles all predicates against instance limits.
- Generated Unicode 15.0 identifier classification independent of host OS categories; catalog warnings use the complete generated plural and locale services. Deterministic generators/checkers preserve pins and notices.
- Bounded `ExactDecimal`, distinct integer/Float/Double carriers, exact scale-sensitive representation, comparison/remainder/rendering, plural operands with visible-place and compact controls, and admission/materialization limits. An original exact-integer converter reproduces pinned Java 21 binary-float selection without a host formatter or external library.
- Complete generated CLDR 48.2 cardinal, ordinal and range rules, supported categories/locales and Java integer/decimal sample helpers. Compiled DNF bytecode drives exact evaluation; no runtime JSON or condition parsing. Locale candidate projection uses the complete pinned JDK/CLDR kernel.
- `LocaleTag` distinguishes strict syntax, lenient JDK projection and CLDR canonicalization; complete aliases, likely subtags, parents, validity and RTL tables. Locale identity preserves JDK fields separately from its rendered tag.
- `LanguageRange`, pinned Unicode 15.0 ROOT lowercase, strict Java-compatible header parsing and ordered IANA/JDK equivalence expansion. Constructed ranges do not expand equivalents; strict parsing applies no matcher budget.
- Immutable `DefaultLocaleMatcher`, `LocaleMatcher` protocol and reference-valued `LocaleMatchResult`: weighted ranges, exclusions, wildcards, canonical/fallback/likely matching, anchor reservation, deterministic tiebreakers and fallback election. Supplied-result validation preserves object identity and checks context after constructor invariants.
- Strict matching rejects more than 32 expanded ranges. The HTTP helper normalizes Java whitespace and returns the fallback for malformed or oversized headers (4,096 UTF-16 units / 32 expanded ranges); unrelated custom parser and valid negotiation errors propagate.
- Public `PlaceholderValue`, bounded `PlaceholderConvertible`, typed `PhoneticResolver` and immutable reference-valued `TranslationEvaluationError` with explicit expression/argument/state kinds and retained causes. Custom values are display-only; generated text never replaces the raw caller snapshot used by expressions/selectors.
- Package-only compiled catalog attempts: first-match terminal alternatives, inherited/replaced scopes, all ten form axes, supplying-locale classification, lazy breadth-first generated selection before recursive expansion, cycle/depth/output/cumulative budgets and per-attempt memoization. Missing/null values are refused before caller display/bidi conversion. Parsed placeholder order survives eager compilation; typed maps retain deterministic order. Model equality/hash ignore this traversal metadata.
- UTF-16 interpolation with exact Unicode names, backslash escapes, strict malformed-delimiter diagnostics, lenient failure-key scanning and literal caller replacements. The bounded caller-rendering seam now integrates bidi policy, with isolated custom values cached per template. Shared catalog graphs compile by storage identity; concurrent attempts retain separate state and budgets.
- Public `Strings`/`DefaultStrings`, immutable construction configuration, exact catalog/placeholder collections, per-call locale/options factories, typed results/failures and strict key inspection. Catalog suppliers run once; locale suppliers run per applicable lookup. Semantic admission precedes matching configuration, then eager instance compilation checks each authored root before later duplicates.
- Typed locale candidate walks preserve unloaded ancestors, loaded canonical rewrites and distinct typed carriers with equal rendered tags. Result validation participates in attempt failures as in the frozen Java 3.1.0 baseline. The first resolution cause is retained; pre-walk suppliers and policy/handler/observer errors propagate with reference identity.
- Successful-fallback events are built only after a validated translation from a later candidate; observation does not alter failed walks or resume fallback. Event diagnostics exclude rendered text and caller values. Forty concurrent lookups and same-runtime callback reentry retain isolated attempt state.
- Bidi caller isolation uses supplying-locale direction for translations and requested-locale direction for returned keys, pinned scripts/likely subtags, bounded FSI/PDI balancing and per-template conversion caches. Generated text stays literal. Failure-key conversion is lenient and returns the original exact key if rendering fails; handler replacement strings remain verbatim.
- Portable `StringsDisplayAdapter` requires an explicit nonthrowing error-display policy and retains the original error and lookup inputs. A shared SwiftUI consumer now qualifies explicit Apple Bundle resources and simultaneous language contexts.
- Explicit Bundle directory/resource-path maps, bounded native directory/file/caller-owned stream APIs, aggregate budgets, canonical source provenance and a packaged SDK privacy manifest. Real SwiftPM and iOS/macOS app consumers preserve ordinary catalog paths and both English/French catalogs together.
- `PreferredLanguageChooser` accepts injectable ordered preferences or explicitly acquires Apple preferences. It limits raw entries to 32, skips malformed native tags, preserves direct match identity and returns honest empty-range fallback diagnostics. Independent contexts need no process-wide language mutation.
- Frozen behavioral/data/naming artifacts, a mechanical API census and declaration-preserving input bytes from pinned authored fixtures. The original corpus remains unchanged. The harness compares every observed field, projects only documented native error/set representations, and leaves unfinished operations explicit.
- CI for minimum Swift 6.2 on native arm64 and Intel and a current arm64 hosted compiler, zero-dependency/fresh-consumer checks, generators, exhaustive plural/locale audits, floating/locale/range goldens, deployment inspection, the exact 2,197-ID whole-runtime ratchet, a 1,432-ID full runtime adapter inventory, 145 real filesystem observations and the retained 578-ID component projection. A compiled kernel probe requires the actual native architecture. The October 4 rerun passed the previously failing compiler/check step on both minimum Swift 6.2 tracks and the current track; the full jobs remain in progress at this observation.

## Local verification

Swift 6.4 / Xcode 27 on arm64 macOS 27.0.1 passes **274 XCTest methods** in M8G (273 passed, one filesystem-specific fixture explicitly skipped). The current M8I standalone runner passes **1,057 checks** without XCTest linkage. Coverage includes exact Unicode keys/text/origins, malformed bytes/surrogates/duplicates, delimiter offsets, budget and compiler hard-ceiling boundaries, eager validation/error order, warning callback error identity/reentry, shard conflicts, and 120-level shared model graphs. Numeric checks cover precision beyond Foundation Decimal, exact remainder/comparison, scale and trailing zeros, signed source/compact expansion, rounding refusals, materialization ceilings, revalidation and Float width/subnormal rendering. Six expression tests check all 31 recorded parse-expression diagnostic suffixes, all 61 constants and every generated identifier range boundary/gap. Locale checks cover grammar/rebuildability, distinct field/tag identity, aliases and parents, matching solver witnesses, exclusions, custom matcher propagation, supplied-result refusal order and immutable concurrent use. M4 adds 15 expression methods, 14 fragment methods and two component-qualification wrappers. Its standalone additions are 211 expression checks, 53 fragment checks and 16 independent discriminators, covering callback identity/timing, source versus expanded numbers, all axes, missing/null precedence, exact Unicode delimiters, terminal selections, authored eager priority, 120-level shared graphs and 40 concurrent attempts.

At its completed milestone, M7A added 30 XCTest methods and 178 standalone checks: 19 identity, 118 manifest validation and 41 planning checks. Frozen URL/manifest audits execute separately from the reference-free standalone checks. Final evidence is `.build/reports/m7a-qualification-summary.json`; the four deployment targets inspect 16 Mach-O outputs from 116 pinned Swift sources. Fresh package consumers and real resource consumers pass with zero external dependencies. The final deployment report is `/private/tmp/lokalized-swift-deployment-m7a-report.json`, and real SwiftPM/unsigned Xcode packaging evidence is `/private/tmp/lokalized-swift-local-delivery-m7a.json`.

M6 adds 18 loader methods, six explicit Bundle methods, six preferred-language methods and four load-adapter methods. Its standalone additions are 42 local ownership/budget checks, 54 preferred-language checks and 12 actual filesystem/runtime/projection checks. Canonical-path invalid-byte refusal is exercised directly; the physical invalid-filename symlink fixture cannot be created on this host volume (unsandboxed creation returns EILSEQ) and remains explicitly skipped. Ordinary Unicode filenames, symlinks, FIFOs and all archived physical load fixtures are exercised.

The independent [plural-data audit](PLURAL-DATA.md) passes **24,227 checks**: 12,396 cardinal samples, 2,645 ordinal samples, all 8,064 category-pair cells across 224 direct cardinal locales, support inventories and exact example sequences/scales/infinite flags. The [floating oracle](FLOATING-POINT.md) matches pinned Corretto Java 21 on **103,310** edge/random inputs, with zero differences; the normal self-contained check and native tests also pass 1,592 checked-in raw-bit goldens. The converter's measured throughput is a documented performance tradeoff, not an exhaustive bit-pattern proof.

Reference/API/identifier/materialization/warning/plural/locale/range-table and floating-golden integrity checks pass. A separate 632-case exact-decimal/operand oracle passes, including 97 rounding refusals and the declared negative-scale remainder normalization. A temporary SwiftPM consumer builds and executes public catalog/numeric/plural/locale/value/callback APIs without Reference artifacts or sibling checkouts. All four Apple target triples compile/import/link/inspect successfully; all 16 Mach-O files have the declared floors and only local modules plus Apple system/Swift runtime dependencies. The host arm64 binary executes its public runtime and manifest consumer, 1,030 standalone checks, corpus inventory, both full data audits, all 578 component projections and the 2,197-ID whole-runtime audit. [DEPLOYMENT.md](DEPLOYMENT.md) records the exact evidence and limits. The packaged-consumer tool additionally executes actual SwiftPM `Bundle.module` consumers in Swift 6/MainActor and Swift 5 language modes against the Swift 6 library, builds macOS/iOS simulator/iOS device apps with actual default MainActor/approachable-concurrency settings, verifies catalog and SDK privacy manifest bytes, and executes the packaged macOS `Bundle.main` app. iOS app runtime execution remains unverified.

The [locale audit](LOCALE-DATA.md) passes **263,771 checks**: eleven complete table comparisons covering 18,675 rows and 12,560 independent Java/JDK inputs with 21 observations each. The [range oracle](LANGUAGE-RANGES.md) passes **107,011 observations** with zero differences, plus 3,663 archived constructor/header/casing/weight goldens. Unicode sigma context includes the pinned JDK's supplementary-character boundary behavior. Generator and ordinary golden checks are self-contained; isolated checks reject altered exports, generated tables, goldens and archived oracle sources. Forty-five locale and 69 matcher standalone checks supplement the 29 range checks.

The shared audit enumerates all 2,381 IDs exactly once:

| Disposition | Cases |
|---|---:|
| Runtime passed | 2,197 |
| Native representation mapped | 0 |
| Failed | 0 |
| Unimplemented | 184 |

The passes include **all 149 `parse` cases, all 22 `define` constructor cases, one `languageForms` case, all 105 numeric/plural cases, all 312 `matchFor` cases and all 31 `acceptLanguage` cases**, plus **1,322 `getResult`, 85 `get` and 25 `construct` cases**, plus **145 actual native filesystem `load` cases**. The audit compares real public APIs against every recorded observation field; matcher support comes from actual parsed fixture inputs. Programmatic catalog admission, merge, callback identity, fallback election, candidate walks and supplied-match context have additional native checks. The required portable partition contains 2,155 cases; 226 are informational. The raw runtime audit exits 1 with `incomplete`, retaining its original 184 unreplayed/different inputs. The separate [native contract coverage](NATIVE-CONTRACTS.md) accounts for those inputs without adding runtime passes.

The separate `--resolution-components` audit passes **578 input-selected single-catalog projections** against the same frozen corpus, comparing outcome, exact translation, error category/message/immediate cause and resolver traces. Eligibility follows only fixture/input guards; expected observations never configure execution. The ordered ID SHA-256 is `fe8cbe90b8c000e88f094edb980b034ba86205ceeae65d6b460c2b825e24b467`. CI rejects changed eligibility, hidden omitted channels or partial passes; five altered report variants were refused locally. The projection retains its limited scope. M5 now separately qualifies full match/result envelopes, fallback policies/handlers, retained identity and bidi in the main audit, with native successful-fallback observation evidence. See [expressions](EXPRESSIONS.md) and [fragments](FRAGMENTS.md).

[Materialized fixture provenance](MATERIALIZED-FIXTURES.md) explains why canonical corpus objects alone cannot recreate the oracle's input member order or bytes. The pinned sidecar contains only inputs and source/recipe evidence; it never supplies expected observations. Missing/tampered sidecars are refused before execution.

The development corpus envelope reaches nesting depth 132 because it embeds intentionally invalid catalogs; its reader allows depth 256. Public catalog JSON depth is 64 by default / 128 maximum. Numeric observation decoding preserves explicit carrier widths and exact decimal text; malformed/unknown fields fail rather than turning into a passing refusal.

## Current compatibility and remaining release gates

The 1.0.0 preparation sets public build metadata to `1.0.0`, changes consumer
examples to a SwiftPM version requirement starting at `1.0.0`, and adds the
[changelog](../CHANGELOG.md) to the source distribution. The release remains
unpublished until the maintainer commits the final sources and pushes its
semantic-version tag. Tagged API documentation requires that clean release
checkout; development documentation remains labelled as development.


Each direct parse/define/merge call owns its session. Local stream/file/directory/
Bundle/resource-map loads share aggregate counters and retain per-file JSON depth,
warnings and origins. Discovery uses bounded UTF-8 ordering; supplied streams stay
open, and owned descriptors close on every exit. [Local loading](LOCAL-LOADING.md)
records validation order, collisions, ownership and budgets.

The original raw corpus retains 2,197 passing and 184 pending IDs. The shared
[core native contract](NATIVE-CONTRACTS.md) separately accounts for all 2,155
required portable obligations: 2,135 exact runtime matches and twenty qualified
nonoptional source boundaries. Informational coverage records 62 exact matches,
five complete filename adaptations and 159 JVM-only carriers. Those five sets
are disjoint and exhaust all 2,381 cases. They qualify declared adaptations;
they do not rewrite raw expectations, create runtime passes for impossible
inputs or certify universal parity. [Native type evidence](NATIVE-REPRESENTATIONS.md)
and [loader dispositions](LOADER-DISPOSITIONS.md) preserve unreplayed channels
and complete native/reference filename observations.

The manifest archive retains 499 cases. Under the separate versioned normalization
amendment, 468 native observations pass: 162 strict native-equal and 306 explicitly
projected observations, including four documented corrections to historical
expectations. The [manifest native contract](MANIFEST-NATIVE-CONTRACTS.md) accounts
for the other 31 dynamic-carrier inputs through compiler/runtime boundaries.
[Manifest normalization](MANIFEST-NORMALIZATION.md) and [diagnostic text](DIAGNOSTIC-TEXT.md)
close the coordinated shared corrections. Archived counts in the milestone
history below describe their original runs.

The [October 5 hosted run](https://github.com/lokalized/lokalized-swift/actions/runs/37251334464)
at `7f2485544f99e6d1053c5863ba9f6742b59fdc13` completed successfully on all
three jobs: minimum Swift 6.2 arm64, minimum Swift 6.2 Intel and current arm64.
Public job metadata confirms the qualification steps passed; authenticated logs
and artifact contents were not read. This supersedes the October 4 Intel checker
failure. The uncommitted 1.0.0 metadata, API documentation and newest shared-profile
tests require a fresh hosted run after commit and push.
The [deployment probe](DEPLOYMENT.md) separates native execution, four-target
compilation and emitted OS floors. iOS 15/macOS 12 runtime and physical-device
execution remain unverified. The current iOS 26.5 simulator evidence is scoped
separately and never substitutes for a minimum-version/device run. Both optional
iOS execution steps were skipped in the October 5 push run. Separate shared
fallback-observer and exact-identifier profiles now qualify those behaviors
without changing the original corpus.

[Performance](PERFORMANCE.md) records optimized consumer measurements on the
current Swift 6.4 arm64 host, with source caps and measured-profile binary caps.
Swift 6.2 performance remains unmeasured locally; CI retains its actual profile
rather than applying another compiler's cap. [Compiled data](DATA-ENCODING.md),
[identifiers](IDENTIFIER-DATA.md), [plurals](PLURAL-DATA.md), [locales](LOCALE-DATA.md)
and [language ranges](LANGUAGE-RANGES.md) have pinned schemas and qualified kernels.

`--runtime-adapter` independently selects and compares all 1,432 eligible runtime cases from fixture/input shapes and actual callback consultations. It records guards for all twenty pending cases; expectations never configure execution. Its eligible-ID SHA-256 is `364e6f0954c2adc1c825a86aee4ea9b423fb850e741b13a01cb2973b6a1a6b60`. The main 2,197-ID digest is `2c4848b0b481d01523e11813efbf5dd874cc5c75ca8b15aaa41e5ff5f25ee76f`. The 145-ID loader digest is `6c6043d0326a9a524690c485292cc2cd748161504fbaa5c0c7fcb97d91e16991`; pending main IDs hash to `618df840c1a5bb7808f0e747ad8c18f5f90532d2676ea05454d9efe0f41b7d76`. All ID digests hash sorted exact IDs with LF after every ID. CI refuses changed eligibility, missing fields, missing guards, partial passes and unexpected mappings.

The archived `perCallOverrideOrder` records a Java builder setter sequence. The adapter checks that exact input recipe and passes its final single locale source to Swift's immutable options; constructing simultaneous Swift locale sources is refused independently. This is an input construction adaptation, never an expected-result choice.

## Milestone history

**M7A: manifest foundation** implements the pinned format version 1 wire shape, explicit decoded/typed claim carriers, strict bounded Data/text parsing, full-manifest schema/tiebreaker/fallback validation, all seven runtime data checks, exact narrow JCS bytes and system SHA-256. Every public planning door revalidates before producing configuration, absent candidate chains or declared first-use fetch entries. These operations perform no catalog I/O and produce no verified loaded records. The original 2,381-case audit and its 2,197/184 sets remain unchanged.

The separate frozen JS manifest archive contains 499 cases. Its native report qualifies 468 input-selected observations: 165 strict native-equal observations and 303 explicitly projected error representations, retaining complete native/reference/comparison observations. Thirty-one dynamic JS/native carrier cases remain pending; no mapping is ratified. The eligible-ID SHA-256 is `f8062a5ef05939d4100f68b1a1c64ab351632992a56719154831e5c1babb69c1`. [Contract evidence](MANIFEST-CONTRACT.md) records exact sets, pins, migration evidence and the projection rules. [Identity](MANIFEST-IDENTITY.md), [validation](MANIFEST-VALIDATION.md) and [planning](MANIFEST-PLANNING.md) describe the implemented boundaries.

**M7B1: Unicode domain processing** completes the resolver's former Unicode/punycode capability gap. Unicode 17 mapping and a fully qualified canonical NFC utility are separate from the pinned Node 26.5.0/Ada 4.0.0 URL normalization/validity profile; its older/incomplete tables and observed normalization/joiner/bidi shortcuts preserve actual oracle behavior. The library consults no device URL/Unicode properties and adds no external runtime package. [URL evidence](MANIFEST-URLS.md) distinguishes compatibility from strict UTS #46 validation and records the shared policy decisions still needed.

M7B1 qualification passes all **59,992 frozen URL observations**: the unchanged 3,479-row archive and a separate 56,513-row Node archive, with zero pending capabilities or failures. The new archive contains 6,389 official scalar-compatible inputs, 32,203 property discriminators, 17,062 normalization discriminators and 859 authored boundaries. An independent 50,030-input review also matches. Canonical Unicode 17 NFC passes 1,195,148 checks; the separate compatibility normalization table decoder passes 4,483,039 lookups and 13 corrupted-report controls. Unicode and auxiliary-property decoders cover every codepoint independently. All fifteen URL report controls and the existing fifteen manifest controls reject altered receipts. The original 2,381-case 2,197/184 ratchet, 499-case 468/31 manifest inventory, native observation ledger and seven runtime data identities remain unchanged. Final evidence is `.build/reports/m7b1-qualification-summary.json`. Four Apple build targets inspect 16 binaries from 124 stable source files, and fresh/package resource consumers pass with zero external dependencies. The deployment and packaging receipts are `/private/tmp/lokalized-swift-deployment-m7b1-report.json` and `/private/tmp/lokalized-swift-local-delivery-m7b1.json`; their runtime/toolchain limits remain explicit in [DEPLOYMENT.md](DEPLOYMENT.md).

The frozen JS locale normalizer's non-idempotent `UND-x-foo` behavior is preserved and covered by paired vectors; the maintainer approved a coordinated shared-version correction on October 2, with implementation pending. A separately measured truncated diagnostic-path output can contain a lone surrogate in JS but U+FFFD in Swift; this native error-message representation remains an explicit release qualification gap outside the frozen 499-case inventory.

**October 2 scope decision:** Swift follows Java's synchronous local-loading model. HTTP fetching exists in JS for browser delivery and is not a Swift requirement. Applications own downloads and supply catalog bytes, text, streams or local resources to the implemented loaders. The proposed M7B2 HTTP transport, partial-network-load policies, cancellation machinery, `LoadedStrings`/verified-network records and publishing workflow are removed from the Swift release scope. The unfinished draft was never integrated and has been discarded; no HTTP implementation ships. Existing M7A/M7B1 pure manifest helpers and frozen evidence remain, and URL metadata never triggers catalog I/O.

**M8A: native type representation evidence** adds the missing catalog/tiebreaker/key compiler boundaries, executes 23 named adjacent runtime controls, and produces a checked per-case dossier for all twenty pending native runtime configurations. All seventeen invalid consumers are refused for their intended type reason, the valid consumer compiles, all 23 runtime controls pass and all 23 report-corruption controls are rejected. Current library sources and consumer inputs are frozen and revalidated. CI runs both generation and strict report checks. The main 2,197/184 audit and independent 1,432/20 adapter inventories remain unchanged; no mapping or additional runtime pass is fabricated. This slice adds no production API or dependencies.

**M8B: public API coverage** accounts for all 747 reference records: 53 Java types, 443 Java members and 251 JS declaration occurrences (including 127 runtime export occurrences). An isolated compiler/symbol-graph check requires every native target to be public and checks the mapped member family/conformance. All eighteen ledger/report-corruption controls are refused. The audit exposed and closed small public omissions: standalone strict `LanguageRange.parse`, immediate negotiated-range/header `TranslationOptions` factories, and `BuildMetadata`'s existing `pinned`/`exact` modes. Thirty-seven new standalone checks cover diagnostics, expansion/count caps, custom result/error identity and actual runtime consumption. A fresh reference-free SwiftPM consumer executes the additions. CI retains the ledger and fresh compiler evidence. See [public API coverage](API-COVERAGE.md) for the precise limits: member-family presence is not full overload or behavioral equivalence. The main corpus and native mapping counts remain unchanged. Fresh four-target SDK inspection and packaged consumers pass with zero external dependencies; actual minimum-compiler/old-OS/iOS/Intel runtime gates remain open. Scoped evidence is `.build/reports/m8b-qualification-summary.json`.

**M8C: local loader dispositions** accounts individually for all 164 pending loader IDs: ninety JVM discovery inputs, sixty-nine JVM resource-map inputs and five native filename-attribution cases. All are informational in the unchanged corpus. An isolated current library/support/executable passes twenty named native Bundle/resource-map/ordering controls, and all twenty-five corrupted-receipt controls are refused. For the five real directory loads, the checker derives the attributed filename from authored unsigned UTF-8 order and the file cap, requires the exact reason/limit/message and preserves both whole observations. The 159 classloader inputs remain unreplayed platform-specific carriers; the five shared mappings remain unratified. Production library sources, external dependency count, main corpus pass/pending sets and native mapping counts are unchanged. See [loader dispositions](LOADER-DISPOSITIONS.md). Scoped local evidence is `.build/reports/m8c-qualification-summary.json`.

**M8D: package size and performance** adds a public-API benchmark consumer, three fresh optimized source-only builds and twelve workloads per build, covering cold initialization, 1,000/10,000-entry catalogs, plain/fallback/plural lookups, larger generated output and pure Unicode-domain planning. All 36 executions and nine corrupted-report controls pass. The measured Swift 6.4/SDK 27.0/arm64 consumer is 2,267,480 bytes stripped, including its driver; warm plain lookup averages 105.54 µs and cold initialization plus first lookup takes 8.22 ms. Generated Swift data is 810,025 bytes. Source byte caps apply everywhere; a compiler/SDK/architecture-specific binary cap applies only to the measured profile, with other profiles explicitly unbudgeted until reviewed. CI measures both configured tracks and retains observations without timing/memory thresholds. No production sources, dependencies or corpus dispositions change. See [methodology, results and limits](PERFORMANCE.md); scoped local evidence is `.build/reports/m8d-qualification-summary.json`.

**M8E: immutable locale fact reuse** profiles optimized unmodified public consumers before/after a focused production optimization. Loaded tags reuse their pinned parent sequences and already computed likely-script/undetermined facts through an immutable index; unknown requests retain the existing calculation. There is no growing request cache, lock, new public API or dependency. A repeated exact M8D source baseline and current source each pass three optimized builds, 36 workload runs and nine report-corruption controls. Current-host warm plain lookup falls from 116.08 to 57.07 µs (51%); fallback falls from 125.82 to 63.57 µs (49%). Cold total is effectively unchanged at about 5.9 ms. The cold live malloc delta grows by 18,496 bytes, and the stripped consumer grows by 496 bytes to 2,267,976; existing caps pass unchanged. All 265 native test methods pass with one existing skip, 1,030 standalone checks pass, and the main corpus keeps the exact 2,197/184 sets with no failures or ratified mappings. Fresh public API coverage still accounts for all 747 reference records and rejects eighteen corrupted reports. All sixteen binaries across four Apple target triples compile/link and meet their declared SDK floors; only arm64 macOS executes locally. The floating converter and its selection semantics are unchanged. See [comparison and limitations](PERFORMANCE.md); scoped evidence is `.build/reports/m8e-qualification-summary.json`.

**M8F: exact floating trial reuse** keeps a bounded three-entry exponent window within each conversion, reusing the two overlapping exact trials at the next digit count. Digit checks, candidate order, IEEE boundaries, closest/tie selection and Java spelling are unchanged. The pinned Corretto oracle again matches 103,310 Float/Double inputs with zero differences and the same input/output digests; all 1,592 archived goldens and 110 selected native numeric/translation methods pass. Three optimized builds per version retain all 36 checked workloads and nine corrupted-receipt refusals. Against a repeated exact M8E source baseline, Double π lookups fall from 225.74 to 125.04 µs (45%) and largest-finite Double lookups from 309.22 to 164.60 µs (47%). Plain/integer/decimal controls stay close to baseline. The stripped consumer grows by 16 bytes to 2,267,992, and existing caps pass unchanged. The standalone 1,030 checks and exact main 2,197/184 sets remain unchanged, with no mappings, dependencies or new public APIs. See [numeric proof/oracle](FLOATING-POINT.md) and [measurement limits](PERFORMANCE.md); scoped evidence is `.build/reports/m8f-qualification-summary.json`.

M8F also refreshes the unchanged 1,155-symbol public graph, all 747 reference dispositions, eighteen report-corruption refusals, and sixteen compiled/linked/inspected binaries across the four Apple target triples. Host arm64 qualification executes; other architectures/platforms have compilation evidence only. The previous full M8E native suite remains historical evidence alongside the targeted M8F suite.

M8J/M8K below close the coordinated diagnostic and manifest normalization amendments. Remaining M8 work includes actual minimum-compiler/old-OS/iOS/Intel/hosted-CI execution gates and shared release-evidence cleanup. M8I below qualifies the archived manifest carriers. The core-corpus native decisions are specified and qualified by M8H below. Minimum-track performance and application-specific sizing remain unmeasured locally. Existing pending corpus cases remain explicit; the HTTP scope decision does not turn them into passes.

The implementation plan remains outside source control at the parent workspace's `SWIFT_IMPLEMENTATION_PLAN.md`.


**October 2: shared IDNA fixture ownership and compression** moves the canonical 56,513-case oracle archive, language-neutral input recipe, required Unicode/Ada data/licenses and engine provenance to `lokalized-spec`. Swift consumes a verified twenty-artifact offline snapshot and retains its native emitter/probe adapters. The 731,845-byte gzip reproduces the original 19,308,094 JSON bytes exactly, preserving every expectation, case ID and decoded digest. Both readers enforce separate stored/decoded byte limits and complete single-member/CRC/trailing-data checks. Production library sources and external dependency counts are unchanged. All 59,992 original/new URL observations and fifteen report-corruption controls pass; fourteen selected XCTest methods, six Swift-development Python tests and nine shared tests pass. A standalone snapshot passes without siblings or a port compiler, and corrupted canonical/local data is refused, including refusal before sync writes. Four Apple SDK targets compile/link/inspect sixteen binaries with the current unchanged Swift source hashes; actual minimum-compiler/other-platform/old-OS runtime limits remain as previously documented. See [shared snapshot ownership](../Reference/URL-ORACLE.md) and [URL evidence](MANIFEST-URLS.md). Scoped local evidence is `.build/reports/idna-shared-qualification-summary.json`.


**M8G: single exact preference** skips language-range member preparation and election when one finite, positive preference exactly matches a configured locale. Undetermined non-private preferences, NaN/zero, nonexact/wildcard and multiple-range inputs retain the full election. Results retain actual requested ranges/configured typed identity and use the normal validated initializer; suppliers, callbacks and fresh result identity are preserved. No request cache, stored member metadata, public API or dependency is added. Three optimized builds and 36 checked workload executions per version, with nine corrupted-report refusals each, compare an exact pre-change source/tool snapshot against current source. On this host, warm plain lookup falls from 53.04 to 7.50 µs (86% less time) and fallback from 58.14 to 12.50 µs (78%). The stripped consumer remains 2,267,992 bytes and existing size caps pass. All 273 native methods pass with one existing filesystem skip; all 1,057 standalone checks and exact 2,197/184 shared sets pass unchanged, with no ratified mappings. Fresh API qualification retains 1,155 public symbols and all 747 dispositions with eighteen corrupted reports refused. Four Apple SDK targets compile/link/inspect sixteen binaries and current arm64 qualification passes all data/component/filesystem/manifest/URL/NFC checks. Actual minimum compiler and other-platform/minimum-OS/hosted-CI execution remain open. See [matcher semantics](LOCALE-MATCHING.md) and [measurements/limits](PERFORMANCE.md); scoped evidence is `.build/reports/m8g-qualification-summary.json`. Next available release work is the shared native-representation/filename mapping decisions and remaining platform validation.


**M8H: shared native conformance contracts** adds `lokalized-spec`'s versioned `swift-native-local-v1` policy, schema, input-derived checker and seven offline shared tests. Swift consumes four byte-pinned artifacts and qualifies them only after current compiler/runtime/native evidence and a source-bound SDK/host audit pass. All 2,155 required portable obligations are accounted for as 2,135 exact runtime matches and twenty qualified nonoptional source boundaries. Informational accounting is 62 exact matches, five complete filename adaptations and 159 platform-specific JVM carriers. All five exact ID sets are disjoint and exhaustive over 2,381 cases; strict runtime agreement remains 2,197. Original observations, partitions and raw 2,197/184 audit remain unchanged. The new receipt is `covered-under-native-contracts-not-certified` with release parity false; it preserves every unreplayed channel. Seventeen negative compiler consumers, the positive consumer, 23 adjacent runtime controls and twenty Bundle/loader controls pass; all 23/25 existing native/loader and 27 new contract corruptions are refused. Five Swift-development Python tests, seven shared tests, schema/partition checks and a standalone saved-evidence check without siblings or a compiler pass. Fresh four-target SDK qualification inspects sixteen binaries from unchanged production sources and passes current arm64 host/data/component/filesystem/manifest/URL/NFC qualification with 1,057 standalone checks. The deployment tool now executes the macOS target matching its host architecture; actual Intel execution remains unverified here. CI checks native coverage after deployment qualification under both configured compiler tracks. No production API, dependency or HTTP loading changes. See [contract evidence and limits](NATIVE-CONTRACTS.md); scoped summary is `.build/reports/m8h-qualification-summary.json`. The separate 31 JS manifest carriers/surrogate diagnostic and actual minimum compiler/other-platform/minimum-OS/hosted-CI gates remain open.


**M8I: shared manifest native contracts** promotes the original 499-case archive, lock, schema, input recipe, JS oracle, declaration/notice provenance and raw comparison checker to `lokalized-spec`; Swift consumes fourteen pinned offline artifacts. The archive, lock, complete native observation ledger and raw report bytes stay unchanged. A versioned input-derived profile accounts for 468 runtime comparisons (165 exact observations, 303 narrow native error projections) and 31 native adaptations. Thirty external consumers fail for their intended type/argument/Unicode reason; one compiles because Swift defaults omitted identity formatVersion to 1. Sixteen adjacent runtime controls qualify this default, explicit null/limit/digest/lookup refusals, Unicode repair/raw escape rejection and successful planning. All 23 new native-coverage and fifteen existing raw-report corruptions are refused; seven shared tests, five Swift-development Python tests and 33 selected manifest/identity XCTest methods pass. A standalone saved-evidence check works without siblings or compiler execution. Fresh SDK qualification inspects sixteen binaries across four targets from the unchanged 127 Swift sources and executes current arm64 host/data/component/filesystem/manifest/URL/NFC qualification with 1,057 standalone checks. Core native coverage also revalidates against the new source-bound audit with its exact original sets. CI runs the manifest profile under both tracks. No production API, source, HTTP loading or external dependency changes. See [manifest native contracts](MANIFEST-NATIVE-CONTRACTS.md); scoped evidence is `.build/reports/m8i-qualification-summary.json`. The maintainer approved the current wire naming and coordinated versioned corrections; actual migration/normalization/diagnostic amendments and minimum compiler/other-platform/minimum-OS/hosted-CI evidence remain separate work.


**M8J: coordinated diagnostic text correction** defines shared `diagnostic-text-v1.1` version 1.1.0, its scalar-based independent recipe/schema and 36 raw catalog/manifest cases. Java and JS repair pairs split by UTF-16 diagnostic truncation to match Swift’s existing replacement behavior. JS/Swift nested manifest member displays now share the catalog’s 256-unit cap; paths retain their 4,096-unit cap and terminal behavior. Swift consumes five byte-pinned artifacts, executes all 36 cases through actual public parsers, compares exact UTF-16 text and rejects altered input bytes. Fifteen saved-report corruptions are refused; six shared checker tests and 26 selected Swift XCTest methods pass. A fresh four-target SDK qualification inspects sixteen binaries from 128 current Swift sources, passes the diagnostic command and replays the unchanged core, manifest, data, filesystem and URL/NFC ledgers with 1,057 standalone checks. Java passes 110 loader/profile test methods (18 shared vectors); JS passes all 2,332 regression tests, including the 36 shared vectors, and its type check. JS source-size records are remeasured with recorded reasons and frozen history checkpoints, and its CI mirrors the new dependency-free shared gates. See [diagnostic profile](DIAGNOSTIC-TEXT.md); scoped summary: `.build/reports/m8j-qualification-summary.json`. No public API, wire-format, locale normalization, HTTP loading or external dependency changes. Remaining work is the coordinated manifest normalization amendment and actual minimum compiler/OS, iOS/Intel and hosted-CI execution.


**M8K: coordinated manifest normalization correction** defines shared
`manifest-normalization-v1.1` version 1.1.0, its independent recipe/schema, 35 new
cases and exactly four explicit historical amendments. JS and Swift manifest
helpers now stabilize private-use-only JDK projections as `x-…`; core locale
behavior, arbitrary raw identity keys, wire format 1 and the current tiebreaker
name retain their contracts. Affected manifest fingerprints must be regenerated.
JS loaded-core and SSR coverage use the same stable manifest spelling while
retaining the actual core context. The original 499-case archive and lock stay
unchanged. Current reports retain all historical references, four separately
amended references, 464 unchanged historical agreements and four amended
comparisons, partitioned as 162 exact / 306 projected observations. Thirty-one
native adaptations compose with the existing carrier profile and never become
runtime passes. All 278 native test methods pass plus one existing filesystem
skip; all 2,372 JS tests, its type check and declaration probes pass. Six shared
and five Swift-development Python tests, 18 active-archive/13 profile corruption
refusals, 23 native receipt refusals and four isolated offline checks pass.
Fresh four-target SDK qualification inspects sixteen binaries from 129 current
Swift sources and executes the new profile alongside all existing core/data/
filesystem/diagnostic/URL/NFC checks and 1,057 standalone checks. A fresh offline
package and external consumer build/execute with zero external dependencies.
Current core native coverage is also requalified against the fresh source-bound
SDK and compiler/loader controls. See [normalization and migration](MANIFEST-NORMALIZATION.md);
scoped summary is `.build/reports/m8k-qualification-summary.json`.

The umbrella `lokalized-spec` check currently stops at its unchanged Java-surface
inventory gate: `TranslationFallbackEvent`, `TranslationFallbackObserver` and
`TranslationFallbackEvent.PrecedingFailure` lack shared surface dispositions.
All manifest normalization, historical/native manifest, schema and partition gates
pass individually. This pre-existing documentation drift remains a separate
release-evidence cleanup task. Minimum Swift 6.2, minimum OS, iOS/Intel runtime
and hosted CI execution remain open. No HTTP loader or external runtime dependency
is added, and the native coverage receipts retain `releaseParity: false`.


**M8L: observer inventory and packaged iOS execution** records A35's three
existing Java 3.1.1 observer types with explicit JS/Swift counterparts, including
the standalone native `PrecedingFailure` representation. The current surface
audit now has no drift; 47 JS observer/divergence/CI tests and 23 selected Swift
runtime/contract methods pass. No observer case is inserted into the frozen
corpus. A new stdlib-only qualifier executes the fresh packaged SwiftUI app on
arm64 iOS 26.5 (23F77), checking actual Bundle catalogs, English/French rendering,
exact NFC/NFD keys and French plural lookup. The app's MainActor/concurrency
settings, iOS 15 floor and resource/privacy bytes are verified during fresh
packaging. Both SwiftPM caller modes and the macOS app also execute; all three
Apple app products build. The owned simulator is shut down and deleted. Nine
offline tests and ten corrupted-receipt controls pass. CI includes the tests and
an explicitly requested installed-runtime execution step; hosted execution has
not occurred locally. See [iOS scope and reproduction](IOS-RUNTIME.md).

The spec's default umbrella check now passes the observer surface but correctly
refuses historical IANA source provenance against today's Java checkout. A
separate source-only archive of the exact Java 3.1.0 commit is freshly compiled
on Corretto 21.0.11; its 62-file source aggregate matches the frozen receipts.
IANA replay passes 116,658 probes and behavioral replay reproduces all 2,381
cases/five seeds without writing any artifacts. All 21 shared gates pass in the
explicit matrix, using current sources for API inventory and that historical
build only for oracle replay. See [oracle input selection](../../lokalized-spec/ORACLE-REPLAY.md).
Scoped summary: `.build/reports/m8l-qualification-summary.json`.

The iOS result is packaged-consumer evidence, not full iOS corpus or device parity.
Minimum Swift 6.2, iOS 15/macOS 12, full iOS runtime, physical device, Intel and
hosted CI remain separate execution gates. Observer vectors remain deferred by
the shared naming policy. Production Swift sources/APIs, original corpus bytes,
external dependency count and no-HTTP scope stay unchanged. Work remains
uncommitted and unstaged.

**M8M: standalone conformance on iOS** runs all fourteen development qualification
commands inside a real arm64 iOS 26.5 simulator app. Full observations match the
fresh macOS build: 1,057 self-tests, exact 2,197 passing / 184 pending corpus IDs,
runtime/component/filesystem/Bundle controls, CLDR plural/locale data, manifest
profiles, URL/56,513 IDNA observations and all 1,195,148 Unicode 17 NFC checks.
The corpus remains incomplete, and native carriers/representation dispositions
retain their existing scope. A development-only SwiftUI shell packages frozen
reference bytes and current local source modules; its three Mach-O files retain
iOS 15 floors and Apple/system/local dependencies. Large reports use bounded
base64 frames over the simulator console. The owned simulator is deleted.

Four development-support files now share the POSIX-canonical application
temporary-directory helper; production sources/APIs are unchanged. Fresh
four-target SDK qualification inspects sixteen binaries from all 129 current
sources. Native coverage and packaged resource consumers are refreshed against
those bytes. All 278 macOS XCTest methods pass with the existing skip; fifteen
offline iOS receipt tests and twenty corruption controls pass. CI adds offline
tests and explicitly requested full simulator qualification. See
[iOS scope and reproduction](IOS-CONFORMANCE.md); summary:
`.build/reports/m8m-qualification-summary.json`.

The current standalone iOS execution gap is closed. Remaining execution gates
are minimum Swift 6.2, iOS 15/macOS 12, physical device, Intel and hosted CI;
shared observer vectors remain deferred. No dependency, HTTP loading, commit
or staging changes.

**M8N: native Intel CI and compiler/host guards** adds the minimum Swift 6.2
`macos-15-intel` track beside minimum/current arm64. Each job compiles and runs
a native kernel probe, requires its declared architecture, rejects Rosetta or
contradictory CPU observations, and repeats that requirement during four-target
SDK qualification. Distinct compiler/architecture artifact names prevent the
two minimum jobs from colliding. Intel runs the same workflow, including tests,
complete audits, native contracts, packaged consumers and measurements; existing
unmeasured-profile binary-budget reporting is retained. Official runner labels
and both minimum Xcode inventories were checked. See [deployment and CI scope](DEPLOYMENT.md).

Eleven offline host-probe tests pass, and actual local requests for Intel or
Swift 6.2 both exit 1 with failed receipts on this Swift 6.4 arm64 Mac. Fresh SDK
qualification inspects sixteen target binaries plus the host probe and executes
the unchanged macOS audits. The refreshed iOS 26.5 app executes all fourteen
commands with full observation equality and deletes its owned simulator.
Native coverage checks and all 27 core / 23 manifest / 25 loader / 20 iOS
corruptions pass; all 24 existing iOS checker tests also pass. Current packaged
catalog evidence remains valid and its ten controls are rechecked.

All 129 Swift source hashes match M8M; public APIs, corpus/profile bytes, runtime
dependencies and HTTP scope are unchanged. The previous full XCTest and
packaged-build runs remain evidence for those unchanged sources; they are not
rerun here. Earlier SDK/native/iOS receipts whose tooling pins changed are
historical. Fresh scoped summary: `.build/reports/m8n-qualification-summary.json`.
Minimum Swift 6.2, native Intel, hosted CI, iOS 15/macOS 12 and physical-device
execution still require actual environments. This slice prepares the hosted
gates and does not claim their completion. Work remains uncommitted and unstaged.

**M8O: concurrency stress and Thread Sanitizer** adds four public-API tests with
992 parallel worker iterations covering a shared four-locale runtime, exact
Unicode keys, bidi/number/plural results, independent resolver caches, callback
reentry/error identity and concurrent local loading budgets/warnings/streams.
All four pass normally. A separate sanitized build executes all 37 selected
runtime/preference/loading methods: 36 pass, one existing filesystem fixture
skips, and no races are reported on this Swift 6.4 arm64 macOS host.

The intentionally racy development control is detected with source attribution
and exit 66. Actual runtime-object instrumentation and the test binary's
sanitizer link are inspected; normal uninstrumented artifacts are refused.
Eleven detector/log/instrumentation refusal controls pass. The checker requires
complete declared test IDs and records pre-build source pins, exact observations
and artifact/log identities. CI adds this recipe on all three configured tracks;
no hosted execution is claimed. See [concurrency scope and reproduction](CONCURRENCY.md);
summary: `.build/reports/m8o-qualification-summary.json`.

All 129 runtime/development Swift source hashes and existing M8N SDK/native/iOS
input identities remain current. No production source/API, corpus/profile,
dependency or HTTP-loading change is made. The full XCTest and packaged-build
runs remain earlier unchanged-source evidence; this slice runs the new tests
and selected sanitized suites. Actual minimum compiler, minimum OS, Intel,
physical-device and hosted-CI execution remain open. Finite sanitizer coverage
does not certify race freedom or release parity. Work is uncommitted and unstaged.

**M8P: source distribution and notices** adds root Apache attribution, a complete
third-party inventory and separately pinned CLDR, Unicode 15/17 and Ada MIT
license documents. A standard-library Python tool creates a deterministic
archive of the current source tree, including the original manifest, examples
and development snapshots. Git/build/cache/user files are excluded, symlinks
are refused and the IDNA goldens remain compressed. Nineteen offline controls
qualify preserved bytes/modes, notices, exclusions and corrupted/unsafe archives.

The fresh-package check now consumes that archive, inspects the extracted
manifest and verifies the notices, then deletes Reference/Tools before building
the package and running a separate public-API consumer. It checks the consumer's
actual macOS deployment floor/system links, exact packaged privacy bytes and
absence of resolver files, and revalidates the source inventory after execution.
CI applies the same source-distribution gate on all three configured tracks and
retains the archive plus complete source/build receipt. See
[source distribution](SOURCE-DISTRIBUTION.md); scoped local receipt:
`.build/reports/m8p-source-distribution.json`.

All 129 Swift source files, the production API, shared corpus/profiles, external
dependency count and no-HTTP scope are unchanged. Existing SDK, packaged Apple
consumer and sanitizer source evidence remains valid. The earlier iOS conformance
receipt is historical for its complete Tools-directory pin because packaging
tools changed; the actual iOS source/reference bytes are unchanged. No iOS run
is added by this packaging slice. Minimum compiler/OS, native Intel, physical
device, hosted CI and deferred observer-vector gates still require their own
environments or shared release decisions. Work remains uncommitted and unstaged.

**M8Q: minimum-compiler CI repair** addresses the actual Swift 6.2 failure in
the [October 3 hosted run](https://github.com/lokalized/lokalized-swift/actions/runs/37132141541).
Both native minimum tracks passed compiler/kernel and package checks, then
failed inferring nonoptional URL-trimming indices. Explicit `Int` indices in
the scalar-array helper and `String.Index` indices in the two locale/header
helpers remove the ambiguity without changing the trimming policy. The CI
checkout/upload actions use the sibling libraries' verified v7.0.1 commit pins
and Node 24. Runner architecture requirements remain unchanged.

Current-host Swift 6.4 passes all 283 XCTest methods (282 passed, one existing
filesystem skip), the separately compiled 3,479 URL and 56,513 IDNA observations,
and source-size budgets. Fresh four-target SDK and extracted-source consumer
receipts are recorded separately for the changed sources. Earlier source-bound
SDK, iOS, packaged-app and sanitizer receipts remain historical; this repair
does not count them as current execution. The fixed sources still need hosted
Swift 6.2/Intel verification after the maintainer commits and pushes. Minimum-OS,
physical-device and deferred observer-vector gates remain open. See
[deployment evidence](DEPLOYMENT.md); local summary:
`.build/reports/m8q-qualification-summary.json`. Changes remain uncommitted
and unstaged.


**M8R: executable consumer documentation** reorganizes the README around package
installation and a complete translation example. The new [usage guide](USAGE.md)
contains real English/French resources and a runnable MainActor-default consumer
covering plural fragments, per-call language choices, ordered preferences,
written decimals, fallback diagnostics, default/throwing failure responses and
exact Unicode keys. The [development guide](DEVELOPMENT.md) holds maintainer
commands and distinguishes raw corpus observations from qualified native contracts.

The documentation checker reads the actual Markdown manifests, six Swift blocks,
two JSON resources and expected output. It substitutes only the remote package
reference with a fresh local source snapshot, validates dependency shapes and
builds/runs both complete programs without Reference/Tools. Both programs pass
on Swift 6.4, matching all twelve documented output lines; seven offline admission
controls pass. CI runs this recipe on all three tracks. A fresh source archive
includes the new guides/tools and its extracted reference-free public consumer
passes. All 129 Swift source hashes and all 66 M8Q SDK input hashes remain current;
production code, dependencies, catalog syntax and frozen corpora are unchanged.
The full runtime suite is not repeated for this documentation slice. Scoped
receipts: `.build/reports/m8r-documentation.json` and
`.build/reports/m8r-qualification-summary.json`. Work remains uncommitted and unstaged.

**M8S: adversarial catalog parsing** adds development-only deterministic generation
and differential execution against fresh, byte-pinned Java 3.1.0 sources and the
pinned Corretto JDK. Two seeds pass 13,210 case executions, comparing complete
decoded models, actual refusal class/main message and ordered warning messages.
Finite JSON/schema/budget/Unicode mutation families and eleven offline admission
controls supplement the frozen corpus; generated cases are not checked-in runtime
resources. [Parser stress](PARSER-STRESS.md) records scope, commands and minimized
regressions. Locale ingress and expression-evaluation fuzzing remain separate
at this milestone.

The probe found and fixed two shared-reader defects: unsupported escapes advanced
the error cursor, and premature high-surrogate validation displaced competing
syntax failures. Catalog and manifest text/byte regressions preserve Java's error
positions; valid pairs remain exact and unpaired surrogates remain refused.
Manifest parsing no longer needs its separate one-unit cursor compensation.

All 285 native test methods pass with one existing filesystem skip. Fresh
four-target SDK qualification inspects sixteen binaries and executes the native
arm64 consumer/data/runtime/filesystem/manifest/URL/NFC checks; original corpus
coverage remains 2,197 passing and 184 pending. Both documentation programs pass
against the changed source. Current source-bound receipts replace M8Q/M8R evidence
where parser/support hashes changed; minimum-OS, device, current-source simulator
and sanitizer execution remain separate scopes.

The hosted rerun completed successfully on current and minimum Swift 6.2 arm64.
Intel reached the manifest native-adaptation check after passing its preceding
qualification steps. M8S fixes an independently reproduced architecture-selection
bug in that check's negative control and tests both host shapes; six offline
manifest tests, 31 compiler consumers, sixteen adjacent runtime controls and all
23 manifest evidence corruptions pass locally. Hosted confirmation remains
necessary. No production API, external dependency, HTTP loading, shared archive
or conformance-policy changes occur. Evidence:
`.build/reports/m8s-qualification-summary.json`. Work remains uncommitted and unstaged.

**M8T: adversarial expression evaluation** adds a development-only differential
against the same fresh, byte-pinned Java 3.1.0 sources and Corretto JDK. Two seeds
pass 4,150 cases and 11,298 evaluations, comparing compiled/refused expressions,
typed Boolean outcomes, full diagnostic cause chains and ordered phonetic resolver
calls. All 61 language forms, numeric carriers, plural categories, Boolean
short-circuit paths, malformed grammar and configured/default limits are exercised.
Seven offline admission checks run in CI. [Expression stress](EXPRESSION-STRESS.md)
records the input recipe, scope and commands. The only detected mismatch was in
the probe: Foundation JSON dictionary decoding lost composed/decomposed key
identity; the corrected probe uses Lokalized's exact-key reader. Production Swift
sources, package dependencies, shared archives and conformance policy are unchanged.
Receipts: `.build/reports/expression-stress-default.json` and
`.build/reports/expression-stress-second-seed.json`. Hosted Swift 6.2/Intel and
minimum-OS evidence remain separate gates. Work remains uncommitted and unstaged.

**M8U: adversarial locale input** adds deterministic generated/mutated tags to
the existing complete CLDR table and fixed JDK projection checks. Two seeds
pass 5,676 Java/Swift comparisons across 21 exact UTF-16 output fields;
2,928 inputs are strictly accepted and 2,748 refused by Java. The first sample
found 59 differences: the lenient CLDR parser classified Unicode script/region
subtags with ASCII rules, and Swift grapheme splitting could hide a hyphen
before a combining mark. Byte-delimited subtags and a pinned-JDK uppercase/
decimal-digit table close both gaps. Eight offline recipe controls and the
generated-table digest check run in CI. Focused native locale tests and live
JDK table reproduction pass. [Locale stress](LOCALE-STRESS.md) records the
recipe, source pins, limited scope and regression examples.

The new compiled table adds 37,608 source bytes and no runtime resource or
external dependency. The runtime Swift source budget rises one 64 KiB step to
1,376,256 bytes, while its generated-source cap stays unchanged and passes.
The complete Swift suite passes 286 test methods with one existing filesystem
skip. One optimized source-only consumer build measures 2,301,576 stripped
bytes, under the existing 2,555,904-byte cap. Receipts:
`.build/reports/locale-stress-default.json`,
`.build/reports/locale-stress-second-seed.json` and
`.build/reports/locale-stress-package-size.json`. Work remains uncommitted and
unstaged.

**M8V: shared fallback-observer profile** introduces a seven-case versioned
supplement in `lokalized-spec` without changing the frozen Java 3.1.0 corpus.
Java 3.1.1, JavaScript and Swift replay byte-identical pinned test snapshots.
The common cases check first/later-candidate success, total exhaustion, policy
stopping, observer exception precedence, per-call replacement, exact candidate
and preceding-failure order, and retained result/match identity. The shared
profile checker has seven admission/negative-control tests. This profile does
not yet cover resolution-cause identity, negotiation-only fallback, nested or
concurrent observer calls, native constructor refusals or JS thenable returns;
port-local tests retain those obligations. See
[`lokalized-spec/FALLBACK-OBSERVER.md`](../../lokalized-spec/FALLBACK-OBSERVER.md).
All seven rows pass in each port. The full Java and JS suites pass, and Swift
passes 287 native methods with one existing filesystem skip. The spec profile
gate, seven negative controls and byte-for-byte snapshot comparison pass.
The broader spec umbrella still stops at its pre-existing historical IANA
source stamp because the current Java checkout is 3.1.1 while that oracle is
pinned to 3.1.0. The test-only snapshot adds no Swift runtime dependency or
HTTP loading; current Swift 6.4 package verification reports zero external
dependencies. Minimum compiler/OS, Intel and physical-device execution remain
separate gates. Work remains uncommitted and unstaged.

**M8W: expanded shared observer evidence** extends the still-uncommitted v1
profile from seven to ten cases, with three catalog/ingress variants now
replayed by Java, JS and Swift. `observer.negotiation-only` proves that
`isFallback` can be true while a first-candidate answer produces no event.
`observer.no-matching-alternative` keeps that reason distinct from a missing
key in the same ordered event. `observer.distinct-causes` passes two separate
throwing placeholder objects through policy callbacks and proves that the
observer retains each exact object, in order. The shared artifact and all
three test snapshots have the new SHA-256
`3dfda588e59cbf8f2b52ee0921dcd5d2d7fcfe2201e1f4853552ecbc3db45869`.
Ten shared admission/negative controls and the three focused port suites pass.
The full Java and JS suites pass; Swift again passes 287 test methods with one
existing filesystem skip. The source-package controls and current Swift 6.4
package verification pass, with zero external dependencies. Only
test/development material changes; no Swift runtime source, package
dependency or transport behavior changes. Port-local reentry, concurrency,
native construction and JS thenable checks remain outside this profile.

**M8X: inherited and reentrant observer parity** extends the still-uncommitted
shared v1 profile to twelve cases. An explicit per-call null observer inherits
the instance callback in all three ports. An instance observer also performs a
nested lookup synchronously; the profile pins the outer and nested results,
ordered policy calls, ordered events and each event's result/match-reference
identity. The shared artifact and three test snapshots have SHA-256
`4c844d73e8d333dde8432cb9e76fcdeb22b4937b50a632205fe74855b6e57d18`.
Concurrent lookups, native event construction and JS thenable checks remain
port-local. This slice changes test/development files only, preserving zero
Swift runtime dependencies and the no-HTTP loading policy. The shared checker
passes all twelve cases and fifteen admission/negative-control tests, including
byte-identical sibling snapshots. Focused and full Java/JS/Swift suites pass;
Swift executes 287 test methods with one existing filesystem skip. Swift source
package and current compiler checks pass, and package verification reports zero
external dependencies. Work remains uncommitted and unstaged.

**M8Y: shared exact Unicode identifier profile** adds six public-parser/runtime
cases to `lokalized-spec`, with byte-identical pinned snapshots in Java, JS and
Swift. The cases distinguish composed and decomposed catalog keys in one file,
prove that either spelling misses a catalog containing only the other spelling,
keep canonically equivalent placeholder names separate and refuse an escaped/
literal duplicate of the same decoded key. Source documents remain strings in
the profile so host dictionary decoding cannot erase the distinctions before
Lokalized parses them; Swift result comparisons use exact UTF-16 code units.
The artifact SHA-256 is
`1577a144581595526560a74cfa3dee0cc6e36d549cfe6dd37a78eab4221db638`.
See [`lokalized-spec/EXACT-IDENTIFIERS.md`](../../lokalized-spec/EXACT-IDENTIFIERS.md).
Eight shared admission/negative-control tests, all six rows in each port and
the byte-for-byte snapshot comparison pass. The shared gate joins the spec
umbrella and JS CI. This slice adds no runtime code, dependency or HTTP loader;
the original behavioral corpus and its coverage partitions remain unchanged.
Full Java and JS suites and JS declarations pass. Swift executes 288 test methods
with one existing filesystem skip and zero failures; the source-package check
and current Swift 6.4 package verification pass with zero external dependencies.
Minimum compiler/OS and physical-device evidence remain separate release gates.
Work remains uncommitted and unstaged.

**M8Z: shared identifier category/scalar boundaries** extends the still-uncommitted
exact-identifier v1 profile from six to fifteen cases. Three generated-fragment
lookups exercise Mn/Mc/Me and Nl/No/Nd continuations, a supplementary U+10400
initial letter and underscore/hyphen placement. Six parser refusals isolate
invalid mark/number/hyphen starters and emoji/format continuations. Every
refusal, including the prior exact duplicate, now compares the complete message
and exact offending spelling; Swift checks UTF-16 units. The artifact and all
three snapshots share SHA-256
`3b20ec306ec5da919909e28a6db04085ad4cf9133d76adb6cf87f3631ee72e6f`.
All fifteen cases pass through each port's public APIs, with twelve shared
admission/negative controls and byte-identical snapshots. The sampled category
boundaries preserve the existing grammar and Swift's Unicode 15.0 tables;
production sources, package dependencies and HTTP scope remain unchanged.
The source-package inventory check passes. Work remains uncommitted and unstaged.
