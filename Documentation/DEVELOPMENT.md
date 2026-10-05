# Development and qualification

Ordinary applications depend on the `Lokalized` product and its compiled data.
The conformance executable, reference archives and Python/Java/Node tools are
development inputs. Run commands here from the repository root with the selected
Apple toolchain. No command below publishes a release or creates a Git commit.

## Everyday checks

```sh
swift build
swift test
swift run --skip-build LokalizedConformance --self-test
python3 Tools/verify_documentation.py --report .build/reports/documentation.json
python3 Tools/verify_package.py
python3 Tools/measure_package.py --check
git diff --check
```

The documentation check extracts the README/usage manifests, Swift blocks,
UTF-8 JSON resources and expected output directly from Markdown. It substitutes
only the remote development dependency with a fresh local source snapshot,
then builds and executes both complete programs. The original library manifest
is preserved, and Reference/Tools are absent from the snapshot. MainActor-default
resource consumption is exercised by the usage manifest. Receipts retain the
actual source/document hashes, compiler, commands, binary digests and exact
output. This checks these examples on the selected host; Apple app packaging
and other compiler/OS execution remain separately scoped.

## Frozen behavior and native adaptations

```sh
mkdir -p .build/reports
swift run --skip-build LokalizedConformance --inventory
swift run --skip-build LokalizedConformance --runtime-adapter
swift run --skip-build LokalizedConformance --resolution-components
swift run --skip-build LokalizedConformance --loader
swift run --skip-build LokalizedConformance --loader-boundaries
```

The original whole-runtime corpus records 2,381 cases. Its raw audit passes
**2,197 exact/projected runtime cases** and retains **184 pending carriers**:
159 JVM classpath/resource cases, five native filename-attribution differences
and twenty native nil-shape/callback configurations. The audit deliberately
exits **1**, with status `incomplete`; this is an expected result rather than
a green parity claim. CI checks the exact passing and pending ID sets:

```sh
audit_status=0
swift run --skip-build LokalizedConformance --audit \
  --report .build/reports/audit.json || audit_status=$?
test "$audit_status" -eq 1
python3 Tools/verify_package.py --audit-report .build/reports/audit.json \
  --binary "$(swift build --show-bin-path)/LokalizedConformance"
```

Exit 0 means the selected qualification command completed; exit 2 indicates
invalid arguments or a rejected archive. Other commands have their own scopes
and inventories. In particular, component projections do not replay every
whole-runtime channel. The shared
[core native contract](NATIVE-CONTRACTS.md),
[manifest native contract](MANIFEST-NATIVE-CONTRACTS.md) and
[loader dispositions](LOADER-DISPOSITIONS.md) account for native adaptations
separately, preserving original observations and unreplayed channels. Complete
accounting does not certify universal parity. Shared observer vectors remain
deferred under the pinned naming policy until the reference Java release.

## Data and reference integrity

```sh
python3 Tools/reference_baseline.py --check
python3 Tools/api_inventory.py --check
python3 Tools/verify_api_coverage.py --check
python3 Tools/materialize_fixtures.py --check
python3 Tools/generate_identifier_tables.py --check
python3 Tools/generate_warning_forms.py --check
python3 Tools/generate_plural_data.py --check
python3 Tools/generate_locale_data.py --check
python3 Tools/generate_language_range_data.py --check
python3 Tools/generate_idna_tables.py --check
python3 Tools/generate_idna_compatibility.py --check
python3 Tools/generate_idna_normalization_compatibility.py --check
python3 Tools/oracle_runtime.py --check
python3 Tools/verify_floating_point.py --check
python3 Tools/verify_locales.py --check
python3 Tools/verify_language_ranges.py --check
python3 Tools/verify_manifest_urls.py --check
python3 Tools/verify_idna_tables.py --check
python3 Tools/verify_idna_compatibility.py --check
python3 Tools/verify_idna_compatibility_normalization_tables.py --check
python3 Tools/verify_idna_normalization.py --check
```

Canonical shared artifacts live in `lokalized-spec`; the Swift repository keeps
byte-pinned offline snapshots. The 56,513-case IDNA archive stays compressed and
is never a runtime resource. Use the focused reference/profile guides and CI
workflow for sync recipes, amendment checks and negative controls. Refreshing
an oracle is a deliberate shared baseline change; a failing generator check
does not authorize replacing expected results.

[Catalog parser stress](PARSER-STRESS.md) adds deterministic adversarial inputs
and a fresh, pinned Java source oracle. Run `python3 Tools/test_parser_stress.py`
for its offline admission controls. The differential itself requires explicitly
supplied local Java sources/JDK/annotation jars; its recipe fetches nothing and
does not add a Swift package or runtime dependency. Keep minimized Swift defect
regressions in the test suite and shared normative artifacts in `lokalized-spec`.

[Expression stress](EXPRESSION-STRESS.md) uses the same frozen Java source/JDK
prerequisites to compare compiled predicates, typed evaluations, diagnostics and
resolver traces. Run `python3 Tools/test_expression_stress.py` for its offline
recipe checks; use the guide for the opt-in differential command.

[Locale-input stress](LOCALE-STRESS.md) mutates tags around JDK projection,
CLDR metadata and Unicode boundaries. Run `python3 Tools/test_locale_stress.py`
and `python3 Tools/generate_locale_unicode_tables.py --check` offline; the guide
describes the pinned JDK comparison and table reproduction.

## Platform and distribution checks

```sh
python3 Tools/verify_local_delivery.py --report .build/reports/local-delivery.json
python3 Tools/verify_deployment.py --compiler-track current \
  --report .build/reports/deployment.json
python3 Tools/test_source_package.py
python3 Tools/source_package.py --check
python3 Tools/verify_package.py --offline-build \
  --source-archive .build/reports/lokalized-swift-source.tar.gz \
  --report .build/reports/source-distribution.json
```

Use `--compiler-track minimum` only with the actual Swift 6.2 compiler.
[Deployment](DEPLOYMENT.md) separates four-target compilation, native hardware
execution, emitted OS floors and minimum-OS execution. [Apple local delivery](APPLE-LOCAL-DELIVERY.md)
checks real resource bundles and Swift 5 caller mode against the Swift 6 library.
[Packaged iOS execution](IOS-RUNTIME.md) and [full iOS conformance](IOS-CONFORMANCE.md)
need an explicitly selected installed simulator runtime; physical-device and
minimum-OS evidence remain separate.

[Concurrency](CONCURRENCY.md) records the Thread Sanitizer recipe, intentional
race control and finite workload. [Performance](PERFORMANCE.md) records optimized
consumer measurements and compiler/SDK/architecture-specific size caps. Timing
and memory observations are tied to the actual host and are not CI thresholds.

The [source-distribution check](SOURCE-DISTRIBUTION.md) extracts the complete
archive, validates notices, removes Reference/Tools and runs a public consumer
with zero external dependencies. Keep the source revision, input digests and
execution scope with each receipt. Earlier receipts remain historical after
their pinned inputs change; a configured CI job is not execution evidence.
