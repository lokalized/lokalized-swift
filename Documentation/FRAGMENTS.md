# Single-catalog fragment resolution

M4 implements an internal compiled catalog kernel, ordered message/fragment selection, generated language forms, recursive interpolation and safety limits. It uses exact caller keys, the expression evaluator and pinned plural/locale services already in the library. It has no external dependencies and reads no reference files at runtime.

M5 integrates this internal kernel into public `Strings`, including locale fallback, failure policies/handlers, result metadata, suppliers and bidi. Component comparisons retain their separate scope; [runtime qualification](IMPLEMENTATION-STATUS.md) reports whole-case parity.

## Component boundary

The package-only `CompiledCatalogResolution` takes an already parsed or defined `ParsedStringsFile`, its supplying `LocaleTag`, instance `TranslationRuntimeLimits` and optional `PhoneticResolver`. Its supplying tag must match the catalog's JDK tag. Typed locale fields are retained for application callbacks.

Construction compiles every whole-message and fragment predicate against the instance's limits, including unreachable predicates. Loading previously checked those predicates against the hard ceilings. Compiled nodes and whole-message predicates are memoized by immutable model storage identity; shared alternative DAGs remain shared rather than expanding into a tree. The model validator's alternative-depth limit applies before this compilation.

A synchronous `resolve(key, placeholders:)` makes one independent attempt and returns `missingTranslation`, `noMatchingAlternative` or a translation plus the selected declaration path. It never manufactures a locale match, falls back to another catalog, invokes a failure handler or claims a public `getResult` result. Mutable queues, scopes, cycle paths, selected templates, expanded values and budgets belong to that attempt, so the compiled configuration can be used concurrently.

An optional package `callerValueRenderer` receives the exact placeholder name, raw caller value and remaining UTF-16 output budget at substitution time. M5 uses `callerValueRendererFactory` to create a fresh renderer for each interpolated template, preserving reference per-name bidi caching within that template. No caller renderer is applied to generated translation text or missing/null caller values.

## Selection and scope

Whole-message alternatives are ordered first-match rules. Once a predicate matches, its subtree is terminal: an unmatched nested subtree does not resume later siblings or the parent's default. If no predicate matches, the current node's translation is used when present; otherwise the attempt returns `noMatchingAlternative`.

Generated definitions accumulate along the selected message path. A descendant replaces the nearest inherited definition by name, including changing between expression and language-form modes. Unmentioned definitions remain inherited. Each effective binding records the path where it was declared; failures distinguish that declaration from the selected message's path.

Expression fragments have a default template and ordered predicate/template alternatives. The first true predicate supplies the template, and later predicates are not evaluated. Failure while expanding that selection does not resume another alternative. An empty selected/default template is a successful value.

All predicates and selectors read the immutable raw caller dictionary. Generated names never overwrite that dictionary. A generated `count` fragment can replace `{{count}}` in output while a predicate or a selector named `count` continues to read the caller's original value. Absent keys and explicit `.null` remain missing values at use sites.

## Generated selection and expansion

Resolution is lazy by reachability. Referenced names are collected from the selected template in first-appearance order. Only names with effective generated definitions enter a breadth-first selection queue. Selected fragment templates enqueue further referenced generated names. Each generated name is selected once per attempt; two names sharing the same raw selector remain separate selections and can invoke an application resolver twice. Definitions in unselected branches or unreferenced fragments are not resolved.

The complete reached selection queue runs before recursive interpolation. A later selector failure can therefore precede a cycle in an earlier selected template. This order is observable through callbacks and errors and matches the reference implementations.

Expansion then walks generated templates with an active name stack and a per-attempt memo. Only re-entering an active name is a cycle; reuse after a completed expansion is valid. Expression and language-form fragments share the same cycle path and cache. Repeated references reuse expanded text without invoking selectors again or consuming another expansion charge. Raw caller text remains literal even if it contains `{{other}}`; it is not recursively interpolated.

All generated references in a template expand before that template's caller substitutions are rendered. The scanner subsequently renders each caller occurrence with its remaining budget. This retains the reference's custom display callback timing and error precedence.

## Language forms and application values

`PlaceholderValue` explicitly represents text, booleans, numeric widths/carriers, prebuilt `PluralOperands`, tagged `LanguageFormValue`, null and application `PlaceholderConvertible` values. Native numeric widths preserve observable type diagnostics. Strings that spell constants, such as `GENDER_MASCULINE`, remain text.

Cardinal and ordinal selectors accept their own explicitly tagged category, a numeric carrier or prebuilt operands. Explicit categories bypass numeric classification. Numbers build operands under the active instance limits. Prebuilt operands revalidate source scale/precision, compact exponent and explicitly visible decimal places against those limits before classification. Cardinal ranges independently validate and classify their start/end under the supplying locale, then use the pinned cardinal range table; missing selected range translations retain the endpoint categories in their diagnostic.

The seven nominal axes accept only a tagged form of the same axis. Phonetic selectors accept a tagged phonetic form or raw text. Raw text is bounded before invoking the application's `@Sendable` resolver, which receives the supplying `LocaleTag`. An omitted resolver uses the library's fail-fast resolver. Custom display values do not become numeric, nominal or phonetic operands; applications can pass formatted `.text` explicitly when needed.

`PlaceholderConvertible` receives an optional remaining character budget when rendering. The scanner still checks the returned string before appending it. The callback controls its own conversion work, while the library bounds the stored output.

## UTF-16 scanner and limits

The internal `StringInterpolator` recognizes `{{name}}` using UTF-16 code units and pinned Unicode identifier rules. Literal backslash escapes follow Java: a doubled backslash renders one backslash; a backslash before an opening placeholder keeps that entire token literal; a backslash before closing braces renders the braces. An escaped unclosed opening token remains literal. Combining marks adjacent to delimiters do not hide those delimiters, and NFC/NFD placeholder names remain distinct.

Strict scanning refuses unclosed openings, stray closings and malformed names. Missing values preserve the placeholder token in the scanner result and record unresolved names once in first-appearance order; the kernel then raises a missing-value failure. Lenient scanning retains malformed tokens and closings as literal text for the later failure-key path. Index diagnostics and character budgets count UTF-16 units. The scanner walks the input view without copying the complete source into a UTF-16 array; reference collection does not construct an unnecessary rendered copy.

| Limit | Scope and charging |
|---|---|
| Expression characters/tokens/grouping | Rechecked eagerly for every predicate at catalog compilation |
| Number scale/precision/visible places/compact exponent | Checked when the reached selector or expression consumes its raw value |
| Generated placeholder depth | Rechecked on entry to each recursive generated expansion; top-level depth is zero |
| Interpolated output characters | Bounds each expansion and the final message, including repeated insertions |
| Generated expansion characters | One cumulative budget per catalog attempt; charges each newly expanded generated value's UTF-16 length |

Nested child and parent expansions each consume their own output length. The top-level message does not consume the generated budget, so a zero cumulative budget permits a message without generated fragments and permits empty generated fragments. Output-limit refusal precedes a cumulative charge for the same expansion. A later catalog attempt will begin with fresh state and budgets in M5.

## Diagnostic provenance and causes

Raw parsing now retains authored placeholder-definition order as immutable package metadata in `LocalizedString`. Native dictionary construction chooses exact UTF-16 key order. Compilation and model revalidation use that retained order, so a parsed `z` definition before `a` remains the first construction refusal when both exceed lowered instance limits. This metadata does not change public model equality or hashing. Shard merge retains the first equal definition and its order while unioning origins.

`TranslationEvaluationError` distinguishes expression, invalid-argument and invalid-state categories. Generated-fragment predicate failures add an expression-selection wrapper, and generated-placeholder failures add the name, definition kind, declaring path and selected template/category when available. Immediate causes are retained. Recognized numeric conversion failures retain their native cause inside an invalid-argument wrapper; rounding and unsupported-locale errors retain their reference exception category. An arbitrary application resolver/display error propagates unchanged, preserving a custom class error's identity.

## Qualification

```sh
swift test
swift run LokalizedConformance --self-test
swift run LokalizedConformance --resolution-components --reference Reference
```

The component audit replays 578 input-driven frozen donor attempts and compares component outcome/text, categorized error message and immediate cause, and resolver calls. It does not mark any whole-runtime case as passed: match diagnostics, fallback policy, handlers, result metadata/identity, successful fallback observations and bidi policy remain unexamined in this projection. The report enumerates the exact eligible IDs and their digest; omissions or mismatches fail the component gate.

Native standalone and XCTest checks add Unicode delimiter/key distinctions, escaping, terminal selections, inherited/replaced scopes, raw selectors, breadth-first error priority, mixed cycles, memoized and nested budget charging, supplying locale, callback identity/timing, all ten form axes, active operand limits, authored compile order, shared DAGs and concurrent attempt isolation. The M5 main audit independently compares full runtime observations. Loading and native representation qualification keep the shared audit incomplete.
