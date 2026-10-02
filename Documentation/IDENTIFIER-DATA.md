# Pinned identifier categories and expression compilation

Swift identifiers use the reviewed oracle's **Unicode 15.0** policy:
`[\p{L}_][\p{L}\p{N}\p{M}_-]*`. Matching operates on Unicode scalars; string
identity remains exact UTF-16. Swift/Foundation character categories and regular
expression engines do not decide acceptance, so OS upgrades cannot change it.
Current JS host Unicode 17 accepts additional identifiers; that existing cross-port
difference requires a shared versioned policy, not a silent Swift expansion.

`Sources/Lokalized/Data/IdentifierTables.swift` contains 1,088 ordered ranges in
a 14,144-byte compiled ASCII `StaticString`. Each range has six hexadecimal start
digits, six inclusive-end digits and one flags digit. Binary search decodes only
the tested ranges. No runtime dependency, resource bundle, object graph or build
generator is required. Underscore and the continuation-only hyphen are explicit
rules outside the Unicode category data.

The projection contains 136,104 letter scalars, 1,831 number scalars and 2,450 mark
scalars. Number categories include `Nl` and `No`, which `isLetterOrDigit` would
miss. Surrogates are excluded. Range payload SHA-256 is
`d1c5f7947c2b761f6f9a7ca5b7ac3d9a0de473b3103698974053461a624a253c`;
generated Swift SHA-256 is
`43314a037611c1b5fb7f5b10abbdfa5cd06bb690ebbf25188ba4deb249e76bd8`.

## Reproduction and provenance

Ordinary verification requires Python's standard library and checked-in files:

```sh
python3 Tools/generate_identifier_tables.py --check
```

Explicit regeneration requires the pinned local JDK:

```sh
python3 Tools/generate_identifier_tables.py --generate \
  --java-home /path/to/amazon-corretto-21.jdk/Contents/Home
```

The generator verifies the JDK `release` SHA-256
`31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239`
and runtime vendor/version before sweeping every valid scalar with Java
`Pattern` categories `L`, `N`, `M`. It independently checks each answer against
`Character.getType` category sets 1–5, 9–11, and 6–8. The pinned runtime is Amazon
Corretto 21.0.11, build `Corretto-21.0.11.10.1`; its Character source documents
Unicode 15.0. Generated range SHA/count pins prevent this command from accepting
an arbitrary newer policy. Neither mode fetches anything from the network.

`Reference/identifier-data.json` is an additional development sidecar with oracle,
projection source hash, counts and encoded ranges. It is intentionally separate
from the immutable 21-artifact M0 `Reference/baseline.json` archive. The checker
rejects duplicate JSON members, unknown/modified manifest values, invalid range
width/order/flags, overlaps, surrogate ranges, noncanonical encodings, changed
category inventories, changed pins and stale generated Swift.

`Reference/identifier-notices.json` preserves the pinned runtime's complete
`legal/java.base/unicode.md` notice verbatim, including its Unicode 15.0.0 data
license. Original notice SHA-256 is
`6f72f10d166b2c2e8a395e03e734c5afc852b59aeca73ced124f6b9c96268d53`.
Preserve this corresponding notice in release documentation when distributing
the derived tables; the existing CLDR Unicode 3.0 notice is a separate artifact.
The generator queries runtime behavior and copies no JDK implementation source or
bytecode into the Swift library.

## Load-time expression validation

The package-only `ExpressionCompiler.validate(_:limits:)` defaults to hard
ceilings: 4,096 UTF-16 source units, 512 tokens, 64 groups, 4,096 decimal precision
and absolute scale. Caller-supplied instance limits are honored explicitly.
Compilation retains a genuine validated postfix representation and exact signed
decimal coefficient/scale; expression evaluation remains later implementation work.

Validation follows Java's ordering: source length, full lexical scan, all numeric
literals, token/depth ceilings, shunting-yard conversion, then static operand
validation. Comparisons bind more tightly than `&&`, which binds more tightly than
`||`; all operators associate left. All 61 form tokens use exact whole-identifier
recovery after greedy scanning. `true` and `false` are ordinary variable names.
Invalid expressions throw `ExpressionCompilationError` with a typed reason and
the exact portable evaluator message; the catalog loader adds contextual loading
diagnostics.

Six XCTest tests passed on current Swift 6.4 in Swift 6 package mode: every packed
range boundary/gap, Unicode 15/newer boundaries, all 61 form constants and suffix
recovery, actual precedence/numeric IR, limit/error ordering, and exact diagnostic
suffixes for **all 31** frozen parse-expression rejection cases. These tests check
implemented behavior against corpus observations; production code reads no expected
observations and implements no evaluation shortcut. Minimum Swift 6.2 execution
and broader OS/runtime qualification remain separate gates.
