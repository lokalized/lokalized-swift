# Pinned manifest contract observations

M7A covers manifest validation, catalog identity, and load planning. It does not perform network or filesystem catalog loading, produce verified `LoadedStrings`, exercise cancellation, publish a manifest, or claim manifest authentication. The original 2,381-case behavioral corpus and M0 reference baseline are unchanged. That corpus's `manifest-loads` cases concern Java directory loading and subsequent translation; it contains no JSON-manifest, JCS-identity, or fetch-plan operation.

`Reference/manifest-contract-vectors.json` is a separate development-only archive of 499 observations from JavaScript commit `617670da887b0c684e2589882447b6b93297f2f7`. Its package.json still says `1.0.0-rc.2`, but the commit includes unreleased API and wire changes. `Reference/manifest-contract-lock.json` pins the exact production source bytes, reviewed tests and declarations, generator, schema, Node version, case inventory, and archived output. Refresh reads immutable git objects, rather than mutable checkout contents, before importing and executing the real JavaScript functions. No expected Swift output participates in generating these observations.

The archive has 152 object validations, 183 raw parses, 41 standalone identity calls, 16 identity projections from manifest claims, 12 locale-configuration calls, 35 candidate chains, 47 fetch sets, and 13 whole-manifest plans. The last operation records an exported internal JS helper, separately from the public JS package entry points. There are 167 returned observations and 332 thrown observations. These are reference outcomes, not a claim that every input can be expressed by the native API or that Swift has passed them.

## Reproduce or check

Normal checking needs Python's standard library only, without Node, Java, git, sibling repositories, or network access:

```sh
python3 Tools/manifest_contract.py --check
```

An explicit development refresh requires the pinned git objects and the recorded Node `v26.5.0` oracle environment:

```sh
python3 Tools/manifest_contract.py --refresh --source-root /path/to/lokalized-js --node /path/to/node
```

Node is an oracle tool, not a consumer or build dependency. The version records the environment actually executed; it does not change Lokalized Swift's runtime or OS floor, or assert qualification of every JS-supported Node version. A refresh reports new archive digests; changing those pins is a deliberate source change. The inputs can be inspected independently with `--inputs`.

`--check` validates the frozen whole-file digests, recomputes the entire explicit input recipe and ID inventory, and checks each successful identity with an independent bounded JCS encoder and Python SHA-256. That encoder accepts only the strings, safe integers, booleans, arrays and exact-name objects needed by these identity projections. It sorts object property names by UTF-16 code units, preserves array order and Unicode spelling, rejects lone surrogates, and verifies the exact UTF-8 bytes with no BOM or trailing newline. It is not advertised as a general floating-point JCS implementation.

## Input and observation format

Each row contains `id`, `operation`, `input`, and `expected`. `input.manifestJSON` or `input.identityInputJSON` is an ordered JSON **string**, so malformed semantic field types and declared object-member order survive the outer archive's serialization. The object door uses real `JSON.parse` object semantics: duplicates have already collapsed, and source positions cannot be recovered. The raw door instead records `carrier: "bytes"` with `documentBase64`, or `carrier: "text"` with `text`; malformed UTF-8, duplicate members and raw syntax remain actual inputs. `optionsJSON` is optional, and planning records the raw `lookupLocale` supplied to the JS API.

Returned observations contain the complete actual return value. Thrown observations contain the actual name, message and every library code/source/line/column/path field present, plus immediate Error causes recursively up to a bounded depth. Host stack traces are not contract fields. Identity returns additionally include the actual projected object, `canonicalBytesBase64`, `byteCount`, and `sha256`. A separate Node crypto SHA-256 calculation checks the library digest before the observation is accepted.

Inputs distinguish validation priority, declaration order, required fields and all seven build-identity values, URL schemes/resolution, decoded-byte safe-integer bounds, file limits, fallback election, full-manifest tiebreaker permutations, and raw parse budgets. Identity probes discriminate included and excluded fields, array order, prototype-like ordinary keys, exact NFC/NFD keys, UTF-16 property order, minimal string escapes, and malformed strings. Planning probes include Norwegian bridges, script boundaries, fallback-equivalent election, exact variant-case-distinct manifest tags, private/undetermined tags, and JDK `lvariant` input. Every file has a distinct deterministic SHA-256 so a wrong-entry digest projection is observable.

Native qualification must select eligibility from these inputs and the actual public API. The decoded native semantic-value door can express malformed JSON field shapes; the typed identity input cannot express null or incorrectly typed required strings or array members. Neither `String` nor public `ExactString` can preserve lone UTF-16 surrogates. Such cases must remain explicit carrier-pending rather than manufacture JS runtime errors from native type safety. Unknown input/observation fields must fail closed. Native error taxonomy or additional structured diagnostics need explicit comparison rules and retained observations; fields may not disappear merely because a reference expectation lacks them.

## Native qualification and report integrity

The actual M7A public-door run matches 468 of the 499 observations, with no failures. Of these, 165 have identical native/reference observations and 303 match through explicitly registered representation projections. The remaining 31 are pending native carriers. This scoped result does not promote any of the original 2,381 behavioral cases or ratify cross-platform API mappings.

The 31 pending inputs comprise nine missing or incorrectly typed required identity fields, five unknown dynamic option members, four incorrectly typed tiebreaker arrays/elements, four lone-surrogate keys/values, three nonobject identity roots, two unknown budget names, two null lookup strings, one nonstring digest value, and one extra dynamic identity member. Eligibility derives from input types and actual native argument labels, before the expected outcome is inspected. Missing/null optional identity maps are successfully exercised as empty maps; they are not excluded merely because another identity input needs a typed-carrier decision.

The error projections preserve complete native and reference observations in the report. `ConfigurationError.kind` and its nil cause project to JS's configuration `code`, or to the independently selected identity TypeError/RangeError class. Native loading-option validation and malformed planning lookup errors have separately named taxonomy projections. Native `StringsParseError` source/line/column/path/cause remain in its receipt; JS's `STRINGS_PARSE` code and raw-reader cause envelope are represented in the comparison receipt. Unlocated raw source failures project to the JS generic Error envelope, while retaining the native structured source and any strict-UTF-8 cause. The same message, source positions and semantic refusal must still match. A projection never absorbs an unexpected difference.

The frozen corpus contains no consulted Unicode or punycode host capability refusal. The adapter nevertheless qualifies that boundary with separate native tests: when the actual validator reaches the unqualified UTS46/IDNA profile, it retains `ManifestURL.Failure` kind/feature/cause as a pending capability. An earlier actual manifest refusal remains observed even if a later URL would require that profile. It does not classify a consulted capability refusal as an ordinary JS malformed-URL match.

Run the real library and check the separate report with:

```sh
swift run LokalizedConformance --manifest-contract --reference Reference --report .build/reports/m7a-manifest-contract.json
python3 Tools/verify_manifest_contract_report.py .build/reports/m7a-manifest-contract.json
python3 Tools/verify_manifest_contract_report.py .build/reports/m7a-manifest-contract.json --self-test --integrity-report .build/reports/m7a-manifest-report-integrity.json
```

The stdlib-only report checker verifies whole-file source/vector locks, derives the exact eligible/pending ID inventories from the inputs, and derives each comparison from actual native fields using the registered rules. It checks every reference observation against the immutable JS oracle, independently verifies returned JCS bytes/hash, and refuses missing native, adaptation or pending receipts. Its separate native-ledger SHA-256 pin includes every observed field, including cause reason/offset fields outside the JS envelope; this reviewable qualification pin prevents silently changing such fields. It is not used by the library or to supply expected runtime answers. Fifteen tamper controls reject altered results, missing receipts, omitted rules, an altered unprojected cause reason, forged mapping ratification, and modified frozen reference bytes.

| Inventory | Cases | SHA-256 of sorted IDs, each followed by LF |
| --- | ---: | --- |
| All | 499 | `cd23a022f9bd427824c451892ab0e922fb8809945a0eb55571d9d4eccec7966f` |
| Eligible/matched | 468 | `f8062a5ef05939d4100f68b1a1c64ab351632992a56719154831e5c1babb69c1` |
| Strict native equal | 165 | `d76f309201418fdda3c0e7b157ed135576d1a1fb9309c0dc70136dea3bb5bb0f` |
| Projected matched | 303 | `35ce8481225f5fde66ec8f966523eda98d7425f18120200deb562c10f897342c` |
| Pending carrier | 31 | `c6157779eb161a1e0193b8abc246bc80112e3ba67e27d0f296d3722006f481f4` |

The native observation ledger pin is `54aa67d6962a9bf1b3f123ebbd6205004c3ce0d272f36270608656fd3957f548`, computed from each ID plus the independently normalized full native observation, in sorted ID order. The archive's vector pin is `6356098bbde353a66886e9552c45efe7ec6353697cf26be2141d3e9f4811d50a`; its lock pin is `faaa51bdacd19f1fbd407848ac545221aad4da5d6d02a1095f1d927a2a96bf03`.

The paired `UND-x-foo`/`und-x-foo` inputs deliberately preserve the pinned JS helper's non-idempotent normalization and repeated projection. M7A has not repaired that shared contract while porting it. A future shared amendment should resolve the behavior and regenerate all affected contract evidence together.

## Wire-name migration evidence

The current identity projection contains the member `tiebreakerLocalesByLanguageCode`. Predecessor commit `cb3a61c14ecd9086e11f226f6063a13665d43a8c` contained `tiebreakers`, while both source commits declared manifest format version 1 and package version `1.0.0-rc.2`. The lock includes a paired identity example measured by executing each commit's own code:

- Current canonical bytes hash to `8cd3a85ba9555c1f1e91fcebe97737b770a4f6e5ecdf867f1aea0a9e60805cd7`.
- Predecessor canonical bytes hash to `602f3d009f1f1719aa2b7e3bf6dba38bb95f9674d08fd6fad61e27913ed1aeaa`.

Only the projection's member spelling changes in that example. HEAD's README says old names are not aliases and requires regenerating manifests and SSR stamps because the rename changes catalog fingerprints. The paired example is explicitly **predecessor source evidence**, not attestation of the contents of a downloaded npm tarball. The implementation plan separately records the published rc.2 wire shape. Swift M7A targets this reviewed HEAD contract; compatibility with both version-1 wire artifacts requires a shared migration/version decision before a broader compatibility claim.

No Java/JS production implementation is vendored in this development archive. Corresponding JS license, notice and third-party notice files are copied verbatim beside the references and checksum-pinned. Their upstream paths remain meaningful in the original repository; they do not introduce runtime dependencies.
