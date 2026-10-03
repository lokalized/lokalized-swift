# Apple deployment verification

The package declares iOS 15 and macOS 12 with Swift tools 6.2 and Swift 6 language
mode. `Tools/verify_deployment.py` checks the actual current Swift sources against
those deployment targets with the selected Xcode compiler and SDKs. It uses only
Python's standard library and Apple developer tools, with no package resolution.

Run from the repository root:

```sh
python3 Tools/verify_deployment.py
```

The script retains binaries, emitted modules, a generated consumer, module caches,
and `deployment-report.json` in a fresh `/private/tmp/lokalized-deployment-*`
directory. Use `--output-directory PATH` or `--report PATH` to choose destinations.
The JSON report contains the compiler and SDK versions, every Swift source and
binary hash, hashes of the script, manifest, generated consumer, and pinned reference
inputs, every command and result, and separate compilation and runtime
observations. The check fails if the Swift source list, source contents, or other
inputs change during execution.

For each target below, it emits and links the actual `Lokalized` library and the
development-only `LokalizedConformanceSupport` module, then imports them in the
conformance CLI and a consumer that exercises the implemented public primitives.
All compilation uses the same package name, so the development harness can access
the library's package-visible JSON reader. The generated consumer calls public
APIs only, including caller stream/file/directory/resource-map ingress and ordered/Apple preference helpers.

| Target | Explicit Swift target triple | Required Mach-O minimum OS |
| --- | --- | --- |
| macOS arm64 | `arm64-apple-macosx12.0` | 12.0 |
| macOS x86_64 | `x86_64-apple-macosx12.0` | 12.0 |
| iOS arm64 device | `arm64-apple-ios15.0` | 15.0 |
| iOS arm64 simulator | `arm64-apple-ios15.0-simulator` | 15.0 |

`vtool`, `lipo`, and `otool` verify each emitted Mach-O file's platform, deployment
version, architecture, and linked dependencies. The check accepts the two local
source modules and Apple system frameworks, libraries, and Swift runtime
libraries. The dylibs are temporary verification artifacts; package consumers
continue to build the source targets through SwiftPM.

On a native arm64 or Intel Mac, the script executes the matching macOS consumer,
conformance self-tests, frozen-corpus inventory, complete plural/locale data audits,
single-catalog component projections, whole-runtime audit, native filesystem,
manifest, diagnostic, URL/IDNA and NFC observations on the host OS. The other
macOS architecture and iOS outputs are compiled and inspected without execution.
The iOS CLI is a link
check for the development harness, with no application bundle, signing, or device
installation. Inventory checks count the corpus; they do not assert completed
translation parity.

Pass `--compiler-track minimum` on a machine whose selected compiler is exactly
Swift 6.2. The check refuses another compiler on that track. A newer compiler
checks source availability for the declared floors but cannot establish that
Swift 6.2 accepts the sources. Executing a binary on a newer host OS likewise
cannot establish behavior on macOS 12 or iOS 15.

CI may retain each compiler track's artifacts inside its workspace:

```sh
python3 Tools/verify_deployment.py \
  --compiler-track minimum \
  --output-directory .build/reports/deployment-minimum \
  --report .build/reports/deployment-minimum.json
```

Use `current` and distinct output/report paths in the newer compiler job. The
compiler and SDKs follow the selected Xcode installation. Module caches stay
inside the writable output directory, and the script does not invoke SwiftPM or
download dependencies. Runtime checks execute the native matching macOS target;
the other architecture retains an explicit `not executed` runtime observation.

## Native host and CI tracks

Before compiling the library, the tool compiles and runs a small Swift probe with
the selected compiler. It checks the program's compiled architecture against the
kernel's `hw.cputype` and `hw.optional.arm64`, requires zero
`sysctl.proc_translated`, and compares the program's OS version and architecture
with the Python process. An absent optional kernel key means zero; another kernel
error fails the probe. Intel execution under Rosetta cannot qualify native Intel
hardware. The report retains the probe source digest, actual output, inspected
Mach-O binary and complete command evidence.

Use an explicit architecture requirement when qualifying a known host:

```sh
python3 Tools/verify_deployment.py --host-architecture x86_64 --compiler-track minimum
```

`--host-only` performs just the compiler/kernel/Mach-O preflight. It reports zero
compiled library targets and explicitly excludes library qualification. A failed
architecture or minimum-compiler check exits 1 and retains a failed report.

CI now has three distinct tracks: minimum Swift 6.2 on `macos-15` arm64,
minimum Swift 6.2 on `macos-15-intel`, and the current compiler on `macos-26`
arm64. Both minimum tracks select `/Applications/Xcode_26.0.1.app`; the current
track selects the image's default Xcode. The runner labels and installed paths
were checked against the official [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
and [Intel image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
on October 3, 2026. Every job requires its actual native architecture before the
full workflow runs, repeats that requirement during SDK qualification, and
retains a distinct artifact. Intel uses the same tests, complete runtime audits,
native coverage, packaged consumers and optimized measurements. Unmeasured
compiler/SDK/architecture profiles retain the existing explicit unmeasured binary
budget; source caps remain enforced. No size cap is invented for Intel.

This configuration has not been executed by GitHub. Swift 6.2, native Intel and
hosted CI remain open until actual successful runs are retained. Neither modern
runner establishes macOS 12 or iOS 15 runtime behavior.

## Local evidence

On 2026-10-01, the check passed on an arm64 Mac running macOS 27.0.1 with Apple
Swift 6.4 (`swiftlang-6.4.0.34.1`) and the macOS, iPhoneOS, and iPhoneSimulator
27.0 SDKs. All four target rows above compiled and linked the library, support
module, consumer, and conformance CLI. Inspection of all 16 Mach-O files confirmed
their requested platform, architecture, and minimum OS. Their dependencies were
the local source modules and Apple system/Swift runtime libraries; CryptoKit was
linked by the development support module.

The macOS arm64 consumer executed public catalog/numeric/plural/locale/value and translation APIs successfully,
including full result metadata, strict inspection, retained match/observer-error identity, bidi, literal failure responses, explicit UI display policy, actual stream/file/directory/resource-map loading and ordered/Apple preference acquisition.
The standalone conformance CLI passed 795 self-checks, read the frozen inventory of 2,381 cases and 586
fixtures, passed the 24,227-check plural and 263,771-check locale audits, and passed 578 separately scoped single-catalog component projections. The separately executed whole-runtime audit passes 2,197 cases with zero failures and 184 explicitly pending cases. The native filesystem audit passes 145 full observations and retains five actual/frozen diagnostic-order differences plus 159 pending JVM carriers. The x86_64 and iOS outputs were not executed.

The final M6 local report is `/private/tmp/lokalized-swift-deployment-m6-final-report.json`, and its
retained binaries are in `/private/tmp/lokalized-deployment-e4e1_lqf`. The report
records all 104 Swift source hashes and complete compiler/inspection command output.
Temporary paths describe this local run and are not required by future runs.

Swift 6.2 compilation, macOS 12 runtime execution, and iOS 15 runtime execution
remain **not verified**. This machine has the newer compiler and host OS; no
minimum-version runtime was exercised. These gaps require separate minimum
compiler and OS runtime jobs before they can be claimed as tested.

## Packaged local-resource evidence

The independent `Tools/verify_local_delivery.py` check also passed on this host.
Its fresh source-only SwiftPM consumer compiled and executed both Swift 6 with
default MainActor isolation and Swift 5 language mode against the unchanged
Swift 6 library using the selected Swift 6.4 compiler. It loaded actual
`.copy("Lokalized")` resources through the consumer's `Bundle.module`.

The shared SwiftUI Xcode consumers compiled into actual macOS, iOS simulator and
iOS device applications with verified `SWIFT_VERSION=6.0`, default MainActor
isolation and approachable concurrency. Each preserved `Lokalized/en` and
`Lokalized/fr.JSON` paths and bytes, and the exact Lokalized SDK privacy manifest.
The macOS app executed `--qualify` using its packaged `Bundle.main`, verifying
simultaneous English/French contexts, plural rendering and distinct NFC/NFD keys.
Actual app binaries have macOS 12.0 or iOS 15.0 deployment floors. iOS products
were not signed, installed or executed.

The final report is `/private/tmp/lokalized-swift-local-delivery-m6-final.json`;
retained source snapshot, products, commands, settings and hashes are in
`/private/tmp/lokalized-local-delivery-b8ropiyj`. No Reference artifacts or sibling
checkouts were present in that snapshot. These are local execution records,
not an App Store privacy approval, a Swift 5 compiler test, an old-OS runtime
test or a completed hosted CI run. [Apple delivery](APPLE-LOCAL-DELIVERY.md)
describes the resource recipes and metadata declaration.

## M7A qualification

The final M7A report `/private/tmp/lokalized-swift-deployment-m7a-report.json` records output directory `/private/tmp/lokalized-deployment-7hxs6p_y`, 116 frozen Swift source hashes, all four target triples and 16 inspected Mach-O files with macOS 12/iOS 15 deployment floors. The public consumer now executes manifest claim construction, canonical identity/projection, validation, complete locale configuration and subset candidate/fetch planning. CryptoKit remains an Apple system dependency; there are no external runtime packages.

Host arm64 execution passes 973 standalone checks, both data audits, the retained 2,197/184 main-corpus sets, 145 native filesystem observations, the separately scoped 468/31 manifest inventory (165 strict native-equal and 303 explicit error projections), and 3,250 qualified URL observations with 229 named pending IDNA capabilities. Source and input hashes remain unchanged after qualification. The packaged consumer report `/private/tmp/lokalized-swift-local-delivery-m7a.json` additionally executes the actual Bundle.module manifest planning example in Swift 6/MainActor and Swift 5 caller language modes. These results retain the earlier limits on minimum compiler, old-OS, iOS and Intel runtime execution; they do not certify release parity. HTTP loading is outside the Swift scope following the October 2 decision.

## M7B1 qualification

The final report `/private/tmp/lokalized-swift-deployment-m7b1-report.json` records all four target triples and 16 inspected Mach-O outputs from 124 frozen Swift sources, retaining macOS 12/iOS 15 deployment floors and Apple/system-only dependencies. Both source and qualification-input hashes remain unchanged after the run. The host public consumer uses a Unicode manifest base and observes the expected Punycode fetch URL from compiled tables, without Reference artifacts. Fresh source-only SwiftPM consumers compile and execute with zero external package dependencies.

Host arm64 execution passes 973 standalone checks, the retained runtime/data/filesystem/manifest gates, all 59,992 URL observations and 1,195,148 canonical NFC checks. The new URL archive independently pins mapping, compatibility normalization/properties, input recipes and the Node executable plus five actual loaded URL/Unicode engine images. Table decoders qualify every codepoint separately; those development archives and engines are absent from consumer requirements. The combined evidence is `.build/reports/m7b1-qualification-summary.json`.

The packaged consumer report `/private/tmp/lokalized-swift-local-delivery-m7b1.json` passes actual SwiftPM Bundle.module consumers in Swift 6/MainActor and Swift 5 modes, the unsigned macOS Bundle.main app, and macOS/iOS simulator/iOS device compilation/resource checks. The complete XCTest suite passes 263 methods with the existing malformed-filename fixture skipped. Swift 6.2, macOS 12/iOS 15 runtime, iOS app runtime, Intel runtime and hosted CI execution remain unverified locally. Full WHATWG suite coverage and shared corrections to the recorded URL compatibility policy remain separate release work.

## M8E qualification

The current-source report `.build/reports/m8e-deployment.json` passes all four
target triples and sixteen compiled/imported/linked/inspected binaries, retaining
macOS 12/iOS 15 SDK floors and local-source/Apple-system-only dependencies. On
the arm64 macOS host, the public consumer and qualification executable pass
1,030 standalone checks, both data audits, the exact 2,197/184 main-corpus sets,
filesystem/component/manifest checks, all 59,992 URL observations and 1,195,148
canonical NFC checks. Source/input identities are revalidated after execution.

This refresh follows immutable locale fact reuse; the public symbol graph is
unchanged. The separate full native suite passes 265 methods with one existing
filesystem skip. Current source-only optimized SwiftPM consumers also compile
and execute twelve checked workloads, preserving the exact SDK privacy resource.
[Performance evidence](PERFORMANCE.md) records the gains and memory/size costs.
Swift 6.2, minimum-OS/iOS/Intel runtime and hosted CI execution remain open;
this slice does not rerun packaged SwiftUI applications. Scoped evidence is
`.build/reports/m8e-qualification-summary.json`.

## M8F qualification

`.build/reports/m8f-deployment.json` refreshes all four target triples and sixteen
compiled/imported/linked/inspected binaries after floating trial-window reuse.
The SDK floors and Apple/system-only dependencies are unchanged. Host arm64
consumer/standalone/data/component/filesystem/manifest/URL/NFC checks pass,
including the unchanged 2,197/184 main-corpus sets and 1,030 standalone checks.
The public symbol graph remains identical and all 747 reference dispositions
are checked again, with eighteen corrupted reports refused.

The targeted native numeric/translation suite passes 110 methods; the independent
pinned Java oracle matches all 103,310 Float/Double inputs and the normal offline
check passes all 1,592 archived goldens. Minimum compiler and other-platform/
minimum-OS runtime remain unverified locally. Packaged SwiftUI applications are
not rerun in this slice. Scoped evidence is
`.build/reports/m8f-qualification-summary.json`.


## M8G qualification

`.build/reports/m8g-deployment.json` refreshes all four target triples and sixteen
compiled/imported/linked/inspected binaries after the single-exact-preference
matcher shortcut. Its 127 Swift source hashes and qualification-input hashes
are stable through execution. macOS 12/iOS 15 SDK floors and Apple/system-only
dependencies are unchanged. The current arm64 macOS consumer and qualification
executable pass 1,057 standalone checks, both full data audits, the exact
2,197/184 corpus sets, component/filesystem/manifest checks, all 59,992 URL
observations and 1,195,148 NFC checks.

The separate full native suite passes 273 methods with one existing invalid-UTF8
filesystem-fixture skip. The public API graph remains identical (1,155 symbols),
all 747 reference dispositions are qualified again, and eighteen altered reports
are refused. Three fresh optimized source-only public consumers also compile and
execute all twelve measured workloads per build, retaining zero external package
dependencies and the exact privacy resource. See [performance](PERFORMANCE.md).

Actual Swift 6.2, minimum-OS/iOS/Intel runtime and hosted CI execution remain
unverified here. Packaged SwiftUI applications are not rerun in this slice.
Scoped evidence is `.build/reports/m8g-qualification-summary.json`.


## M8H source-bound native coverage

`.build/reports/m8h-deployment.json` refreshes all four target triples and sixteen
compiled/imported/linked/inspected binaries from the same 127 Swift sources as
M8G. Production APIs and dependencies are unchanged. The current arm64 host
executes the public consumer, 1,057 standalone checks, both data audits, exact
main-corpus sets and all component/filesystem/manifest/URL/NFC qualification.

The native coverage gate now requires this receipt's source/input identities and
actual matching-host main audit before qualifying shared adaptations. Stale or
unexecuted runtime evidence is refused. The deployment tool also selects its
matching macOS architecture for host execution, enabling x86_64 qualification
on an appropriate host; this local run executes only arm64. Minimum Swift 6.2,
minimum-OS/iOS/Intel runtime and hosted CI remain unverified. This tools-only
slice does not rerun the full M8G XCTest suite or packaged SwiftUI applications.
See [native contract coverage](NATIVE-CONTRACTS.md); scoped evidence is
`.build/reports/m8h-qualification-summary.json`.


## M8I source-bound manifest coverage

`.build/reports/m8i-deployment.json` refreshes the same four target triples and
sixteen binaries from 127 unchanged Swift source files. The host arm64 consumer,
1,057 standalone checks and all core/data/component/filesystem/manifest/URL/NFC
checks pass. Qualification inputs now include the complete shared manifest
snapshot and comparison code; the native gate requires the actual host manifest
receipt and its execution log before qualifying adaptations.

The new external compiler consumer run separately validates thirty source
refusals, one accepted identity default and sixteen adjacent runtime controls.
All 23 new and fifteen existing raw-manifest corruption controls are refused,
and 33 selected manifest/identity XCTest methods pass. A copied checkout verifies
saved evidence offline without siblings or invoking a compiler. The raw manifest
report and all runtime sources are identical to the prior evidence. No production
code, API or dependency changes; the prior full-suite and packaged-app evidence
remains historical unchanged-source evidence. Actual Swift 6.2, minimum-OS, iOS,
Intel and hosted-CI execution remain unverified. See
[manifest native qualification](MANIFEST-NATIVE-CONTRACTS.md); scoped summary is
`.build/reports/m8i-qualification-summary.json`.


## M8L packaged iOS runtime consumer

The separate [iOS runtime qualifier](IOS-RUNTIME.md) now executes the freshly
packaged SwiftUI catalog app on an arm64 iOS 26.5 simulator, including real
Bundle.main resource loading, English/French translations, exact Unicode keys
and French plural lookup. It records the installed/booted runtime, current input
and app hashes, actual app output and successful temporary-device cleanup.
Fresh SwiftPM Swift 6/Swift 5 caller consumers and the packaged macOS app execute;
all three Apple app products retain verified floors, settings and resource bytes.
Nine offline checker tests and ten corrupted-receipt controls pass. The local
receipt is `.build/reports/m8l-ios-runtime.json`.

This extends packaged-consumer execution coverage only. The standalone iOS
conformance binaries above remain compile-only; iOS 15, physical device, full iOS
corpus, minimum Swift, macOS 12, Intel and hosted CI evidence remains open.
Production sources and the M8K four-target SDK/host corpus receipts are unchanged.

## M8M standalone iOS runtime qualification

The [standalone iOS suite](IOS-CONFORMANCE.md) executes all fourteen CLI
qualification commands through a real SwiftUI app on arm64 iOS 26.5 (23F77).
Complete observations match the freshly rebuilt macOS baseline, including the
exact 2,197 passing / 184 pending corpus IDs, 1,057 standalone checks, native
filesystem/runtime/Bundle controls, both manifest amendments, CLDR data, all URL/
IDNA observations and Unicode 17 NFC equations/identity checks. The three app
Mach-O files have verified iOS 15 floors and Apple/system or local dependencies.

Four development-support files now share POSIX-canonical application temporary
paths. Production library sources are unchanged. Fresh SDK qualification builds
all four targets/sixteen binaries from the current 129 sources; source-bound
native coverage and packaged-delivery receipts are refreshed for this checkout.
Earlier source-bound reports remain historical. The macOS XCTest suite passes
278 methods plus the existing skip. Fifteen offline checker tests and twenty
corrupted iOS receipt controls pass. CI can run the full suite when an installed
runtime is explicitly requested; no hosted run is claimed.

Actual minimum Swift 6.2, iOS 15/macOS 12, physical-device, Intel and hosted-CI
execution remain open. The corpus retains its incomplete status and native
carrier dispositions; current-simulator execution does not certify release parity.

## M8N native host and CI qualification

The current-source `.build/reports/m8n-deployment.json` retains a compiled,
executed and inspected native arm64 kernel probe alongside all four targets and
sixteen library/support/consumer/CLI binaries. All 129 Swift source hashes match
M8M. Native macOS execution retains the same complete observations and exact
2,197 passing / 184 pending main-corpus sets. Fresh core and manifest coverage
receipts accept this SDK evidence; their corruption checks pass.

Actual `--host-architecture x86_64` and `--compiler-track minimum` preflights fail
with retained failed receipts on this arm64 Swift 6.4 machine. Eleven offline
probe tests reject translated/contradictory hardware, wrong process or requested
architecture, malformed OS observations and noninteger kernel values. These
offline controls do not count as executing Rosetta or Intel hardware.

`.build/reports/m8n-ios-conformance.json` refreshes all fourteen standalone
commands on an owned iOS 26.5 simulator using the new SDK binaries; complete
observations match the fresh macOS baseline, and shutdown/deletion pass. The
twenty corrupted-receipt controls pass. Existing M8M packaged catalog evidence
remains current for unchanged source/packaging inputs and is checked again.

CI now includes native Intel, but has not run. Actual Swift 6.2, Intel, minimum
OS, physical-device and hosted-CI execution remain open. No production source,
public API, corpus/profile, runtime dependency or HTTP-loading change is made.
Scoped summary: `.build/reports/m8n-qualification-summary.json`.
