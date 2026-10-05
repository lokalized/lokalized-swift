# Expression differential stress

`Tools/verify_expression_stress.py` generates bounded, deterministic expression
inputs and compares the current Swift implementation with freshly compiled,
frozen Java 3.1.0 sources. This is a development check, separate from the shared
behavioral corpus and the native expression qualification suite. It adds no Swift
runtime dependency or checked-in generated archive.

## Compared behavior

Each case compiles once and evaluates the retained expression against one or more
typed contexts. The probes compare compile success or refusal; returned Boolean
values; full exception cause chains and exact diagnostic UTF-16 units; and every
phonetic resolver call's raw term and supplying locale in order. Scenarios include
numeric literals and all six comparison operators, Boolean precedence and skipped
branches, byte/short/integer/long/big-integer/decimal/float/double carriers,
plural categories across several locales, all 61 language-form constants,
malformed token streams, source/token/nesting/number limits, exact composed and
decomposed identifier keys, and resolver return/throw paths. Float and Double
inputs use exact bit patterns.

The Java probe uses actual `ExpressionEvaluator.compile` and
`evaluateCompiledExpression`; the Swift probe uses the package-visible compiler
and evaluator. The Java source snapshot is a verified read-only `git archive` of
`63b63e47c982f7a87873c52ac2289cc0392f3329` with 62 files and aggregate hash
`db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0`.
The pinned Corretto 21.0.11 JDK is checked before use. Annotation jars are
compile-only; Java runs solely from freshly built classes. Swift builds beside
all production library sources. The probe parses context JSON through the
library's exact-key reader: Foundation dictionary decoding can collapse
canonically equivalent Unicode spellings and would make the comparison invalid.

The explicit Swift error-kind mapping is checked against observed Java class
names. An unknown refusal class, malformed UTF-16 diagnostic/trace, changed
result shape, missing/reordered row, altered probe input, or inadequate
accepted/refused/callback coverage fails closed. Reports retain all source/probe
hashes, generated input and actual observation hashes, compiler/JDK identities,
commands and up to 100 full mismatches. Temporary sources and binaries are
removed. A mismatch should be reduced and retained as a focused regression
before changing production code.

This finite check does not cover whole-message contextual wrapping, generated
alternatives, arbitrary custom Java `Number` subclasses or callback object
identity. Existing native expression and corpus checks address adjacent behavior.
Locale-input fuzzing and shared observer vectors remain separate work.

## Running it

From the Swift repository root, with already-installed local prerequisites:

```sh
python3 Tools/test_expression_stress.py
python3 Tools/verify_expression_stress.py \
  --java-repository ../lokalized-java \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home \
  --jspecify-jar /path/to/jspecify-1.0.0.jar \
  --jsr305-jar /path/to/jsr305-3.0.2.jar \
  --report .build/reports/expression-stress.json
```

The default seed is `0xe7a6634c214812b9` with 250 generated rounds. Change
`--seed` and `--count` (32–2,000) for a second deterministic sample. The tool
never downloads prerequisites, modifies the Java repository or creates commits.
CI runs the seven offline recipe-admission checks without a Java checkout.

## October 4 qualification

Two seeds passed 1,450 and 2,700 cases respectively, **4,150 case executions**
and 11,298 individual evaluations, with zero differences. They include 796
compile refusals, 4,547 evaluation refusals and 126 resolver calls. The fixed
edge families recur in both seeds, so case executions are not all unique inputs.
An initial probe mismatch exposed Foundation context-key normalization in the
test harness; exact-key JSON decoding removed that false difference. No
production source changed in this slice.

Receipts: `.build/reports/expression-stress-default.json` and
`.build/reports/expression-stress-second-seed.json`. These runs used local Swift
6.4 on arm64 macOS 27 and the pinned Corretto 21.0.11 JDK. They do not establish
Swift 6.2, Intel runtime, iOS 15 or macOS 12 runtime coverage.
