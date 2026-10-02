# M0 data encoding experiment

Select **compiled compact UTF-8 `StaticString` payloads with generated offsets and
indexes** as the initial representation family for M2/M3. This local experiment
fits all three pinned exports into a 424,134-byte payload without allocating a
decoded object graph. Consumer builds will use checked-in generated Swift; they
will not run this tool, fetch data, invoke a plugin, or resolve a dependency.

This decision selects a representation family, not a final table schema. The
experiment packs three complete JSON exports, including provenance and plural
examples that production tables may omit. Its three record indexes do not measure
the final language/rule/alias lookup indexes. M2/M3 must generate typed, versioned
records or rule bytecode, measure the resulting indexes, and validate real semantic
lookups. Do not add eager whole-export Foundation JSON decoding to the runtime.

## Reproduce

From the repository root on an Apple Swift host:

```sh
python3 Tools/data_encoding_probe.py --samples 3 --rounds 25 \
  --work-dir /tmp/lokalized-data-encoding \
  --report /tmp/lokalized-data-encoding/report.json
```

The Python standard library tool reads only the selected local `Reference/`
exports and compiles standalone temporary applications with the selected
`swiftc`. It changes no library source or package settings. Omit `--work-dir` to
use and remove a temporary directory; `--reference PATH` selects another copy of
the same pinned exports. The JSON report contains all samples, generated source
hash, compiler/SDK/host metadata, binary sizes and measurement limitations.

An excluded empty-harness build warms a private system SDK module cache. Every
measured application compilation starts from Swift source with no application
object or incremental cache. All builds use `-O -whole-module-optimization`.
Each runtime sample starts a fresh process. OS page/filesystem caches are not
flushed: these are cold application builds/processes with a warmed SDK cache,
not cold-machine measurements. The probe uses the compiler's default host target;
it does not qualify the package's minimum OS declarations.

## Inputs and encoding integrity

| Export | Original bytes | Compact bytes | Original SHA-256 |
|---|---:|---:|---|
| `cldr-locale-data.json` | 360,048 | 360,048 | `6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93` |
| `cldr-plural-data.json` | 79,598 | 56,706 | `7ade4692762aac80144f915b62de19f29eb039ec3cf28c3f9f2c34b810cdc0e7` |
| `iana-language-equivalences.json` | 7,378 | 7,378 | `2398b866e6739ae81d9484da929567e68e8255fe31aefe5bf2ef25846c611462` |

The tool independently pins these input digests. Compacting removes insignificant
JSON whitespace; numeric tokens retain their exact spelling through a tagged
lexeme carrier, with no binary floating-point conversion. Decoded string values
retain Unicode spelling, including distinct composed/decomposed sequences.
All values round-trip through the compact encoding. Duplicate members, nonfinite
numbers, invalid UTF-8, unpaired surrogate escapes, and trailing JSON content are
rejected. Built-in probes include `1.2300`, `1E+0003` and `-0`.

Three compact JSON records are separated by exactly one LF. Generated indexes
contain native `Int` offset/length and `UInt64` FNV-1a checksum fields: 24 logical
bytes per record on this 64-bit host, 72 bytes total. The Swift harness checks
contiguous offsets, bounded lengths, separators, complete consumed length and
every record checksum before accepting a read. A generated source with an
appended unindexed payload byte was independently compiled and rejected. A
modified input export was rejected before generation/compilation. Runtime FNV-1a
is an integrity probe, not a cryptographic substitute for the original SHA-256 pins.

For this experiment:

- Packed payload SHA-256: `dd3193f429c9247df0513a56f0c352fd38bdeb91aac08aa66c2e94d181dc9d10`.
- Generated Swift SHA-256: `8ec1293c808e4e5a9262c334d080c09eb7c74869e7be78b3dcfbcd939b3c7f9f`.
- First indexed read checksum: `3082899470775259993`.
- The combined checksum for 25 repeated reads: `3285510474543293661`.

The packed payload hash identifies this experimental encoding. It does not
replace the shared CLDR/IANA fingerprints in `Reference/baseline.json`.

## Recorded measurement

Measured on 2026-10-01 with Apple Swift 6.4
(`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), Xcode 27.0 build `27A266a`,
macOS SDK 27.0, macOS 27.0.1, arm64. Swift 6.2 was **not executed**.

The matching local report and generated source are retained in
`/private/tmp/lokalized-data-encoding-m0-final/`. Its report is also copied to
the ignored `.build/reports/data-encoding.json` for this workspace's review.

| Measurement | Empty-data control | Compiled compact payload |
|---|---:|---:|
| Cold application compile, median of three | 0.470633 s | 0.487118 s |
| Executable size | 58,776 bytes | 488,072 bytes |
| Added executable bytes | — | 429,296 bytes |
| Table/index initialization, median | 125 ns | 208 ns |
| Initialization malloc live-byte delta | 0 bytes | 0 bytes |
| First full indexed checksum read, median | 42 ns | 0.549167 ms |
| 25 full indexed checksum reads, median | 83 ns | 11.811250 ms |
| Additional malloc live-byte delta during reads | 0 bytes | 0 bytes |
| Peak process resident bytes, median | 6,062,080 | 6,504,448 |

The excluded SDK warmup took 1.299977 s. Recorded compile samples in seconds were
`[0.477840, 0.470633, 0.465570]` for the empty control and
`[0.487697, 0.487118, 0.482455]` for the compact payload. Small timing differences
are noisy; no claim that this encoding beats every alternative follows from three
samples. Sub-microsecond initialization results show no measurable decode work
in this optimized harness and should not be extrapolated to larger final indexes.

As an initialization/heap control, the same executable can eagerly decode all
three JSON exports with native Foundation `JSONSerialization` and keep the
resulting objects alive. Its median initialization took **2.692292 ms** and added
**1,132,896 malloc live bytes**. Subsequent reads still checksum the encoded
records; they are not decoded-object semantic lookups. This control illustrates
the cost of constructing an entire object graph. It is not an exact-decimal
production decoder or another dependency proposal.

Malloc snapshots use Apple's `malloc_zone_statistics(nil, ...)`, which the SDK
documents as summing all malloc zones. Helpers are warmed before the first
snapshot; report formatting occurs afterward. Read timings exclude heap-stat
collection. Deltas measure observed live requested malloc bytes, not allocations
ever made, mapped static storage, total application memory or a promise of zero
heap use in the finished library. Peak resident bytes are reported separately.

## M2/M3 follow-through

Keep UTF-8 payloads in compiled read-only storage. Generate deterministic compact
indexes and decode only the typed fields needed by a lookup; retain exact decimal
scale/spelling where the contract requires it. Final decoders must reject unknown
format versions, invalid lengths/offsets, noncanonical encodings and unconsumed
trailing data, with explicit byte order/width and source/data identities. Preserve
all source licenses/notices when deriving the final tables.

Rerun compile, size, initialization and semantic lookup measurements after final
typed schemas/indexes exist, on minimum Swift 6.2 and current compilers, and on
supported Apple OS/architecture tracks. Neither minimum-OS behavior, iOS/device
behavior, Intel performance nor full expression-heavy Swift literals were
measured here. This M0 experiment establishes a practical candidate and an honest
local baseline; it establishes no localization conformance cases.

M3's actual [locale schema](LOCALE-DATA.md) uses compiled compact text with lazy
Swift dictionaries/sets, while [language-range tables](LANGUAGE-RANGES.md) use
indexed `StaticString` records and fixed-width casing data. The locale maps
retain allocated strings and hash storage; their fifteen-process optimized
initialization probe measured a 4.15 ms median for all 18,675 rows. That probe
does not measure heap/RSS or certify the M0 blob's zero observed allocation for
these different production schemas. Allocation, linked-size and minimum-track
measurements remain separate release qualification work.

[M8D package measurements](PERFORMANCE.md) now cover the actual compiled data,
optimized public consumer size, construction/lookup costs and live malloc/RSS
on the current arm64 Swift 6.4 host. Generated Swift data totals 810,025 bytes;
the cold one-entry runtime observes a 1,260,688-byte live malloc increase.
Minimum-toolchain and other platform execution remain open. These production
schema observations supersede any attempt to apply the M0 static-blob's zero
observed heap delta to the finished library.

M8E adds an immutable index of already computed loaded-locale facts and retains
their parent sequences to avoid repeated lookup-time computation. Current-host
measurements record a 1,279,248-byte cold live malloc delta, 18,496 bytes above a
repeated M8D baseline, with unchanged generated data. The lookup savings and
limits are recorded in [the current performance comparison](PERFORMANCE.md).
