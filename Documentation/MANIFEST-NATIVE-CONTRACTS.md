# Shared manifest native qualification

M8I consumes `lokalized-spec`'s `swift-native-manifest-v1` profile, version 1.0.0.
The original 499-case archive, input recipe, Node oracle, source/declaration/notice
provenance, raw comparison checker and new native policy are now shared artifacts.
Fourteen byte-pinned copies support independent offline development checks:

```sh
python3 Tools/sync_manifest_contracts.py --check
python3 Tools/manifest_contract.py --check
python3 Tools/test_manifest_native_contracts.py
```

Use `--check-source --source ../lokalized-spec` to compare the canonical checkout.
An explicit `--sync` verifies every canonical source before writing any local
copy. Oracle refresh now belongs to `lokalized-spec`; the Swift wrapper refuses
`--refresh`. Fixtures and Python/Node tools are development-only and never enter
the production target or consumer dependency graph.

## Evidence and accounting

The original shared profile covers **499 distinct obligations** as 468 executed runtime
comparisons and 31 native adaptations. Of the runtime comparisons, 165 observations
are exactly equal and 303 use named narrow error representations. Native and
reference errors remain whole in the receipt; messages/positions/identity bytes
and unexpected fields remain checked. The historical native ledger digest remains
`54aa67d6962a9bf1b3f123ebbd6205004c3ce0d272f36270608656fd3957f548`.

Thirty input-derived external consumers are refused for their exact type,
argument or Unicode-scalar reason. One compiles: the identity initializer defaults
omitted `formatVersion` to `1`, while JS refuses the missing object member. A
runtime control requires exact identity bytes/digest equality with explicit `1`.
This accepted native default is documented separately from source rejection.

Four of the invalid consumers contain lone UTF-16 surrogate keys/values. Runtime
controls observe the repairing Swift UTF-16 initializer and public `ExactString`;
repair is not passed off as the original JS input. Raw manifest parsing refuses
unpaired escapes, while real U+FFFD and supplementary identity text remain valid.
The remaining controls preserve runtime refusals for expressible null manifests,
malformed digests, empty lookup text and exceeded file limits, and successful
options/chain/fetch-set behavior. All sixteen named controls execute externally
against an isolated current-source library.

```sh
python3 Tools/verify_manifest_types.py --report .build/reports/manifest-types.json
python3 Tools/verify_deployment.py --report .build/reports/deployment.json
python3 Tools/verify_manifest_native_contracts.py \
  --type-report .build/reports/manifest-types.json \
  --runtime-report .build/reports/manifest-contract.json \
  --deployment-report .build/reports/deployment.json \
  --report .build/reports/manifest-native-contracts.json
```

The runtime report comes from `LokalizedConformance --manifest-contract` as in CI.
Qualification validates every current production/support source hash, the actual
host manifest observation and execution log, all eight source-module compilation
logs and sixteen inspected binaries across four SDK targets. It refuses stale
shared verifier inputs, missing consumers/controls, unrelated compiler errors,
failed executions and invented runtime/release claims. Saved report checks and
negative controls need no compiler or sibling repositories.

Local M8I evidence is `.build/reports/m8i-manifest-native-contracts.json`, with
23 new corrupted-receipt controls rejected. All fifteen existing raw-manifest
corruption controls, seven shared Python tests and five Swift-development Python
tests also pass. The original archive/lock/raw report bytes and all 127 Swift
source files are unchanged. Current Swift 6.4 / SDK 27 / arm64 macOS host execution
and four-target compilation do not establish Swift 6.2, iOS/Intel or minimum-OS
runtime coverage. Hosted CI has not run these changes yet.

The historical raw report remains 468 runtime/31 pending and unratified. The separate native
receipt reports `covered-under-native-contracts-not-certified`, zero added runtime
passes and `releaseParity: false`. M8J closes the diagnostic boundary under [diagnostic profile 1.1.0](DIAGNOSTIC-TEXT.md).
M8K composes this native carrier policy with [manifest normalization profile
1.1.0](MANIFEST-NORMALIZATION.md). Current source-bound coverage records 464
unchanged historical runtime agreements, four explicit amendments, 162 exact
and 306 projected active observations, and the same 31 native adaptations. It
retains the original profile/archive pins and every original reference channel.
The active raw checker refuses 18 corruption controls; native coverage still
refuses all 23 controls and reports zero added runtime passes. The full old
native ledger remains historical evidence alongside a separately pinned amended
ledger. Current M8K deployment qualifies 129 Swift sources and sixteen binaries;
all compiler/runtime/SDK evidence is revalidated against current source and tools.
No production API, HTTP loading or external runtime dependency is added.
