# Package size and performance

M8D measures the current public library through an optimized external SwiftPM
consumer. It adds development tools and size caps, with no production API,
dependency or conformance-disposition changes. These observations identify costs
to profile; they do not certify release parity or performance on other platforms.

## Reproduce

```sh
python3 Tools/measure_package.py --check
python3 Tools/measure_package.py --measure --samples 3 --report .build/reports/package-performance.json
python3 Tools/measure_package.py --report-check .build/reports/package-performance.json --negative-controls
```

Measurement requires macOS, an installed Apple Swift toolchain/SDK and Python's
standard library. `--compiler-track minimum` requires the actual Swift 6.2
compiler; the default `current` track records the installed compiler. The tool
copies package sources into a temporary directory without `Reference`, tests,
sibling repositories, build plugins or external packages. A separate consumer
imports only public APIs. Its sources, production sources, package declaration
and license are hashed and revalidated after execution.

An empty Foundation consumer first warms a private SDK cache. Each measured
release build uses a fresh SwiftPM build directory and recompiles the library;
SDK and operating-system caches are not flushed. The consumer's stripped and
unstripped sizes, architecture, linked images, macOS 12 deployment floor and
copied privacy resource are recorded. The source-only consumer has zero external
package dependencies and needs no reference archive to build or run.

Each of twelve workloads runs in a fresh process for each of three build samples.
Warm lookup loops follow twenty excluded lookups. They call `getResult`, validate
output/status/resolved locale and accumulate checked UTF-16 output lengths.
Fallback also verifies both locale attempts. Input generation precedes catalog
parse timing. Clock/malloc helpers are warmed without warming library tables;
heap snapshots and report formatting are outside timed stages. The generated
32,768-character workload also verifies refusal at a 32,767-character output cap
after the timed loop and resident-memory snapshot.

`malloc_zone_statistics` reports changes in live requested malloc bytes while
parsed models/runtime objects remain alive. It does not count allocations made
and freed, static storage or the whole application's memory. Darwin peak RSS
includes process/runtime/SDK and input-creation costs, and is captured before
hashing/JSON reporting. A small or negative warm heap delta does not imply an
allocation-free lookup.

## M8D local results, October 2, 2026

Host: arm64 macOS 27.0.1, Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), macOS SDK 27.0, Swift 6 language mode, release builds.
These observations precede the M8E optimization described below.
All numbers below are medians of three samples. Local evidence is
`.build/reports/m8d-package-performance.json`; its source/tool input manifest
SHA256 is `654546274f04de0f69760dc5dc4cce843b8c1f5c6605d9f4368d0cfaaddc2157`.
The report contains individual timings, input hashes, output checksums and memory
observations, so reruns can distinguish workload changes from measurement noise.

| Size/build observation | Result |
| --- | ---: |
| Runtime Swift source, 92 files | 1,291,764 bytes |
| Generated data Swift source, seven files (included above) | 810,025 bytes |
| Runtime resource (`PrivacyInfo.xcprivacy`) | 576 bytes |
| Optimized consumer build, warmed SDK cache | 19.19 s |
| Unstripped benchmark executable | 3,138,944 bytes |
| Stripped benchmark executable | 2,267,480 bytes (2.16 MiB) |
| Stripped empty Foundation consumer | 51,704 bytes |

The executable includes the benchmark driver and the code/data reachable from
its workloads. Its difference from the empty control is 2,215,776 bytes, but
that is not a library-only size or a prediction for an iOS application's size.
SwiftPM linking, dead stripping and each application's API use affect the
result. The development Unicode/reference archives are excluded from the built
product.

| Construction/first-use workload | Parse | Construct | First lookup | Other |
| --- | ---: | ---: | ---: | ---: |
| Cold one-entry runtime | 1.27 ms | 4.98 ms | 1.67 ms | 8.22 ms total, including 0.24 ms initial locale creation |
| 1,000-entry catalog | 3.10 ms | 6.34 ms | 1.39 ms | 26,781-byte input |
| 10,000-entry catalog | 22.04 ms | 21.57 ms | 1.18 ms | 287,781-byte input |
| Unicode-domain manifest planning | — | — | — | 4.45 ms first `fetchSet` |

Catalog workloads create `K0`…`K9999` with `Value0 {{name}}`… translations and
check the last key. They measure both parsed catalog retention and compilation
into `DefaultStrings`. Locale creation precedes the large-catalog snapshots;
those stages therefore have a different initialization boundary from cold-start.
The manifest workload plans `https://bücher.example/catalogs/en.json` to its
canonical Punycode URL. It performs no network request or catalog-body read.

| Warm public operation | Iterations per sample | Average per operation within the median loop |
| --- | ---: | ---: |
| Plain placeholder translation | 20,000 | 105.54 µs |
| French miss with English fallback | 10,000 | 119.10 µs |
| Cardinal integer `1` | 10,000 | 111.15 µs |
| Cardinal exact decimal `1.00` | 10,000 | 113.07 µs |
| Cardinal Double `0.1` | 2,000 | 121.34 µs |
| Cardinal Double π | 2,000 | 257.35 µs |
| Cardinal largest finite Double | 1,000 | 366.66 µs |
| Generate 32,768 output characters | 100 | 553.00 µs |
| Unicode-domain manifest planning | 200 | 183.62 µs |

These costs include result validation/checksum work and are not isolated
conversion/kernel timings or latency percentiles. The harder Double inputs make
the exact floating converter a useful profiling candidate; see its separate
[correctness oracle and earlier driver measurements](FLOATING-POINT.md). The
whole lookup path should be profiled before attributing plain-lookup costs to a
particular stage or choosing an optimization.

| Workload/stage | Median live malloc delta | Median process peak RSS |
| --- | ---: | ---: |
| Cold one-entry initialization plus lookup | 1,260,688 bytes | 9,371,648 bytes |
| 1,000-entry parse / construct | 534,832 / 854,848 bytes | 10,289,152 bytes |
| 10,000-entry parse / construct | 3,723,056 / 2,145,088 bytes | 17,924,096 bytes |
| Unicode-domain planning first use | 1,273,952 bytes | 9,764,864 bytes |

Warm lookup heap deltas range from 304 to 1,040 bytes in the small translation
workloads; the generated-output loop retains 359,344 more live bytes at its
snapshot. These are allocator/process observations, not allocation counts or a
leak determination. The actual schemas include lazy strings/dictionaries/sets;
the earlier M0 static-blob experiment's zero observed heap delta does not describe
the finished runtime. See [data encoding](DATA-ENCODING.md).

## Size caps and evidence checks

`Reference/package-size-budgets.json` caps generated Swift source at 851,968
bytes, all runtime Swift source at 1,310,720 bytes, and resources at 4,096 bytes.
Caps round observed source sizes to the next 64 KiB (resources: 4 KiB). They
provide explicit review points for future code/data growth; they are not
serialization budgets applied to user catalogs.

The measured Swift 6.4 / SDK 27.0 / arm64 artifact profile caps the stripped
benchmark consumer at 2,555,904 bytes: observed size plus 10%, rounded to 64 KiB.
Other compiler/SDK/architecture profiles report `unmeasured-profile` for the
binary cap until independently measured and reviewed. Source caps still apply.
CI runs measurements on both configured compiler tracks and retains reports;
local success does not establish that hosted CI has run. Timings and memory have
no pass/fail thresholds.

All three builds and 36 workload executions pass, including output-cap refusal
and copied-resource verification. Nine report-corruption controls reject stale
sources, a missing workload, a wrong output checksum, changed catalog input,
omitted budget refusal, a failed build, invented parity, omitted limitations and
source growth above its cap. These checks validate evidence consistency; they do
not add corpus passes or ratify pending native mappings.

Swift 6.2 execution, older supported OS execution, iOS device/simulator runtime,
Intel runtime, allocation counts and application-specific profiles remain
unmeasured here. Minimum deployment-floor inspection is recorded separately
from actual runtime qualification. No Java/JS performance equivalence is claimed.

## M8E: reuse immutable locale facts

```sh
python3 Tools/profile_lookup.py --output-directory .build/profiles/lookup
```

This optional macOS development tool builds an optimized public consumer from
unmodified production source copies and uses Apple's `sample` tool during warmed
plain/Double π/largest-Double lookups. It retains call graphs, checked consumer
outputs and source hashes. Attaching the sampler can require local process
inspection permission. Sampled-loop timings are diagnostic observations;
unsampled `measure_package.py` runs supply the comparison below. The profiler is
not a runtime dependency or a CI latency gate.

The before traces show repeated locale matching and candidate-chain construction
dominating plain lookup. The harder Double traces also show exact interval
conversion and its bounded unsigned division. Inlining, sample count and sampler
overhead limit precise attribution; the traces are not per-function timing
measurements.

M8E indexes the matcher’s existing immutable loaded-locale facts by exact tag,
retains each loaded tag's pinned CLDR parent sequence, and reuses likely-script
and undetermined-language facts during candidate selection. Other requests use
the existing pinned calculation. Storage grows with configured loaded locales;
requests do not populate a mutable cache. Candidate ordering/deduplication,
strict validation, fresh match-result construction, supplier/callback timing,
and per-call translation state retain their existing paths. The floating
converter and public API signatures are unchanged.

The comparison uses the same twelve workloads, three optimized builds per
version and the same Swift 6.4/SDK 27.0/arm64 host. After the optimized run, the
previous exact M8D source snapshot was rebuilt and rerun in a temporary copy;
its source/tool manifest matches M8D's original digest above. This avoids
attributing changes between the original M8D run and today's environment to
the optimization. The runs are sequential host observations, not randomized
statistical trials or guarantees for other machines.

| Checked warm operation | Repeated M8D baseline | M8E | Observed time reduction |
| --- | ---: | ---: | ---: |
| Plain placeholder translation | 116.08 µs | 57.07 µs | 51% |
| French miss with English fallback | 125.82 µs | 63.57 µs | 49% |
| Cardinal integer `1` | 117.28 µs | 64.29 µs | 45% |
| Cardinal exact decimal `1.00` | 115.49 µs | 60.45 µs | 48% |
| Cardinal Double `0.1` | 124.45 µs | 75.65 µs | 39% |
| Cardinal Double π | 275.28 µs | 217.05 µs | 21% |
| Cardinal largest finite Double | 364.58 µs | 319.66 µs | 12% |
| Generate 32,768 output characters | 531.46 µs | 477.93 µs | 10% |
| Unicode-domain planning | 188.28 µs | 191.61 µs | No demonstrated gain |

Cold total is effectively unchanged in these samples: 5.913 ms baseline versus
5.917 ms M8E. Construction rises from 3.506 to 3.653 ms while first lookup falls
from 1.289 to 1.122 ms. Large-catalog construction remains approximately 5.3 ms
for 1,000 entries and 21.3 ms for 10,000 entries; each workload loads one locale.
This does not measure the construction cost of an application loading many
locales. The cold live malloc delta rises by 18,496 bytes to 1,279,248 bytes.
Allocator metadata and retained locale facts participate in that observation;
it is not an isolated per-locale storage formula.

The stripped consumer grows by 496 bytes to 2,267,976 bytes; runtime Swift source
grows by 966 bytes to 1,292,730 bytes. Generated data and privacy resource bytes
are unchanged. Existing source and measured-profile binary caps pass without
raising them. Each version's 36 workload runs and nine corrupted-report controls
pass, including output-budget refusal. The full native suite passes 265 methods
with one existing filesystem skip, all 1,030 standalone checks pass, and the
main audit retains exactly 2,197 passing and 184 pending IDs with no failures or
ratified mappings.

Fresh symbol-graph qualification retains all 747 public reference dispositions
and rejects eighteen corrupted reports. Sixteen current-source binaries across
macOS arm64/Intel and iOS device/simulator target triples compile/link and meet
declared SDK floors. The arm64 macOS consumer and qualification executable run
on the host; this does not establish other-platform or minimum-OS execution.

Local current evidence is `.build/reports/m8e-package-performance.json` with
source/tool manifest SHA256
`44df3d9a3ac547ee53aef4ae7a0ce5e378967d9d7dfc15dc918d5b893d980172`.
The repeated baseline is `.build/reports/m8e-baseline-repeat.json`; traces are in
`.build/profiles/m8e-before/` and `.build/profiles/m8e-after/`. Historical baseline
receipts describe their old source snapshot and are checked against that copy,
not accepted as current-source qualification. The scoped summary is
`.build/reports/m8e-qualification-summary.json`.

Remaining profiling candidates include single-range match-member preparation and
the exact floating converter. Any numeric optimization must preserve the
[pinned oracle/golden checks](FLOATING-POINT.md). Minimum compiler, old-OS/iOS/
Intel runtime and hosted CI execution remain separate release gates.

## M8F: reuse exact floating trials

The numeric slice retains a three-entry window of exact exponent trials within
each conversion. Adjacent digit counts share two exponents, so the next pass
computes only the new exponent. Decade comparisons also reuse a single scaled
fraction. The [algorithm and oracle evidence](FLOATING-POINT.md) record why this
preserves candidate order, minimum digits, IEEE boundaries and closest/tie
selection. No shared input cache or external formatter is introduced.

The current source and an exact copy of the M8E source snapshot each pass three
fresh optimized builds and 36 checked workload runs, with all nine corrupted
receipt controls rejected per version. Compiler, SDK, architecture, workloads,
iteration counts and driver are unchanged. The baseline is rebuilt in a
temporary copy without changing the working tree or Git index. These sequential
same-host medians use the methodology and limits above.

| Checked warm operation | Repeated M8E baseline | M8F | Interpretation |
| --- | ---: | ---: | --- |
| Cardinal Double π | 225.74 µs | 125.04 µs | 45% less time |
| Cardinal largest finite Double | 309.22 µs | 164.60 µs | 47% less time |
| Cardinal Double `0.1` | 65.89 µs | 64.83 µs | Close to baseline |
| Cardinal integer `1` | 59.13 µs | 58.38 µs | Control; converter is not used |
| Cardinal exact decimal `1.00` | 60.39 µs | 59.36 µs | Control; converter is not used |
| Plain placeholder translation | 53.26 µs | 52.16 µs | Control; converter is not used |

These are complete checked public lookups, not isolated numeric timings.
Non-floating controls vary by approximately 1–2%; their changes are not claimed
as converter gains. Cold and parse observations also vary outside the changed
code path, so this slice makes no startup or memory-footprint improvement claim.
The fixed window is bounded local scratch storage; live malloc/RSS observations
do not count allocations made and freed or establish an allocation-free path.

The stripped consumer is 2,267,992 bytes, just 16 bytes above the repeated M8E
baseline. Runtime Swift source is 1,293,788 bytes, 1,058 bytes more; generated
data and the SDK privacy resource are unchanged. All existing source and
measured-profile binary caps pass without increases. The 110 selected numeric/
expression/fragment/bidi/translation test methods, 1,030 standalone checks and
the exact main-corpus 2,197/184 sets pass unchanged. The previous full M8E suite
is historical evidence; unrelated IDNA/loader suites are not rerun as part of
this targeted XCTest slice.

Current local measurements are `.build/reports/m8f-package-performance.json`,
with source/tool manifest SHA256
`6add0d0401660d08a0345c3c88881737f0f90bf5a2564daa705482064c0ce64e`.
The repeated historical baseline is `.build/reports/m8f-baseline-repeat.json`;
each report is checked against its actual source copy. The independent broad
Java differential matches all 103,310 inputs with zero differences and unchanged
input/output digests; the normal offline check passes the same 1,592 archived
goldens. Scoped evidence is `.build/reports/m8f-qualification-summary.json`.

Single-range match preparation remains an available profiling candidate.
Minimum compiler, old-OS/iOS/Intel runtime and hosted CI execution remain
separate release gates; these measurements do not ratify pending native mappings.


## M8G: single exact preference

A fresh native sample again attributed substantial ordinary-lookup work to
`MatcherMember.init` and language-range identity/canonical/CLDR preparation.
The [matcher shortcut](LOCALE-MATCHING.md) skips that preparation and the
candidate election for one finite, positive preference exactly matching a
configured tag. Undetermined non-private preferences are excluded. All other
requests use the existing election, and every returned result still passes the
normal validated initializer. No stored member metadata, growing request cache,
public API or dependency is added; configured tag identity and per-call supplier,
callback and result identity behavior are preserved.

The current source and an exact pre-change production/tool snapshot each pass
three fresh optimized builds and all 36 checked workload runs. Both versions
also refuse all nine corrupted measurement reports. Compiler/SDK/architecture,
consumer source, inputs, iteration counts and methodology are identical. Runs
are sequential same-host observations, not randomized trials or platform-wide
performance guarantees.

| Checked warm operation | Repeated pre-change baseline | M8G | Observed time reduction |
| --- | ---: | ---: | ---: |
| Plain placeholder translation | 53.04 µs | 7.50 µs | 86% |
| French miss with English fallback | 58.14 µs | 12.50 µs | 78% |
| Cardinal integer `1` | 58.80 µs | 12.69 µs | 78% |
| Cardinal exact decimal `1.00` | 59.59 µs | 12.88 µs | 78% |
| Cardinal Double `0.1` | 65.93 µs | 19.57 µs | 70% |
| Cardinal Double π | 122.66 µs | 78.16 µs | 36% |
| Cardinal largest finite Double | 167.07 µs | 120.18 µs | 28% |
| Generate 32,768 output characters | 491.44 µs | 428.96 µs | 13% |

These are complete checked public lookups. Their requested locales exactly
match loaded tags, including the per-key fallback workload; nonexact/multiple
preferences are qualified for behavior but not separately benchmarked here.
Pure Unicode-domain planning is a control outside the changed path: 187.58
versus 189.74 µs (about 1% variation), with no improvement claim. Remaining hard
Double costs still include the unchanged exact converter.

For the cold single-catalog, exact-first-lookup process, first lookup changes
from 1.337 ms to 0.058 ms; total locale creation/parse/construct/lookup changes
from 6.697 to 5.784 ms. Its live malloc delta changes from 1,279,296 to 998,912
bytes. Full-election metadata can remain lazy in an exact-only process; this is
not a general application startup/memory guarantee. A later nonexact request
still prepares that data. Large-catalog parse/construct observations vary and
are not attributed to the shortcut. Warm live heap deltas do not count transient
allocations or establish an allocation-free path.

The stripped benchmark consumer remains 2,267,992 bytes. Runtime Swift source
adds 1,053 bytes to reach 1,294,841 bytes; generated data and privacy resources
are unchanged. Existing source and measured-profile binary caps pass without
increases. Local evidence is `.build/reports/m8g-package-performance.json`, with
source/tool manifest SHA256
`1bc6f3c968930c4a2bbb4096da85e0d98e1fb1aed744d144797ad05d5a47018d`.
The exact repeated baseline is `.build/reports/m8g-baseline-repeat.json`, retaining
manifest `6add0d0401660d08a0345c3c88881737f0f90bf5a2564daa705482064c0ce64e`.
Sampling traces are in `.build/profiles/m8g-before/` and `m8g-after/`.


The after-change plain sampling trace has no `MatcherMember` frames; matching
samples now cover result construction/validation. Inlining and sampler overhead
limit attribution, so the unsampled benchmark supplies the timing comparison.


Three new native regression methods pass against both the original and changed
matcher. They cover both pinned equivalence modes, aliases/unknown/private-use/
extension tags, legacy typed identity, fractional/subnormal quality, fresh result
identity, multiple preferences/exclusions and undetermined/NaN/signed-zero
behavior. The full current XCTest suite passes 273 methods with one existing
invalid-UTF8 filesystem-fixture skip. All 747 API disposition records are
qualified again, eighteen corrupted receipts are refused, and the 1,155-symbol
public graph is identical to the pre-change graph.


All 1,057 standalone checks pass, including 27 added checks. The exact main
2,197 passing / 184 pending ID sets remain unchanged, with no failures or
ratified mappings. Fresh four-target Apple SDK qualification compiles, imports,
links and inspects sixteen binaries. Host arm64 consumer/data/component/
filesystem/manifest checks pass, including all 59,992 URL observations and
1,195,148 NFC checks. Only current arm64 macOS executes locally. Minimum Swift
6.2, minimum-OS/iOS/Intel runtime and hosted CI remain open release gates, as do
shared native-representation/filename mapping decisions. The scoped summary is
`.build/reports/m8g-qualification-summary.json`.
