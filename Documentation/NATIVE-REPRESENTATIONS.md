# Native type representation evidence

M8A qualifies all twenty pending runtime inputs whose null shapes cannot inhabit the public Swift types. This is evidence for a native API disposition, not replay of Java's null diagnostics. The main corpus remains at 2,197 runtime passes, zero native mappings and 184 pending cases. The runtime adapter remains at 1,432 complete comparisons and twenty pending configurations.

`Tools/verify_callback_types.py` compiles the current library into an isolated temporary module and dynamic library, checks a valid external consumer, then requires seventeen invalid consumers to fail specifically for their intended nil/type mismatch. The compiler's diagnostic must identify both nil incompatibility and the relevant public type; an unrelated compilation failure does not count. The nine added consumers cover catalog values/keys/elements/entry labels, tiebreaker lists/elements/language keys, and placeholder names. The original eight consumers are retained. Positive examples preserve valid optional settings, explicit `.null` placeholder values and ordinary nonoptional collections.

The same tool compiles and executes [a public runtime consumer](../Tools/Fixtures/NativeTypeControls.swift) with no XCTest or reference fixtures. Its 23 individually identified checks exercise successful-key handler nonconsultation, single-candidate policy nonconsultation, complete-walk handler order, policy-before-handler refusal through both `get` and `getResult`, current versus first-retained resolution causes, identity-preserving rethrow, expression resolver errors, the valid `.other` category, explicit missing-map errors, explicit null/missing binding refusal, optional supplier inheritance, optional whole-tiebreaker configuration and raw JSON null rejection. These representable controls preserve runtime obligations that negative compilation alone cannot establish. They do not recreate a callback returning nil.

| Unavailable input | Pending cases | Required negative consumer evidence |
|---|---:|---|
| Callback configured to return null | 11 | Handler response, policy Bool or phonetic category, according to each input guard; the two nonconsultation controls remain accounted for |
| Null catalog supplier/value/entry/locale key | 4 | Each exact collection boundary; null entries cover both root-array and labeled-entry forms |
| Null tiebreaker list/entry/language code | 3 | Each exact nested collection boundary |
| Null placeholder name | 1 | Nonoptional `ExactString` key |
| Actual unmapped phonetic consultation | 1 | Nonoptional resolver return, with actual consultation evidence and an adjacent explicit-throw control |

`Tools/verify_native_representations.py` links every pending ID to its authored input/fixture fingerprint, actual runtime guard, corresponding negative consumer, adjacent runtime checks and the original observation channels that were not replayed. It retains a fingerprint of each original observation as an obligation; those observations never configure native execution. The complete twenty-ID digest remains `e19eacaf8f0773df2bdb0ca83e38a025fa8b964f20f2dfc188ec05e5fd83dd79` (sorted IDs, each followed by LF).

The checker verifies the frozen reference baseline and independent runtime-adapter ratchet, checks guard claims against authored input, verifies every compiler consumer and runtime check, and requires a complete current-library source snapshot. Changed source files, consumer inputs, diagnostic reasons, execution outcomes, omitted checks or altered per-case receipts are refused. Source inputs are rechecked after the compiler/execution run. Twenty-three negative controls exercise missing/duplicate cases, fabricated passes/ratification, missing original channels, changed input/observation fingerprints, mismatched guards, wrong evidence consumers and stale/altered compiler receipts.

Run the development qualification from the repository root:

```sh
python3 Tools/verify_callback_types.py --report .build/reports/callback-types.json
swift run --skip-build LokalizedConformance --runtime-adapter --reference Reference --report .build/reports/runtime-adapter.json
python3 Tools/verify_native_representations.py --type-report .build/reports/callback-types.json --runtime-adapter-report .build/reports/runtime-adapter.json --report .build/reports/native-representations.json
python3 Tools/verify_native_representations.py --type-report .build/reports/callback-types.json --runtime-adapter-report .build/reports/runtime-adapter.json --report-check .build/reports/native-representations.json --negative-controls
```

Build the conformance executable before `--skip-build`. Normal checking needs Python's standard library, frozen local artifacts and saved reports; compiler qualification additionally needs the Apple Swift SDK. No Java, Node, sibling checkout, network or consumer package dependency is involved. CI runs the qualification under both configured compiler tracks.

The report status is `evidence-ready-unratified`, with empty `runtimePassedAdded` and `nativeRepresentationMapped` arrays and `nativeMappingsRatified: false`. It does not ratify a shared representation mapping or account for JVM carriers and filename-order differences. All original observation channels remain unreplayed for the twenty impossible inputs. Host execution is distinct from runtime support at macOS 12/iOS 15, Intel execution and minimum Swift 6.2 compiler coverage; those existing release gates remain explicit.

Local M8A evidence on Swift 6.4 / Xcode 27 / arm64 macOS 27.0.1 is `.build/reports/m8a-callback-types.json`, `m8a-runtime-adapter.json`, `m8a-native-representations.json` and `m8a-native-representation-controls.json`. All seventeen refusals, the valid consumer, 23 runtime controls and 23 report controls pass. This slice changes qualification tooling and documentation; it adds no runtime API or networking.
