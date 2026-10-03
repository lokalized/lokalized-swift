# Local loader dispositions

M8H applies a versioned shared contract to the five filename adaptations and
retains the 159 JVM cases as informational platform-specific carriers. See
[native contract coverage](NATIVE-CONTRACTS.md). This low-level dossier itself
continues to add no original runtime passes or shared coverage claims.

M8C accounts for the remaining 164 loader IDs individually: **90 JVM package-discovery cases, 69 classloader resource-map cases, and five native filename-attribution differences**. Every one is `informationalIds` in the unchanged shared corpus. The report retains each authored input/fixture fingerprint, reference-observation fingerprint, native carrier choice, rationale and applicable native controls. It does not relabel donor classloader observations as native runtime passes.

## Native carrier scope

Swift's `loadFromBundle(directory:)` uses an explicit caller-selected Bundle and an exact ordinary directory. `loadFromResources` accepts already resolved local file URLs; the Bundle mapping overload accepts exact bundle-relative paths and typed locale keys. These boundaries replace JVM classloader/root resolution and package/resource name normalization. Literal native paths have their own validation and provenance. The JVM's trailing-slash package normalization, physical multi-release namespace restrictions, directory-listing streams, exhaustive root scans, JAR overlays and classpath filename-warning behavior are not added to Swift.

The 159 informational cases now have `platform-specific-informational` dispositions with their original input, filenames and loading options retained per ID. All six original loader observation channels remain explicitly unreplayed for those cases. Adjacent native controls prove the actual replacement API boundaries; they do not run those donor inputs or certify every underlying classloader observation. Portable parsing/validation/translation behavior remains qualified by the existing shared and native suites.

Twenty named controls execute real owned files and Bundles through public APIs. They cover independent bundles with identical paths, missing/empty/file-shaped directories, literal path validation including NUL/traversal, absence of a JAR-reserved namespace on Apple, nonrecursive discovery, canonical POSIX provenance and UTF-16-distinct keys, hidden/arbitrary mapped filenames, explicit `.lproj` paths, repeated-resource aggregate byte charges, no discovery charge for explicit maps, map-count validation before URL/I/O checks, directory refusal, rendered locale collision preflight, warning error identity/reentry, and deterministic directory failure ordering.

## Five complete filename observations

The original adapter still executes all five directory cases and retains both complete observations. The new checker derives the native attributed filename from authored UTF-8 filename order and the configured file cap. It requires the complete reason/message template, budget value and candidate membership; accepting any differing error message is insufficient.

| Input boundary | Native attribution | Frozen JVM attribution |
|---|---|---|
| Two invalid `.json` stems | `notes.json` | `zz.json` |
| 257 files, default cap 256 | `amh` | `afu` |
| Two files, cap 1 (two separate cases) | `fr` | `en` |
| Extensionless/JSON duplicate | `en.json` | `en` |

Locale/key results, failed flag, failure type and the complete warning array remain equal. The messages are retained separately without replacing filenames or rewriting expectations. These five records remain `evidence-ready-unratified`; no shared mapping is counted. The narrow guards still leave ordinary case/legacy/grandfathered filename collisions as real native passes.

## Reproducible qualification

```sh
python3 Tools/verify_loader_dispositions.py --qualify --report .build/reports/loader-dispositions.json
python3 Tools/verify_loader_dispositions.py --report-check .build/reports/loader-dispositions.json --negative-controls
swift run LokalizedConformance --loader-boundaries
```

Qualification copies current sources into an isolated directory, compiles the library/support/standalone executable with the selected Apple SDK, and runs both the original loader adapter and the new boundary controls. It snapshots and revalidates all compiled sources and this tool. The receipt records compiler/SDK/target/host, compilation/execution results, all native observations and all 164 records. Normal checking is offline and uses Python's standard library; no Java, Node, sibling repositories or external consumer dependencies are involved. CI generates and checks the receipt under both compiler tracks.

Twenty-five corruption controls reject incomplete inventories, invented mappings/passes, missing native checks, stale source, failed execution, unrelated diagnostic text, the wrong authored filename, altered file-cap values and changed warning channels. The five original adaptation observations retain their exact ID digest `f2e4b155d9ff9f7a77acf00a53fcead51f8482fce9e47230466543a51f779131`. The 145 passing loader IDs and overall 2,197 passed / 184 pending audit remain unchanged.

This qualification changes development support/tooling and documentation. It adds no runtime API, dependencies, networking, classloader or replacement manifest-delivery pipeline. Source compilation for macOS 12 and execution on the current arm64 host do not establish older-OS/iOS/Intel runtime or minimum Swift 6.2 execution. Those remaining release gates and shared native representation decisions remain explicit. The next implementation slice can move to package-size/performance measurement rather than trying to implement JVM/JS delivery mechanisms.
