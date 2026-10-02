# Public API coverage

M8B accounts for every declaration in the frozen Java 3.1.1 and JS `617670da887b0c684e2589882447b6b93297f2f7` inventories. The supplementary [ledger](../Reference/swift-api-coverage.json) retains each original signature/declaration and gives it a native target or an explicit platform disposition. The [original census](../Reference/api-inventory.json) remains unchanged.

| Inventory | Occurrences |
|---|---:|
| Java public types | 53 |
| Java public members, including overloads/constants/builders | 443 |
| JS exported type/runtime declarations across nine entry points | 251 |
| Total ledger records | 747 |
| JS runtime exports (subset of the 251 declarations) | 127 |

Reexports are counted at each entry point. There are 93 `implemented`, 608 `native-adaptation` and 46 `platform-specific` records; these describe reference declarations, not percentages of features or behavioral parity. Native adaptations include initializers instead of builders, properties instead of getters, `CaseIterable`/`RawRepresentable` enums, Swift errors, typed closures, and Apple local resources. Java debug rendering is not a serialization format promised for every Swift model. Java classpath/JAR carriers and JS HTTP/SSR/verified-network/publishing APIs have explicit platform dispositions. Applications own remote acquisition. Pure manifest metadata utilities retain their documented scope.

## Executable evidence

```sh
python3 Tools/verify_api_coverage.py --check
python3 Tools/verify_api_coverage.py --qualify --report .build/reports/api-coverage.json
python3 Tools/verify_api_coverage.py --report-check .build/reports/api-coverage.json --negative-controls
```

Ordinary checks need only local artifacts and Python's standard library. Qualification compiles an isolated copy of the current library with Apple's SDK and extracts its public symbol graph. Every native target must be public; member mappings require their named member family, and mapped enum/equality APIs require the actual compiler conformance. Receipts retain the graph, all 747 witnesses, compiler/SDK/target, source hashes and input revalidation. CI checks both the ledger and freshly compiled evidence. Eighteen corrupted-ledger/report controls are refused, including removal of the real header factory after recomputing the graph digest.

This proves public type/member-family presence, not equivalence of every overload, nested JS object field, return shape, default or behavior. Repeated overloads mapped to the same family are individually accounted for but are not independently type-checked against Java signatures. Compiler evidence supplements the focused native consumer tests and behavioral suites. It adds no corpus pass or ratified native mapping. The main audit remains 2,197 passed / 184 pending / zero failed. The twenty native input-shape dossiers and local carrier/filename cases remain separate qualification work. `--refresh` explicitly rebuilds this supplementary ledger after a reviewed policy change; unknown reference types/member families/export names fail instead of silently disappearing.

## Public additions found by this audit

```swift
let matcher = try DefaultLocaleMatcher(supportedLocales: ["en", "fr"], fallbackLocale: "en")
let ranges = try LanguageRange.parse("fr;q=0.9,en;q=0.8")
let deferred = try TranslationOptions.forLanguageRanges(ranges)
let negotiated = try TranslationOptions.forLanguageRanges(ranges, using: matcher)
let header = try TranslationOptions.forAcceptLanguage("fr;q=0.9,en;q=0.8", using: matcher)
let localeMode = BuildMetadata.current.localeDataMode   // "pinned"
let cardinalMode = BuildMetadata.current.cardinalityMode // "exact"
```

`LanguageRange.parse` exposes the existing strict parser with explicit pinned `.ianaRegistry` (default) or `.jdk` expansion. It imposes neither the 4,096-unit raw-header guard nor the matcher’s 32-expanded-range cap. The one-argument options factory retains deferred strict ranges; the `using:` overload negotiates immediately and retains the actual match object. The header factory processes an already combined optional header value and preserves match diagnostics. Missing, malformed, blank, oversized or over-expanded headers negotiate an empty list, preserving an honest unmatched result rather than manufacturing a fallback match. A custom matcher's unrelated parser/negotiation errors propagate. Consumption still checks the supplied match against the `DefaultStrings` instance.

Thirty-seven standalone checks cover those contracts, including IANA expansion crossing the cap, q=0 exclusions, custom error/reference identity and actual translation consumption. A fresh source-only SwiftPM consumer imports and executes the new APIs without reference artifacts or external dependencies. macOS 12-target compilation is separate from old-OS/iOS/Intel runtime and minimum Swift 6.2 execution; those platform gates remain open.
