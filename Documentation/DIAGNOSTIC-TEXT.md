# Shared diagnostic text amendment

M8J consumes `lokalized-spec`'s `diagnostic-text-v1.1` profile, version 1.1.0.
All 36 raw catalog/manifest documents run through the public Swift parsers, with
exact UTF-16 comparisons. Java runs the 18 catalog cases; JS runs all 36. The
shared [contract](../../lokalized-spec/DIAGNOSTIC-TEXT.md) describes the rule and
native error representations. The local copies and checker are sufficient for
offline qualification without a sibling checkout.

Paths retain the 4,096-unit limit and quoted nested duplicate-member displays
the 256-unit limit. If truncation splits a surrogate pair, the retained high
surrogate becomes U+FFFD before the ellipsis, keeping a valid Unicode diagnostic
at the cap. Swift already repaired this boundary. Java and JS now follow the
same rule. Nested manifest duplicate-member names now use the catalog display
cap in both JS and Swift. The catalog/manifest parsing APIs, source labels,
error precedence and separate path-field representations are preserved.

The five byte-pinned artifacts are `Reference/diagnostic-text-v1.1.json`, its
schema and `Tools/DiagnosticText`'s scalar-based recipe, strict report checker
and package marker. Check them with `python3 Tools/sync_diagnostic_text.py --check`
and `python3 Tools/verify_diagnostic_text.py --check`. An explicit sync requires
`--source` pointing to the canonical spec checkout and verifies every source
before writing. Java and JS keep digest-checked fixtures in their test trees.

Run `LokalizedConformance --diagnostic-text --reference Reference --report PATH`,
then `python3 Tools/verify_diagnostic_text.py --report-check PATH --negative-controls`.
The latter rejects fifteen changed versions, inputs, inventories, outcomes,
texts, paths, source labels, error names or unknown fields. A report check
validates saved observations; runtime qualification comes from executing the
standalone binary. Two XCTest wrappers exercise all cases and refuse changed
fixture bytes before execution. Development-only fixtures and Python checks
introduce no consumer dependency.

`verify_deployment.py` hashes the snapshot, checker and current Swift sources,
builds fresh binaries for four Apple SDK targets, and executes the diagnostic
command on its native macOS host. M8J locally qualifies 128 Swift sources and
sixteen binaries on Swift 6.4 / SDK 27 / arm64 macOS 27.0.1. The 36 diagnostic
observations pass alongside the unchanged 2,197 passing / 184 pending core
ledger and 468 matching / 31 carrier-pending raw manifest report. The shared
correction adds no runtime passes to these historical ledgers. Original archive
and lock bytes remain unchanged.

The full JS regression suite passes all 2,332 tests, and its type check passes.
Java passes 110 loader/profile test methods, including all 18 shared catalog
vectors. Swift passes 26 selected parser/manifest test methods. Six shared
Python tests and three isolated offline snapshot/saved-report checks pass.
Scoped evidence lives under `.build/reports/m8j-*`. Minimum Swift 6.2,
minimum-OS, iOS and Intel execution and hosted CI remain unverified locally.
The separate [manifest normalization amendment](MANIFEST-NORMALIZATION.md) is now
qualified by M8K; it is not part of the diagnostic profile. Swift continues to have zero external runtime dependencies
and application-owned remote acquisition.
