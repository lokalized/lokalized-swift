# Pinned locale behavior and data

`LocaleTag` supplies deterministic locale values on iOS 15 and macOS 12. The
production implementation uses Swift code and compiled tables; it does not use
Foundation locale negotiation, host locale inventories, network access, or
runtime JSON resources. The package has no external dependencies.

The JDK and CLDR stages stay distinct. `LocaleTag.forLanguageTag(_:)` reproduces
the pinned JDK's lenient projection: it discards an ill-formed suffix, preserves
variant case, collapses extlangs, replaces grandfathered tags, normalizes Unicode
extensions, and handles `x-lvariant` compatibility locales. The throwing
`LocaleTag(_:)` initializer additionally requires the complete input syntax and
Java `Locale.Builder.setLocale` rebuildability. `LocaleTagError` distinguishes
malformed tag syntax from a resulting malformed locale.

`tag` remains the JDK spelling. `cldrCanonicalTag` applies CLDR aliases as a
separate operation, including compound language aliases and likely-region
selection for multi-region replacements. For example, `mo-MD` retains its tag
and language identity while its CLDR canonical tag is `ro-MD`. Catalog filename
recognition separately requires full tag syntax and the pinned CLDR validity
inventory. An explicitly supplied unknown but syntactically valid locale such
as `zz` remains constructible.

Equality and hashing compare the underlying locale fields, including variant
case and normalized extensions. A rendered tag can hide different valid locale
identities: `forLanguageTag("und")` and `forLanguageTag("UND")` both render
`und` but retain empty and `und` languages respectively; `no-NO-x-lvariant-NY`
renders `nn-NO` while retaining its compatibility locale fields. Typed APIs
must preserve these values until an operation explicitly projects a tag.

Likely subtags return the full language/script/region result, preserve requested
fields and variants, and remove extensions. Fallback candidates follow explicit
CLDR parents, stop at likely-script boundaries, then consider truncation,
Norwegian bridges, and canonical aliases in the Java order. The CLDR `root`
parent is an internal sentinel and is excluded from public fallback candidates.
Plural lookup maps its internal `root` candidate to the exported `und` group.
RTL lookup uses an explicit script when present and the likely script otherwise.
ASCII tag casing and the pinned Unicode 15 ROOT lowercase helper keep this
behavior independent of host Unicode updates.

## Data provenance and representation

The frozen input is `Reference/cldr-locale-data.json`, CLDR 48.2, with source
SHA-256 `6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93`.
The schema SHA-256 is
`03097cf61a52b4e21b35a2f1d986373b706010ebaba61e89c72921905cf41784`.
The shared fingerprint is
`9b4f24165b6dd1ee6dbb5f0822abc7bcde49c5b94d35903045826b45e1f30e68`.
The generated file carries these identities and the compiled payload digest.

| Inventory | Rows |
| --- | ---: |
| Language aliases | 500 |
| Region aliases | 640 |
| Script aliases | 1 |
| Variant aliases | 2 |
| Likely subtags | 7,788 |
| Parent locales | 199 |
| Valid languages | 8,787 |
| Valid regions | 343 |
| Valid scripts | 244 |
| Valid variants | 134 |
| RTL scripts | 37 |
| Total | 18,675 |

`LocaleTables.swift` is 254,321 UTF-8 source bytes with SHA-256
`e0052d7191da16f9193782474d3dbc636e8d92fc7b04f4956629454138262621`.
Its `packed-text-maps-v1` format embeds compact text and lazily initializes
Swift dictionaries and sets on first access. This differs from the indexed
`StaticString` format used for the language-range tables: locale lookups retain
allocated key/value strings and hash-table storage in exchange for direct
lookup and straightforward complete-row verification. No JSON is decoded at
runtime. Allocation count and resident-memory cost have not been measured.

A development probe on arm64 macOS 27.0.1, Swift 6.4, with an optimized library
and macOS 12 deployment target touched all eleven tables in fifteen fresh
processes. Table initialization took 4.08–4.25 ms, median 4.15 ms; process launch
was excluded. This is local evidence, not an iOS or older-device performance
guarantee. `verify_locales.py` repeats this timing probe and records complete source and
artifact hashes. A static indexed locale representation remains a possible
optimization after allocation measurements establish a need.

The CLDR tables retain the Unicode-3.0 license, reproduced in
`Reference/THIRD-PARTY-NOTICES.spec.md`. The original Swift behavior port follows
the Lokalized Java Apache-2.0 source; no JDK source implementation is copied.

## Regeneration and independent verification

Run from the package directory:

```sh
python3 Tools/generate_locale_data.py --check
python3 Tools/verify_locales.py --check --report .build/reports/locale-goldens.json
swift run LokalizedConformance --locale-data --report .build/reports/locale-data.json
```

The generator checks the input and schema digests, validates every table row,
and compares the entire generated file, including headers, metadata, and
license references. Explicit `--refresh` regenerates it from the frozen input.
`verify_locales.py --check` compiles the actual library and consumer with Swift
6 language mode and an explicit macOS 12 target on macOS, using a writable
temporary module cache. It needs no JDK, sibling repositories, network, or
download. Reports capture commands, source hashes, compiled artifacts, and
actual observations; source changes during a run cause refusal.

`Reference/locale-goldens.json` is development-only expected data, 2,436,031
bytes, SHA-256
`40e876c0c61bdc4f9e0bbe51d95eb1462b503acecb97ace785f79b33f8be8e7d`.
It records 12,560 distinct inputs and 21 observations per input, authored from
actual Java locale code at corpus commit
`63b63e47c982f7a87873c52ac2289cc0392f3329` and pinned Corretto 21.0.11.
The inventory covers every language alias, region-alias alternatives for
English/Armenian/Russian, script/variant aliases, every likely-subtag and parent
key, every valid language and script, every RTL script, all 26 grandfathered
tags in two cases, and targeted JDK projection/identity cases. Expected data
never feeds production behavior.

The standalone native `--locale-data` audit verifies all 18,675 compiled rows
against the separately hashed CLDR input and compares all 263,760 Java/JDK
observations. Its 263,771 checks include eleven complete table comparisons.
It rejects tampered archives before decoding; native tests cover that refusal.
Forty-five additional standalone checks exercise the public API without files
or XCTest.

To repeat the independent live oracle, explicitly select the pinned JDK and
Java checkout:

```sh
python3 Tools/verify_locales.py --oracle \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home \
  --java-repository /path/to/lokalized-java \
  --report .build/reports/locale-oracle.json
```

The tool extracts `LocaleUtils`, `CldrLocaleData`, `GeneratedCldrLocaleData`,
and `Diagnostics` from that frozen Git commit into a clean temporary tree and
compiles them using declaration-only annotation stubs. Reports hash those
sources, the harness, annotations, classes, input rows, Swift sources, consumer,
library/module, and outputs. `--refresh-goldens` writes a new archive only after
actual Java and Swift observations agree; its new digest must then be reviewed
and updated in both checkers.

Local qualification passed all 12,560 rows with zero differences using Swift
6.4, macOS SDK 27, and the pinned JDK. The identical Swift/Java observation TSV
SHA-256 is `846a248b0d51c6149bda201af2164f61303da5680654e01aee9843326719a41b`.
The exact minimum Swift 6.2 compiler and execution on iOS 15/macOS 12 were not
available locally; deployment emission/link evidence is tracked separately in
`Documentation/DEPLOYMENT.md`.
