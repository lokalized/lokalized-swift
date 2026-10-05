# Catalog parser differential stress

`Tools/verify_parser_stress.py` generates bounded, deterministic byte inputs and
compares actual parsing by current Swift and a freshly compiled Java 3.1.0
reference. It supplements the fixed shared corpus. Generated inputs and results
stay in temporary directories or `.build/reports`; they are not runtime resources
or a new checked-in golden archive.

## What is compared

Every input reaches the public `Data`/`InputStream` catalog parser with the same
source label, authored locale and loading options. The probe compares:

- Returned roots, sorted by exact UTF-16 key order, including translation,
  commentary, generated-placeholder definitions and nested alternatives.
- Authored placeholder and alternative order. Language-form maps are sorted by
  their shared wire tokens; value/range selectors and fragment modes remain distinct.
- The actual refusal class and exact main diagnostic. The sole measured mapping is
  Java `com.lokalized.LocalizedStringLoadingException` to Swift `StringsParseError`.
  Unknown Java classes and unused mappings fail the check.
- Every warning message delivered to the handler, in order, including warnings
  delivered before a later failure. A refused warning is not delivered.

All authored text is emitted as arrays of integer UTF-16 units. This preserves
composed/decomposed spelling, supplementary characters and control characters
without output-stream repair or Unicode normalization. Nil and empty values have
different wire representations. Unknown fields, missing/reordered/duplicate rows,
lost classes and malformed warning units are refused. Positive model families
must return; minimum accepted/refused/warning counts reject a degenerate oracle.

This check does not compare error causes, Swift error location/path properties,
warning metadata, reader/String doors, locale ingress or expression evaluation.
The focused regression tests separately inspect error locations through catalog
and manifest text/byte doors. Eager validation of authored alternative expressions
is exercised here; [expression stress](EXPRESSION-STRESS.md) now separately
compares compiled/evaluated behavior. Locale-input stress remains separate work.

## Inputs and provenance

The recipe uses a specified xorshift64 generator, a nonzero 64-bit seed and between
8 and 1,000 generated valid catalogs. It combines shorthand and structured nodes,
commentary, form/range selectors, generated fragments, nested ordered alternatives,
exact Unicode keys, JSON escapes, BOM and line-ending variants. Derived inputs
exercise structural deletion/replacement/truncation, competing schema failures,
warning-before-error order, strict UTF-8 and controls, valid/invalid surrogate
escapes, and byte/aggregate/depth/node/warning boundaries. A small reader-character
limit on byte input checks that the two budget doors remain distinct.

The Java library comes from a read-only `git archive` of commit
`63b63e47c982f7a87873c52ac2289cc0392f3329`. The tool requires exactly 62 package
sources and the original corpus source aggregate
`db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0`.
It freshly compiles those sources with `javac --release 9 -proc:none` on the same
pinned Corretto 21.0.11 build used by the floating-point oracle. The two explicitly
supplied annotation jars are compile-only; the Java execution classpath contains
only the fresh classes. The Swift probe compiles alongside all current production
Swift sources, with package access to retained authored placeholder order.

Receipts include seed/count, generated-input and observation hashes, exact source,
probe, annotation and baseline hashes, JDK identity, Swift compiler and commands.
Pinned inputs are checked again after execution. Temporary sources/classes/binaries
are removed. No source checkout, commit, download or shared baseline rewrite occurs.

## Running the check

From the repository root, using existing local prerequisites:

```sh
python3 Tools/test_parser_stress.py
python3 Tools/verify_parser_stress.py \
  --java-repository ../lokalized-java \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home \
  --jspecify-jar /path/to/jspecify-1.0.0.jar \
  --jsr305-jar /path/to/jsr305-3.0.2.jar \
  --report .build/reports/parser-stress.json
```

The default seed is `0x97e513cb4a826fd1`, with 200 generated valid catalogs and
4,705 total cases. Supply `--seed` and `--count` to explore another deterministic
sample. Any mismatch produces exit 1, retains the actual differing observations
in the report and attempts bounded delta deletion of the first mismatching input.
`--minimization-probes` defaults to 64 and may be 0–256. The reducer preserves the
differing output channels; review the reduced input before adopting it as a
regression. It does not promise a globally minimal input or identical root cause.

CI runs the eleven offline admission controls and the Swift regressions without
Java, annotation jars or a sibling repository. The development-only differential
requires its explicit local prerequisites and fetches none of them.

## October 4 qualification

The first 4,391-input run found five unsupported-escape cursor disagreements.
Expansion to 4,705 cases exposed 253 diagnostic disagreements: unsupported escapes
and competing syntax errors after a high surrogate. After the cursor correction,
six surrogate-priority disagreements remained. All 4,705 cases now agree.
A second seed, `0xb17620a4ed935fc9`, with 400 generated catalogs passes another
8,505 comparisons: 13,210 case executions across the two samples. Fixed edge
cases recur in both samples; this is not a count of unique inputs.

The reader now refuses an unsupported escape while its offending code unit is
current, and validates a pending high surrogate after decoding the next character.
Malformed escapes, raw controls and EOF therefore retain Java's first-error
priority. Valid surrogate pairs remain exact; unpaired surrogates remain refused.
Manifest parsing uses the corrected shared location directly, removing its former
one-unit cursor compensation. Small regressions retain the minimized `"\x` and
`"\uD800` cases and their competing-error variants.

The full native suite passes 285 test methods, with one existing malformed-filename
filesystem skip. Receipts live in `.build/reports/m8s-parser-stress*.json` and
`.build/reports/m8s-swift-tests.log`. These are finite, source-bound development
observations; the frozen shared corpus and native conformance policy are unchanged.
