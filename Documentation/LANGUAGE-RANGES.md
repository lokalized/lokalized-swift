# Pinned language ranges and header parsing

M3 provides immutable `LanguageRange` values, Java 21 extended-range validation,
strict weighted-header parsing, and two deterministic equivalence sources. No
host locale parser, Unicode casing API, runtime JSON, network access, or external
runtime dependency participates.

`LanguageRange(_:, weight:)` lowercases the range using the pinned Java 21 ROOT
casing projection, validates RFC 4647 extended-range subtags, and expands
nothing. The first subtag admits 1–8 ASCII letters or `*`; later subtags admit
1–8 ASCII letters/digits or `*`. A one-letter subtag is legal. Weights default
to 1 and accept 0 through 1, signed zero, and Java's constructor-accepted NaN.
Invalid weights are checked before range grammar. An empty range is invalid;
hyphens-only ranges have the distinct pinned JDK 21 bounds-error diagnostic.
`LanguageRangeError.kind` separates `invalidArgument` and `indexOutOfBounds`,
with the original Java message.

Value copies preserve NaN identity, reproducing Java's same-object equality
shortcut; separately constructed NaN ranges compare unequal. Finite weights
compare numerically, so signed zeros compare equal. Swift canonicalizes their
hashes to honor `Hashable`; JDK 21 itself hashes those equal weights differently.
Rendering retains signed zero and uses the M2 exact Java floating-point printer.
Range strings are ASCII after validation, so Swift's canonical-equivalence
string equality cannot merge distinct accepted ranges.

## Parsing and expansion

`LanguageRangeParser.parse(_:equivalents:)` is the package implementation behind
`LocaleMatcher.parseLanguageRanges`. It removes U+0020 spaces globally, applies
ROOT lowercase, drops an initial `accept-language:` prefix, and splits on ASCII
commas with Java's trailing-empty behavior. It preserves interior empties, rejects
an empty value, and lets a comma-only value produce an empty list. Delimiters are
matched as UTF-8 bytes; combining marks cannot hide commas, the prefix, or `;q=`
inside a Swift grapheme cluster.

The weight grammar is Java `Double.parseDouble`, including scientific decimal,
hexadecimal `p` exponents, `f`/`d` suffixes, Java trim of code units <= U+0020,
overflow, subnormal rounding, and signed-zero underflow. Binary64 conversion
uses the Swift standard library only after explicit lexical validation. The
pinned oracle compares actual weight bits, rather than formatted approximations.
`NaN` and `Infinity` are accepted by the numeric helper, but header lowercase
changes them to `nan`/`infinity`, which that case-sensitive grammar rejects.
Numeric refusals quote the normalized weight text; out-of-range numeric refusals
use the exact Java floating-point spelling. A duplicate member's weight is still
validated before duplicate suppression.

The first occurrence of a range owns its weight, including ranges already added
as equivalents. Insertion uses the first strictly lower weight, preserving
request order within a weight tier. The region/variant arm runs first, then the
longest known language-prefix arm with its original suffix retained. A region
rewrite also applies to each language equivalent. Each unseen expansion is
inserted at the original member's index plus one, reversing its authored
expansion order. For example, `sgn-BE-FR` parses as
`sgn-be-fr, sgn-sfb, sfb, sgn-be-fx`. Region/variant matching retains the pinned
14-pair order and stops rewriting inside singleton extensions.

Strict parsing has **no length, input-member, or expanded-member cap**, matching
the Java API. The matcher separately rejects more than 32 supplied/parsed ranges.
Its fail-soft HTTP ingress separately applies 4,096 UTF-16 units, normalizes
horizontal tabs/empty HTTP members, and falls back on parse failure or excess
expanded ranges. Those policies must not be moved into this strict parser. A
native qualification explicitly parses 300 strict members.

## Data and representation

`LanguageRangeEquivalents.ianaRegistry` (raw name `IANA_REGISTRY`) is the default:
369 ordered classes / 781 keys from the shared IANA registry dated **2026-09-17**.
Its registry bytes have SHA256
`755fad43283be7b41ebe3c89ad054b6eaf928f404f9c0edb74799e0eab74beb1`;
the shared exported closure's SHA256 is
`2398b866e6739ae81d9484da929567e68e8255fe31aefe5bf2ef25846c611462`.
The dated JDK compatibility overlay also pins the 14 region/variant substitutions
and their iteration order.

`LanguageRangeEquivalents.jdk` (raw name `JDK`) means the **bundled Corretto
21.0.11** table: 769 keys, originating from the JDK's IANA revision **2025-05-15**.
Swift cannot consult a running JVM; this deliberate platform policy preserves
the Java option's naming and offers a reproducible reference table. It is
observably distinct: `yol` expands to `enm` in registry mode and remains alone
in pinned JDK mode.

`LanguageRangeTables.swift` compiles ASCII UTF-8 `StaticString` blobs plus UInt32
row offsets. First use builds indexes from range keys to row positions; values
are decoded from the fixed row when requested. Runtime tables never read
reference files. The casing projection uses fixed-width hexadecimal scalar
mappings and property ranges, with binary search over those blobs. The generated
Swift file is **76,994 bytes**, a source-size figure rather than linked size or
initialization heap measurement; those costs have not been benchmarked.

The Unicode projection pins **1,433** full singleton lowercase mappings and
**1,376** word-property ranges from Java 21 / Unicode **15.0**. Its original word
tokenizer preserves contextual final sigma, including the JDK's queried UTF-16
boundary after a surrogate pair. Java's queried boundary can differ from its
forward word iterator: this distinction was caught by the broad differential and
has dedicated local regression goldens. Kelvin-sign folding and dotted-I's
multi-scalar expansion are also pinned; newer host Unicode data is irrelevant.
The locale kernel can reuse `LanguageRangeLowercase.apply` for its raw ROOT
lowercase helpers.
Pure ASCII inputs take an A–Z byte-mapping fast path, avoiding the Unicode
scalar array and table lookups while preserving the same pinned results.

| Archived/compiled input | SHA256 |
| --- | --- |
| JDK factual data archive, 173,075 bytes | `cfa23bf8a516c91a33d22376125b0f93c361d729e094f08d84c57c289fbf1b95` |
| Generated Swift tables | `b11411a2e513f95ca7c43861b4a93f6d54f2a5dff4b51cbb178bf179b92ebfda` |
| Local parser/casing/weight goldens, 629,401 bytes | `2ce290f0f3bd2176b98416f4cc20c33ecd0fd192973e3b487262018edc47d73f` |
| Archived Java IANA parser, 35,994 bytes | `9d11a1ce46ba506c4b4286bc804919ab31b22179d882d99047f6f75b1c680992` |
| Corretto JDK release bytes | `31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239` |

The factual archive records the JDK release/vendor/build, five original JDK source
pins, capture-program pin, dated registry revision, Unicode version, full
mappings, and ordered substitutions. The capture queries the actual pinned
runtime. It does not copy JDK implementation source or generated Java source
into the Swift library. The Swift parser follows the Apache-licensed Lokalized
algorithm, with original bounded lexical/casing code. Unicode facts retain the
[Unicode 15 notice](../Reference/identifier-notices.json); shared IANA facts retain
the [existing third-party notices](../Reference/THIRD-PARTY-NOTICES.spec.md).
The archived Apache Java parser retains its original copyright/license notice
and is development-only.

## Regeneration and independent checks

Normal commands need Python's standard library and, for the golden driver,
`swiftc`; they need no Java, sibling repositories, or network:

```sh
python3 Tools/generate_language_range_data.py --check
python3 Tools/verify_language_ranges.py --check
```

The generator pins the whole IANA and JDK archive digests, validates provenance,
class uniqueness/order, region/variant order, scalar/word ranges and safe byte
encoding, regenerates in memory, and compares the whole generated Swift file.
`--refresh` is the explicit local rewrite. An explicit
`--capture-jdk --jdk /path/to/corretto/Contents/Home` can capture a replacement
archive only after release/vendor/build/source-pin checks; a deliberate update
also requires updating the fixed archive SHA. No runtime build runs this capture.

The verifier compiles actual production range sources in an isolated temporary
directory. Its **3,663** checked-in goldens cover 957 IANA headers, 957 JDK headers,
180 weighted constructors, 1,549 lowercase cases, and 20 numeric weight-bit cases.
It pins the whole golden archive, independently reconstructs its exact input
inventory, and checks original oracle provenance. Native XCTest checks the same
goldens and every mapping/property-range boundary; the standalone
`LanguageRangeQualification.run()` adds 29 checks without reference file reads.

The explicit broad development oracle is:

```sh
python3 Tools/verify_language_ranges.py --oracle \
  --jdk /path/to/amazon-corretto-21.jdk/Contents/Home \
  --report /tmp/lokalized-range-oracle-report.json
```

It executes the actual JDK constructor, JDK parser, ROOT lowercase and weight
parser. For registry mode it compiles the archived, source-pinned Lokalized Java
IANA helper called by the public Java default parser; the archive comes from
Java 3.1.0 commit `63b63e47c982f7a87873c52ac2289cc0392f3329`.
The oracle takes only operation/input/weight bits, never expected outputs.
It uses `-XX:-OmitStackTraceInFastThrow`: after many probes the normal JIT can
replace repeated bounds failures with message-less exceptions; disabling that
optimization retains the documented pinned diagnostic for comparison. The
option is recorded in reports and goldens.

On 2026-10-01 the final broad run passed **107,011** observations with zero
differences: 46,423 registry headers, 46,423 JDK headers, 13,965 casing contexts,
180 constructors and 20 numeric weight-bit cases. Inputs span every equivalence
key, suffix/wildcard/region/variant/extension combinations, all changed Unicode
scalar mappings, every observed property-range endpoint around sigma, ordering,
duplicate and malformed cases, and direct NaN/signed-zero weights. Input SHA256
was `ffb73bea5037d6f2315d249d75b75b6e32757d3c35efa03c7311a363841a15da`;
output SHA256 was
`0785682de108daeb35f25f3a449f73e2fd90b228179be4c5df00e3f67ff6ea8a`.
Production source concatenation SHA256 was
`d70e4f34c4b396033ad87dd063d912880e6bbcc160d828f130e7a341b9a595e0`.
The local report is `/private/tmp/lokalized-m3-range-oracle-report.json`.

These results used arm64 Apple Swift 6.4 / Swift 6 language mode and the pinned
Corretto release. They are development evidence rather than exhaustive Unicode
string enumeration, minimum-OS execution, or minimum Swift 6.2 qualification.
The full locale matcher and shared corpus accounting have their own gates.
