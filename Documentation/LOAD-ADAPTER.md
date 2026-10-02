# Native loader conformance adapter

The M6 adapter executes `LocalizedStringLoader.loadFromDirectory` against real owned filesystem trees. It uses the frozen corpus inputs and `Reference/materialized-fixtures.json` authored bytes. Expected values participate only in full-field comparisons after execution. Fixture IDs determine the relative directory names; they do not select behavior.

`LokalizedConformance --loader --reference Reference --report PATH` reports 145 passing filesystem observations, five pending native diagnostic-order adaptations, and 159 pending JVM carriers. The eligible ID digest is `6c6043d0326a9a524690c485292cc2cd748161504fbaa5c0c7fcb97d91e16991`: sorted ASCII IDs, each followed by LF, including the last. The main corpus audit executes 2,197 cases and retains 184 pending cases, with no native representation mappings ratified.

Materialization reproduces the pinned JS build recipe for directory, absent-path, and regular-file path shapes. Nested directory files use archived authored bytes; the special-file fixture contains an actual FIFO created with `mkfifo`. Every authored file must occur in the materialized inventory. File writes use POSIX UTF-8 paths because Foundation's filesystem representation decomposes some filename text. This preserves the precomposed `café.json` input alongside the genuinely decomposed fixture without editing native diagnostics.

The adapter compares loaded locale tags, exact UTF-16 keys, failure type and message, and every warning field in callback order. Temporary path projection substitutes only the actual owned canonical fixture-root prefix at a path-token boundary with `<fixtures>`. It preserves relative segments, filename spelling, parse positions, and all other text. It never edits expected messages or substitutes a different filename.

Ordinary directory fixtures also use the real directory loader when preparing `DefaultStrings` for the existing get/getResult/construct adapter. The 1,432 M5 eligible IDs and their full result, failure, identity, and callback comparisons remain unchanged. Non-directory carriers retain the earlier explicitly scoped parser projection. Twelve separate native checks exercise real loads, an explicit URL resource map, full public translation results, immutable old/new loaded instances, canonical-equivalent key identity, deterministic failure ordering, and path-projection boundaries.

## Unresolved diagnostic ordering

Native directory discovery charges entries before retaining names, then processes the bounded inventory in unsigned UTF-8 filename order. Frozen Java 3.1.0 processed raw `DirectoryStream` traversal order. All three frozen discovery-entry overflow cases have warning-free contents and no competing parse faults, and their observations match. Independent native loader qualification covers the enumeration-first safety ordering.

Three input-only predicates keep five cases pending until the shared native diagnostic precedence is resolved:

- More than one regular `.json` filename has an invalid locale stem. The frozen first refusal names `zz.json`; native sorted processing names `notes.json`.
- The number of distinct loadable locale files exceeds the configured positive aggregate file cap. Three fixtures name a different file at cap exhaustion under native ordering.
- A valid exact locale basename occurs both extensionless and with an ASCII case-insensitive `.json` suffix. The `en`/`en.json` fixture names a different duplicate filename under native ordering.

These predicates use input files, pinned locale classification, and validated loading options. They never inspect expected output, and the guard applies after a case is renamed or its expectation is replaced. Case, legacy-language, and grandfathered filename alias collisions remain real native passes; the extensionless/JSON predicate is deliberately specific and is not a blanket duplicate-locale mapping.

The report retains all five actual native observations, frozen reference observations, and comparison differences in `adaptationObservations`. Those observations are separate from the passing list. The five adaptation IDs have LF-delimited SHA-256 `f2e4b155d9ff9f7a77acf00a53fcead51f8482fce9e47230466543a51f779131`.

## Missing JVM carriers

Ninety `loadClasspath` cases request JVM package discovery, including classloader roots, package-name normalization, namespace rules, and JAR discovery. Sixty-nine `loadClasspathResources` cases map locale tags to classloader-relative resource names. Swift's native URL map accepts already resolved URLs, and Bundle lookup has its own platform semantics. Neither reproduces those inputs by relabeling a directory. All 159 remain pending with explicit carrier categories; native URL-map and packaged Bundle qualification are separate evidence and do not turn them into corpus passes.

## M8C native disposition evidence

The [loader disposition qualification](LOADER-DISPOSITIONS.md) now accounts for all 164 pending IDs individually. All are informational in the frozen corpus. It compiles an isolated current standalone executable, executes twenty named Bundle/resource-map/ordering controls, and requires the five native messages to differ only in the specifically derived authored filename. Twenty-five corrupted-receipt controls are refused. The 159 JVM inputs remain unreplayed platform-specific carriers and the five filename mappings remain unratified; the original 145 passing observations and all frozen observations are unchanged.
