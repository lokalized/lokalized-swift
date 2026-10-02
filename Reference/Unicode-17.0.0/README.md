# Pinned Unicode 17 IDNA data

These release files supply Lokalized's original Swift Unicode mapping and NFC implementation, together with complete Unicode 17 property APIs for independent data qualification. They are development and qualification inputs; applications use the committed immutable tables in `Sources/Lokalized/Data/IDNAUnicodeTables.swift`. Consumer builds do not invoke a generator, download Unicode data, load these reference files, or consult the operating system's ICU/Unicode tables. There are zero external runtime packages.

The mapping and NFC Unicode version is **17.0.0**, matching the version reported by the Node 26.5.0 / ICU 78.3 / Ada 4.0.0 development URL oracle. Browser URL validity has a separate explicitly pinned auxiliary-property compatibility profile: the complete Unicode 17 mark, bidi, joining, and combining-class properties alone do not reproduce that oracle's acceptance decisions. The URL processor uses Unicode 17 mapping, then the separately pinned [Node compatibility normalization and properties](../IDNA-Compatibility/README.md). Its global fast/slow normalization behavior and older auxiliary mark, ContextJ and bidi tables differ from the complete Unicode 17 NFC utility, which remains independently qualified. This does not claim strict Unicode 17 UTS #46 conformance. Both pins are independent of the Unicode 15.0 identifier tables and of Lokalized's seven runtime identity fields; they do not change catalog identity or the existing CLDR and IANA pins.

`data-lock.json` records the release URLs, byte counts, and SHA-256 digests of the exact downloaded data, the generator identity, each encoded table, and the generated Swift source. The Unicode 17 directory layout places IDNA data under `/Public/17.0.0/idna/`.

| Input | Use |
| --- | --- |
| [IdnaMappingTable.txt](https://www.unicode.org/Public/17.0.0/idna/IdnaMappingTable.txt) | UTS #46 mapping statuses and replacement scalar sequences. |
| [UnicodeData.txt](https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt) | Canonical combining classes, General_Category Mark, and canonical-only decomposition. Compatibility decompositions are omitted. |
| [DerivedNormalizationProps.txt](https://www.unicode.org/Public/17.0.0/ucd/DerivedNormalizationProps.txt) | `Full_Composition_Exclusion` determines which canonical pairs can compose. Hangul normalization is implemented algorithmically. |
| [DerivedBidiClass.txt](https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedBidiClass.txt) | Complete Unicode 17 bidi property API for independent qualification. All `@missing` defaults are applied before explicit rows. The browser acceptance profile is pinned separately. |
| [DerivedJoiningType.txt](https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedJoiningType.txt) | Complete Unicode 17 joining property API, including transparent characters, for independent qualification. The browser ContextJ acceptance profile is pinned separately. |
| [NormalizationTest.txt](https://www.unicode.org/Public/17.0.0/ucd/NormalizationTest.txt) | Official Unicode NFC qualification equations and the required scalar identity sweep. |
| [LICENSE.txt](https://www.unicode.org/license.txt) | Complete Unicode License V3 notice obtained with these inputs. |

`IdnaTestV2.txt` is the official Unicode 17 IDNA test input, with its own URL-oracle qualification pins and profile explanation. Its strict UTS #46 status fields are retained as evidence; browser URL expectations come from the separately pinned URL oracle.

Regenerate or verify the tables offline using Python's standard library:

```sh
python3 Tools/generate_idna_tables.py --generate
python3 Tools/generate_idna_tables.py --check
python3 Tools/verify_idna_tables.py --check --report .build/reports/idna-tables.json
```

Both modes require the exact committed input hashes and make no network requests. The generator coalesces adjacent equal ranges, stores scalar sequences once, and emits binary-searchable fixed-width ASCII `StaticString` payloads. The generated file embeds the complete Unicode copyright and permission notice so that copies of the compiled table source carry their attribution.

The independent table decoder check compiles a development probe and compares its binary output with a direct projection of the original data. It checks all 1,114,112 code points (including the 2,048 surrogate entries), all seven decoded properties, and all 1,046 canonical decomposition pairs' composition results. The frozen projection is 7,848,540 bytes with SHA-256 `de375da459ccff1ccb12ed6b8137019f84d0761f5a40585a34b4f586b05b5f62`. This checks the Swift payload offsets and lookups as well as the offline generation; the official NFC and URL suites qualify algorithmic behavior separately.

Table codes are deliberately internal: mapping `valid=0`, `ignored=1`, `mapped=2`, `deviation=3`, `disallowed=4`; bidi `L=0`, `R=1`, `AL=2`, `AN=3`, `EN=4`, `ES=5`, `CS=6`, `ET=7`, `ON=8`, `BN=9`, `NSM=10`, `other=11`; joining `U=0`, `L=1`, `R=2`, `D=3`, `T=4`, `C=5`. The bidi `other` code covers classes that cannot pass the IDNA bidi label rules. Mark classification uses the complete general category, including marks with combining class zero.

The data is covered by the [Unicode License V3](LICENSE.txt). The projection and lookup code are original Lokalized code; no ICU, Ada, or other implementation source is included.
