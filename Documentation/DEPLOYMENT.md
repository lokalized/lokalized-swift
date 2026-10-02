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

On an arm64 Mac, the script executes the macOS arm64 consumer, conformance
self-tests, frozen-corpus inventory, complete plural/locale data audits and single-catalog component projections, the whole-runtime audit and native filesystem observations on the host OS. The x86_64 executable and
iOS outputs are compiled and inspected without execution. The iOS CLI is a link
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
download dependencies. Runtime checks execute on arm64 macOS hosts; another host
architecture retains an explicit `not executed` runtime observation.

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
