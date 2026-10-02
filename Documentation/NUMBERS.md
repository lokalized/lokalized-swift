# Exact numbers and plural operands

M2 uses an in-repository decimal engine and pinned CLDR rules. Consumer builds require neither an arbitrary-precision package nor host locale or number-formatting data. `Foundation.Decimal` does not participate in numeric evaluation.

```swift
let integer = NumericValue.integer(1)
let decimal = try NumericValue.forDecimal("1.00")
let integerForm = try Cardinality.forNumber(integer, locale: "en") // .one
let decimalForm = try Cardinality.forNumber(decimal, locale: "en") // .other

let compact = try PluralOperands(.forDecimal("1.2"), compactExponent: 6)
assert(compact.n.plainString == "1200000")
assert(compact.sourceNumber.plainString == "1.2")
```

`ExactDecimal` holds signed decimal digits and a scale. Written trailing zeros survive construction, equality, hashing and rendering: `1`, `1.0` and `1.00` are distinct representations. `compare(to:)` compares their numeric values equally. `description` uses Java BigDecimal's canonical notation; `plainString` omits the exponent. Exact remainder supports the positive integral divisors needed by CLDR without coercing either operand through binary floating point. It preserves a nonnegative dividend scale and expands a negative scale to zero first, following JS's helper convention; Java BigDecimal may retain a negative scale in a zero remainder. CLDR's expanded operands already have nonnegative scale.

`NumericValue` distinguishes signed and unsigned integers, arbitrary integer text, exact decimals, binary32 `Float` and binary64 `Double`. Initializers accept native integer, Float, Double and ExactDecimal values. `forDecimal` and `forBigInteger` validate text immediately. The raw `.bigInteger(String)` carrier is validated when consumed numerically. Native integers and binary floats normalize insignificant trailing zeros before numeric admission; exact decimal text preserves its scale. Float is never widened to Double to derive its decimal spelling.

The original [floating-point converter](FLOATING-POINT.md) selects and renders decimals according to the pinned Java 21 contract using exact integer arithmetic. Numeric consumption rejects NaN and infinities; source rendering retains `NaN`, `Infinity` and `-Infinity`, as well as signed zero. Locale-aware date, currency and display formatting belongs to callers.

`PluralOperands` derives `n`, `i`, `v`, `w`, `f`, `t`, `c` and `e` after expanding an optional compact exponent. The absolute expanded number drives plural rules; `sourceNumber` retains the signed unexpanded mantissa for later expression comparisons and interpolation. Explicit visible decimal places add or remove zero digits exactly; removing a nonzero digit throws `NumericError` with `.roundingNecessary`. Operand equality includes exact `n`, source sign and compact exponent, matching Java's representation contract.

Admission checks compact exponent, visible places, numeric conversion, absolute scale and precision in that order. Defaults are precision 1,024, absolute scale 1,024, visible places 1,024 and compact exponent 64. Each has a hard ceiling of 4,096. Derived materialization is separately bounded at 12,288 digits before padding or compact expansion. Raised construction budgets do not exempt operands from later instance-level admission in the forthcoming translation runtime.

`Cardinality` provides `forNumber`, `forOperands`, `forRange`, `supportedCardinalitiesForLocale`, integer/decimal example helpers and `getSupportedLocaleTags`. `Ordinality` provides number/operand classification, supported categories/locales and integer examples. Every data set ships in the library. `Lokalized.Range<Value>` holds ordered sample values and their `isInfinite` flag; qualify the module name when Swift's interval `Range` would otherwise be ambiguous. An infinite sample range still stores a finite illustrative list.

Full rule, range, support and example qualification and generated-data provenance are documented in [PLURAL-DATA.md](PLURAL-DATA.md). Classifiers and catalog warnings share the complete pinned [locale kernel](LOCALE-DATA.md), including JDK projection and CLDR aliases.

The development-only `Tools/verify_numeric.py` independently generates deterministic decimal inputs, compiles the actual library for macOS 12, and compares its public APIs to the pinned Corretto 21 BigDecimal oracle. Its 632-case local run passed 535 accepted inputs and 97 rounding refusals with zero differences, applying the declared negative-scale remainder normalization to both observations. The report pins every library source, oracle/harness/input/output and binary, checks the JDK identity, and refuses mid-run source changes. Run it with an explicit existing JDK; none is downloaded:

```sh
python3 Tools/verify_numeric.py \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home \
  --report /tmp/lokalized-numeric-report.json
```

This oracle uses only standard-library Python, the system Swift compiler and Java as development tools. The local evidence is `/private/tmp/lokalized-numeric-verification-report.json`; normal consumer builds and native checks require no JDK or sibling repository.
