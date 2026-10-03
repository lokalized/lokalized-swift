# Shared native contract coverage

M8H consumes `lokalized-spec`'s `swift-native-local-v1` contract through four
pinned offline artifacts. Canonical ownership is in that repository's
`NATIVE-ADAPTATIONS.md`, `conformance/swift-native-v1.json`,
`schema/native-adaptations.schema.json` and `tools/native_adaptations`.
The byte-identical local profile is [here](../Reference/swift-native-v1.json).
No runtime API, file grammar, dependency or HTTP loading is added.

The [native type dossier](NATIVE-REPRESENTATIONS.md) and
[loader dossier](LOADER-DISPOSITIONS.md) remain low-level evidence and do not decide
shared coverage themselves. `Tools/verify_native_contracts.py` validates current
compiler/host evidence through their original strict checkers, then applies the
shared contract. An independent deployment receipt must bind the original audit
to current library/support sources and qualification inputs, with actual matching
macOS-host execution. Stale sources, failed/unexecuted audit or changed original
observations cannot qualify.

## Current accounting

| Evidence | Required portable | Informational |
| --- | ---: | ---: |
| Exact runtime agreement | 2,135 | 62 |
| Qualified native adaptations | 20 source boundaries | 5 filename attributions |
| Platform-specific, unreplayed JVM carriers | 0 | 159 |

All 2,155 required portable obligations are covered under the declared contract.
Strict runtime agreement stays 2,197; original `--audit` stays at 2,197/184 with
no mappings or fabricated passes. The separate receipt stores all five disjoint
ID sets/digests, input/reference fingerprints, unreplayed channels and port-record
identities. Its status is `covered-under-native-contracts-not-certified` with
`releaseParity: false`. Source rejection does not replay null diagnostics or
callback traces. Only the specified five complete filename differences qualify.
JVM carriers remain outside native mapping counts.

Raw JSON null, representable callback/error/limit behavior and optional whole
settings retain their runtime obligations. An unmapped phonetic adaptation needs
consultation evidence and explicit-throw/valid-`.other` controls; it cannot
silently substitute `.other` for null.

## Reproduce

Generate current compiler/native and original runtime evidence using the linked
dossiers and standard `--audit` command. Then bind it to SDK/host qualification:

```sh
python3 Tools/verify_deployment.py --report .build/reports/deployment.json
python3 Tools/sync_native_contracts.py --check
python3 Tools/test_native_contracts.py
python3 Tools/verify_native_contracts.py \
  --audit-report .build/reports/audit.json \
  --type-report .build/reports/callback-types.json \
  --runtime-adapter-report .build/reports/runtime-adapter.json \
  --native-type-report .build/reports/native-representations.json \
  --loader-dispositions-report .build/reports/loader-dispositions.json \
  --deployment-report .build/reports/deployment.json \
  --report .build/reports/native-contracts.json
```

Repeat the final command using
`--report-check .build/reports/native-contracts.json --negative-controls` instead
of `--report`. Twenty-seven corruption controls reject stale source/runtime
bindings, missing/duplicate required IDs, invented runtime passes/release parity,
missing native guards/controls, unrelated compiler failures, changed filename/
reference evidence and fabricated platform execution. The underlying native/
loader checkers also refuse all 23/25 existing corruptions.

Offline snapshot and saved-report checks require only stdlib Python and this
checkout. Reads are bounded at 8 MiB, or 32 MiB for the deployment receipt's
56,513-ID URL inventory. No sibling checkout, compiler, refresh or network is
needed to check saved evidence. New execution needs the selected Apple toolchain.
Explicit `--check-source` or `--sync` on `Tools/sync_native_contracts.py` requires
a spec path and verifies all four source artifacts before any writes.

CI checks this contract under both compiler tracks after SDK qualification.
Native macOS qualification runs the target matching its actual arm64/Intel host;
only arm64 executed here. Local evidence passes seventeen negative consumers,
the positive consumer, 23 type/runtime controls, twenty loader/Bundle controls,
27 shared-coverage controls, five Swift-development Python tests and seven shared
tests. Four SDK targets inspect sixteen binaries. Host qualification retains
1,057 standalone checks, the exact main sets and all data/component/filesystem/
manifest/URL/NFC checks. Summary: `.build/reports/m8h-qualification-summary.json`.

Actual minimum Swift 6.2, minimum-OS/iOS/Intel runtime and hosted CI remain
unverified. This core profile is separate from the 31 JS manifest adaptations qualified by
[M8I](MANIFEST-NATIVE-CONTRACTS.md). The surrogate-diagnostic boundary outside
that archive remains open; see [manifest evidence](MANIFEST-CONTRACT.md).
