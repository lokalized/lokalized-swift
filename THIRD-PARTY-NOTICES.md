# Third-party notices

Lokalized for Swift is licensed under Apache-2.0; see [LICENSE](LICENSE) and
[NOTICE](NOTICE). The library compiles the following derived data into Swift
source. These notices and the complete texts in `Licenses/` accompany source
distributions. Include them in associated documentation when redistributing
the library or a binary containing its data.

## Unicode CLDR 48.2

`Sources/Lokalized/Data/PluralTables.swift` and `LocaleTables.swift` derive from
the shared CLDR 48.2 exports. The upstream inputs are:

- `common/supplemental/plurals.xml`, `ordinals.xml`, and `pluralRanges.xml`
- `common/supplemental/likelySubtags.xml`, `supplementalMetadata.xml`, and `supplementalData.xml`
- `common/properties/scriptMetadata.txt`
- `common/validity/language.xml`, `script.xml`, `region.xml`, and `variant.xml`

Source: [Unicode CLDR release-48-2](https://github.com/unicode-org/cldr/tree/release-48-2).
Copyright © 1991-2025 Unicode, Inc. All rights reserved. The complete Unicode
License v3 notice preserved from the shared export is in
[Licenses/Unicode-CLDR-48.2.txt](Licenses/Unicode-CLDR-48.2.txt).
`Reference/cldr-data-lock.json` and the generated source headers record the
input and payload identities. No CLDR XML is parsed during a consumer build.

## Unicode 15.0

`IdentifierTables.swift` and the Unicode casing data in `LanguageRangeTables.swift`
preserve the Java 21 oracle's Unicode 15.0 categories and ROOT lowercase behavior.
They are generated from runtime observations; no OpenJDK implementation source
or bytecode is included in the Swift library. The pinned runtime's complete
Unicode 15.0.0 notice is preserved verbatim in
[Licenses/Unicode-15.0.md](Licenses/Unicode-15.0.md), including its 1991-2022
Unicode copyright and permission notice. Its source and digest are recorded in
`Reference/identifier-notices.json`; the behavioral projection is documented in
[identifier provenance](Documentation/IDENTIFIER-DATA.md) and
[language ranges](Documentation/LANGUAGE-RANGES.md).

## Unicode 17.0.0

`IDNAUnicodeTables.swift` derives UTS #46 mappings, canonical decompositions,
combining classes and composition pairs from Unicode 17.0.0. The independent
canonical NFC utility and manifest domain mapping use these tables.

Sources: [Unicode 17 UCD](https://www.unicode.org/Public/17.0.0/ucd/) and
[Unicode 17 IDNA data](https://www.unicode.org/Public/idna/17.0.0/).
Copyright © 1991-2026 Unicode, Inc. The complete Unicode License v3 text is in
[Licenses/Unicode-17.0.0.txt](Licenses/Unicode-17.0.0.txt) and in the generated
Swift source. `Reference/Unicode-17.0.0/data-lock.json` pins each source and
compiled payload; [manifest URL processing](Documentation/MANIFEST-URLS.md)
explains the distinction between Unicode mapping and URL compatibility.

## IANA Language Subtag Registry

The IANA portions of `LanguageRangeTables.swift` derive from the
[IANA Language Subtag Registry](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry),
File-Date **2026-09-17**, SHA-256
`755fad43283be7b41ebe3c89ad054b6eaf928f404f9c0edb74799e0eab74beb1`.
They encode language equivalence classes and region/variant substitutions;
substitution order follows the separately recorded JDK compatibility overlay.
The registry snapshot has no accompanying license text. Provenance and the
derivation recipe are preserved in `Reference/IANA-PROVENANCE.md` and the shared
IANA locks. Consumers read the generated tables, not the registry file.

## Ada URL compatibility data (MIT)

`IDNACompatibilityProperties.swift` and `IDNACompatibilityNormalizationTables.swift`
derive compact property and normalization tables from the Ada data embedded in
[Node v26.5.0's Ada source](https://raw.githubusercontent.com/nodejs/node/v26.5.0/deps/ada/ada.cpp),
source SHA-256 `ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4`.
They preserve the separately recorded Node 26.5.0 / Ada 4.0.0 URL compatibility
profile. The lookup and normalization algorithms in Swift are original;
the Node/Ada executable implementation is not embedded or linked.

Copyright 2023 Yagiz Nizipli and Daniel Lemire. The complete MIT text is in
[Licenses/Ada-MIT.txt](Licenses/Ada-MIT.txt) and both generated source files.
`Reference/IDNA-Compatibility/README.md` and its two profile files retain the
data and binary-oracle provenance. This material is used only by pure manifest
URL helpers; the library performs no HTTP loading.

## Behavioral acknowledgements and development artifacts

The catalog JSON reader reproduces observable behavior of the minimal-json reader
embedded by Lokalized Java. [minimal-json](https://github.com/ralfstx/minimal-json)
is MIT-licensed; no minimal-json implementation source is copied into Swift.
The floating-point, locale projection and other compatibility algorithms are
original Swift implementations qualified against Java/JS observations.

The complete source archive also carries development-only snapshots from
`lokalized-spec`, `lokalized-java`, and `lokalized-js`. Their original notices
remain under `Reference/` (`LICENSE.java`, `LICENSE.js`, `LICENSE.spec`,
`NOTICE.js`, and `THIRD-PARTY-NOTICES.*.md`), alongside the Unicode/Ada notices
and the pinned URL recipe in `Tools/URLOracle/`. Those upstream notices retain
their original paths. [Reference baseline](Documentation/REFERENCE-BASELINE.md)
maps the archived inputs. These files are not runtime dependencies or library
resources; none is required to compile or use `Lokalized`.
