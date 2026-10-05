# Locale-input differential stress

`Tools/verify_locale_stress.py` generates bounded language tags, mutates their
code points and compares the current Swift port with fresh Java 3.1.0 sources
on the pinned Corretto 21.0.11 runtime. It supplements the complete CLDR table
and fixed JDK locale audit in [locale data](LOCALE-DATA.md). Generated cases and
observations live in temporary storage and `.build/reports`; they are not
package resources or a new golden archive.

The probes compare 21 actual output fields: lenient JDK tag projection;
language, script, region, variant, extensions and Java identifier; rebuildability,
full input syntax, strict construction and catalog-filename eligibility; raw and
projected CLDR canonical/likely results; fallback locales, validity,
undetermined/private status and writing direction. Every value is emitted as
integer UTF-16 units. Missing, reordered or malformed observations, changed
source inputs and insufficient accepted/refused/projection coverage fail closed.
This slice does not compare strict-constructor diagnostic chains, language-range
parsing, locale matcher election or Java strings containing unpaired surrogates.

The Java probe compiles a read-only archive of all 62 sources at frozen commit
`63b63e47c982f7a87873c52ac2289cc0392f3329`; their aggregate SHA-256 is
`db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0`.
The JDK release and source identity are checked. Annotation jars are
compile-only, and the Java execution classpath contains only fresh classes.
Swift compiles beside all current production sources. The explicit generator
uses the same frozen xorshift recipe as the parser and expression stress tools.
Both probes and source hashes are recorded and rechecked after execution.

## Findings and fix

The initial 1,933-case sample exposed 59 differences. Most came from the
lenient CLDR tag parser using ASCII-only script/region tests where Java uses
`Character.isLetter(char)` and `Character.isDigit(char)`. In particular,
`in-Katn-fonipa-x` should canonicalize to `id-Katn-fonipa-x`; treating `Katn`
as a variant instead changes the script to `Katn` on a later pass. Two more
inputs exposed Swift `String.split` treating a hyphen followed by a combining
mark as one grapheme. Java splits at the hyphen code unit and retains the valid
prefix of `ji-́u` as `yi`.

The JDK parser and CLDR projection now split at ASCII byte `0x2D`, preserving
empty subtags. The lenient CLDR parser uses the existing pinned Unicode 15
letter table and a generated pinned Java BMP decimal-digit/uppercase table.
The development generator verifies Corretto's exact release plus the
`Character`, `String`, `StringLatin1` and `StringUTF16` source hashes before
capturing mappings. Its generated Swift source is pinned at SHA-256
`c5e48e0d56fcbf64b38bc315a28938cae1322bd433ff3ac55d06426638307ccd`.
No host Unicode category or case API participates in runtime locale projection.

The generated table adds 37,608 source bytes and no runtime resource or package
dependency. The checked source-size cap for runtime Swift was raised one 64 KiB
step, from 1,310,720 to 1,376,256 bytes; generated Swift remains within its
unchanged 851,968-byte cap. Binary-size measurement is recorded separately.

## Running it

From the Swift repository root, using existing local prerequisites:

```sh
python3 Tools/test_locale_stress.py
python3 Tools/generate_locale_unicode_tables.py --check
python3 Tools/generate_locale_unicode_tables.py --oracle-check \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home
python3 Tools/verify_locale_stress.py \
  --java-repository ../lokalized-java \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home \
  --jspecify-jar /path/to/jspecify-1.0.0.jar \
  --jsr305-jar /path/to/jsr305-3.0.2.jar \
  --report .build/reports/locale-stress.json
```

The default seed is `0x4ca1e5d7b0912683` with 300 generated rounds. `--count`
accepts 32–2,000. The checker never fetches a JDK, alters the Java checkout or
creates a Git commit. CI runs the eight offline recipe tests and table digest
check without the pinned local JDK; the full differential is opt-in.

## October 4 qualification

The two final seeds passed 1,938 and 3,738 cases, **5,676 case executions**
with zero differences across all 21 fields. The Java observations contain
2,928 strictly accepted and 2,748 refused inputs. Fixed edges recur across
seeds, so the count is not 5,676 unique tags. The focused 16-method native
`LocaleTagTests` suite, including the pinned locale-golden audit and minimized
regressions, passes on current Swift 6.4 arm64 macOS 27. The generated table's
live pinned-JDK reproduction and source budget check pass. The complete Swift
suite passes 286 test methods with one existing filesystem skip. One fresh
optimized source-only consumer build measures 2,301,576 stripped bytes and
passes the existing 2,555,904-byte cap; this single sample is not a timing
comparison with earlier source states.

Receipts: `.build/reports/locale-stress-default.json` and
`.build/reports/locale-stress-second-seed.json`, plus
`.build/reports/locale-stress-package-size.json`. The actual Swift 6.2/Intel,
iOS 15/macOS 12 runtime and physical-device gates remain separate.
