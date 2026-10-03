# Shared manifest normalization amendment

M8K consumes `manifest-normalization-v1.1`, version 1.1.0. The shared
[contract and migration](../../lokalized-spec/MANIFEST-NORMALIZATION.md) define the
independent cases, historical amendments and publishing rules. The Swift
snapshot supports offline checks without a sibling checkout.

Manifest locale normalization now performs strict JDK projection, then removes
`und-` only from a private-use-only `und-x-…` result. `UND-x-foo` normalizes to
`x-foo` on the first and every subsequent manifest operation. Script, region,
variant and ordinary extensions retain their information. Core `LocaleTag`
projection retains its historical Java-compatible behavior.

All public parsing/validation/planning doors use the stable manifest projection.
Fingerprint validation continues to refuse stale declared identities. Publishers
must normalize locale keys/values, reject collisions, resolve configuration and
recompute the fingerprint; see the shared migration example. Raw standalone
identity property names stay exact, and `catalogIdentityInputFor` preserves raw
authored digest keys unless its caller supplies a validated manifest.

The six pinned artifacts are the profile, schema, active native lock and the
three `Tools/ManifestNormalization` package/recipe/checker files:

```sh
python3 Tools/sync_manifest_normalization.py --check
python3 Tools/sync_manifest_normalization.py --check-source --source ../lokalized-spec
python3 Tools/verify_manifest_normalization.py --check
swift run LokalizedConformance --manifest-normalization --reference Reference --report .build/reports/manifest-normalization.json
python3 Tools/verify_manifest_normalization.py --report-check .build/reports/manifest-normalization.json --negative-controls
swift run LokalizedConformance --manifest-contract --reference Reference --report .build/reports/manifest-contract.json
python3 Tools/verify_manifest_contract_report.py .build/reports/manifest-contract.json --self-test
```

Explicit `--sync --source PATH` verifies every source before writing any copy.
The production target imports none of these development artifacts or tools.
Three XCTest methods execute all 35 cases, refuse changed fixture bytes and
ensure expected observations cannot configure actual public operations.

The active raw report scope is
`native-manifest-validation-identity-planning-v1.1`. It retains the historical
reference for all 499 archive IDs and a separately named amended reference for
exactly four corrected IDs. Current runtime accounting is 464 unchanged
historical agreements plus four amended comparisons, partitioned as 162 exact
observations and 306 explicit native error projections. The 31 input-derived
native adaptations remain separate. Historical scope/bytes/checker stay valid
for historical receipts; current sources are not claimed to reproduce those
four superseded expectations. Eighteen active-report and thirteen profile-report
corruption controls pass. The full native ledger includes all unprojected fields.

`verify_deployment.py` builds four SDK targets, inspects sixteen binaries and
executes both profile commands on the matching native macOS host. Native-carrier
qualification composes the behavior amendment with the unchanged
`swift-native-manifest-v1` policy and requires those actual source-bound runs.
Current local evidence uses 129 Swift source files, Swift 6.4 / SDK 27 and arm64
macOS 27.0.1. All 278 XCTest methods pass with one additional existing filesystem
skip. All 1,057 standalone checks and the unchanged 2,197 passing / 184 pending
core-corpus sets pass. Six shared and five existing Swift-development Python
tests also pass. Scoped receipts are `.build/reports/m8k-*`.

Swift still has zero external runtime dependencies and no HTTP loader. Minimum
Swift 6.2, minimum OS, iOS/Intel runtime and hosted CI execution remain open.
The amended native receipt reports coverage under declared contracts with
`releaseParity: false`; compiler adaptations are not runtime equality claims.
