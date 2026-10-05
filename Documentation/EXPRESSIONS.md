# Expression compilation and evaluation

M4 implements the package-only expression evaluator used by compiled catalog resolution. Like Java's evaluator, it is an internal service rather than a public standalone expression API. Public `Strings` construction and translation methods remain M5 work. The implemented evaluator uses pinned identifier data, exact decimal arithmetic and the library's plural and locale services, with no package dependencies or runtime reference-file reads.

## Grammar and eager compilation

Expressions combine comparisons with `&&`, `||` and parentheses. Comparison operators are `==`, `!=`, `<`, `<=`, `>` and `>=`. Comparisons bind more tightly than `&&`, which binds more tightly than `||`. Parentheses change that order. There are no arithmetic operators, quoted string literals, boolean literals or textual equality operators.

Operands are numeric literals, placeholder identifiers or one of the 61 `LanguageFormValue` constant tokens across the ten supported axes. Numbers accept an optional ASCII sign, a decimal point and a signed decimal exponent. Literal precision and scale are retained, so `1` and `1.0` compare numerically equal but can produce different plural categories. Identifiers use the pinned Unicode letter/number/mark rules described in [IDENTIFIER-DATA.md](IDENTIFIER-DATA.md); a hyphen is permitted after the first character. Only space, tab, carriage return, line feed and form feed are expression whitespace. Error positions and length limits count UTF-16 code units.

The loader validates expressions against hard ceilings. Construction of a compiled catalog recompiles every message and fragment predicate against that instance's `TranslationRuntimeLimits`, including predicates in unreachable branches. Compilation checks source length, lexes the complete source, validates every numeric literal, checks token count and grouping depth, converts the expression to postfix form, and validates its static types in that order. A later lexical failure can therefore precede an earlier invalid numeric literal. Numeric literals become exact decimals during compilation and are not parsed again during evaluation.

The compiled representation is an immutable, `Sendable` flat node array. Compilation, boolean evaluation and representation destruction do not recurse through an expression tree. Grouping depth and token limits are distinct: a long flat boolean expression need not consume grouping depth. Invalid configuration values throw rather than clamp.

## Values, comparison and short circuit

Each evaluation reads an immutable `[ExactString: PlaceholderValue]` caller dictionary. Lookup preserves exact UTF-16 identity; NFC and NFD spellings can identify different placeholders. Generated fragment bindings do not replace caller values in predicates. A reached absent key and an explicit `.null` have different diagnostics.

`&&` and `||` evaluate left to right and short circuit before looking up a skipped branch's variables. Skipped branches cannot validate numbers, classify forms, invoke phonetic callbacks or fail for missing values. Within a reached comparison, both operand types are discovered before dispatch, preserving the reference implementation's failure order.

| Operand family | Supported comparison |
|---|---|
| Numeric carriers and prebuilt `PluralOperands` | All six comparison operators, using exact signed decimal values |
| Gender, grammatical case, definiteness, classifier, formality, clusivity and animacy | `==` and `!=` between forms of the same axis |
| Cardinality and ordinality | `==` and `!=`; numeric operands are classified under the supplying catalog's locale |
| Phonetic forms and raw text | `==` and `!=`; text opposite an explicit phonetic form invokes the resolver |

All numeric widths exposed by `PlaceholderValue` are supported. `.byte`, `.short`, `.integer` and `.number` retain the reference's observable boxed-type diagnostics; binary32 and binary64 numbers retain distinct pinned decimal conversions. There is no conversion through Foundation's finite-precision `Decimal`.

Ordinary comparison of prebuilt `PluralOperands` uses its signed source number. Plural classification uses its absolute expanded number and retained metadata, including explicitly visible decimal places and compact exponent. Consuming prebuilt operands revalidates the source scale and precision, then compact exponent, then explicitly visible places against active limits. Classification uses the supplying catalog's locale rather than a later requested locale. Explicitly tagged cardinal and ordinal forms bypass numeric classification.

Raw `.text` remains text even when it spells a number or a language-form constant. Text is phonetic input, never a nominal form or numeric coercion. Comparing two raw texts rejects textual equality or ordering before invoking a resolver. Comparing raw text with a number gives the numeric-operand diagnostic. A `.boolean` or `.custom` value is unsupported in expression comparisons; the evaluator does not invoke `PlaceholderConvertible.lokalizedDescription` to discover or convert its value. Applications should pass the intended typed carrier explicitly.

## Phonetic resolver behavior

The public native callback type is:

```swift
public typealias PhoneticResolver = @Sendable (String, LocaleTag) throws -> Phonetic
```

The callback receives the original text and the supplying catalog's typed `LocaleTag`, retaining its JDK identity. The return type is a nonoptional tagged phonetic form; Java's nullable callback shape has no native Swift equivalent. An explicit phonetic value needs no callback. Every reached text comparison invokes the resolver at that site; there is no global callback-result memo. Short-circuited sites never invoke it.

Input length is checked in UTF-16 units against `maximumInterpolatedOutputCharacters` before invocation. An omitted resolver uses the library's fail-fast resolver and raises an invalid-state error when raw phonetic input is reached. Resolver code may throw, reenter the library or run concurrently; evaluation stores no mutable per-call state on the compiled expression. As with other application callbacks, the callback controls its own internal work.

## Native errors and retained causes

The public native error is `TranslationEvaluationError`, a final class with `kind`, `message` and optional `cause`. Its `.expression`, `.invalidArgument` and `.invalidState` kinds preserve the Java exception categories without exposing Java exception class names as Swift types. A contextual resolution wrapper retains the immediate recognized error as its cause; class error identity is preserved at that boundary.

Lexical, length, token, nesting and grouping failures are expression leaves without an invented cause. Static type failures retain an inner expression leaf beneath the `Invalid expression ...` wrapper. Invalid numeric literals and reached numeric extraction failures retain a typed `NumericError` cause. Phonetic input-budget failures retain an invalid-argument cause beneath their expression error. Missing/null operands, incompatible axes and forbidden comparison operators are expression errors. A default fail-fast resolver produces an invalid-state error.

Recognized expression, numeric argument and library state errors receive the catalog's relevant expression/placeholder context. `NumericError.roundingNecessary` retains its arithmetic category. `UnsupportedLocaleError` and arbitrary application errors propagate unchanged rather than acquiring an expression category. An application-thrown class error retains the exact object reference. A typed `TranslationEvaluationError` thrown by a resolver is unchanged until an owning resolution boundary adds its contextual wrapper and immediate cause.

## Qualification and current boundary

`ExpressionEvaluationTests` has 15 native test methods. The standalone `ExpressionQualification.run()` contributes 211 checks to the conformance runner's self-test, without XCTest, corpus fixtures or expected-driven execution. Checks cover all 61 forms and ten axes, exact large decimals and typed numeric widths, precedence, genuine short circuit, reusable compiled state, source versus expanded operands, lowered-limit refusal priority, raw-text rejection, UTF-16 input limits, callback timing/identity, Unicode key distinctions, eager compilation causes and the maximum flat token shape.

The development-only [expression stress differential](EXPRESSION-STRESS.md)
separately compares generated compile and evaluation cases with freshly compiled,
frozen Java sources. Its two recorded seeds pass 4,150 cases and 11,298 evaluations.

```sh
swift test
swift run LokalizedConformance --self-test
swift run LokalizedConformance --resolution-components --reference Reference
```

The component audit compares input-driven single-catalog resolution projections, including predicate effects and callback/error observations. It does not establish whole-runtime parity for locale fallback, failure handlers, public result metadata or bidi policy. The main M5 audit now verifies those observations separately; see [FRAGMENTS.md](FRAGMENTS.md).
