# Standalone conformance on iOS

M8M runs all fourteen existing standalone qualification commands inside a real
arm64 iOS 26.5 simulator application, using freshly compiled source modules and
byte-identical packaged Reference inputs. The same build supplies the macOS
baseline. The iOS reports must match its complete observations, including every
passing and pending ID. This extends the [packaged catalog consumer](IOS-RUNTIME.md)
with the development conformance suite; the runtime library has no new API,
catalog format or dependency.

| Qualification | Recorded scope |
|---|---|
| Standalone self-tests | 1,057 checks |
| Frozen corpus inventory/audit | 2,381 IDs: 2,197 passes, 184 explicitly pending, zero failures |
| Public runtime adapter | 1,432 complete observations; 20 native representation cases retained separately |
| Single-catalog components | 578 projections; existing whole-case omissions retained |
| Native filesystem | 145 complete observations; 159 JVM carriers and five native filename differences retained separately |
| Native Bundle/resource boundaries | 20 owned-resource controls |
| CLDR plural / locale data | 24,227 / 263,771 checks |
| Manifest validation, identity and planning | 468 observations: 162 exact, 306 documented projections; 31 native carriers retained |
| Manifest normalization / diagnostic text | 35 / 36 shared profile observations |
| URL / IDNA | 3,479 URL and 56,513 Unicode-domain compatibility observations |
| Unicode 17 NFC | 100,170 official equations plus 1,094,978 scalar identity checks |

The corpus keeps its `incomplete` status. Native dispositions and archived
observations are preserved; running another platform does not promote pending
cases or certify shared release parity. The iOS suite calls the same development
qualification functions as the CLI, without XCTest. The separate macOS XCTest
run passes 278 methods with the existing filesystem skip.

## Reproduce

Use an installed arm64 iOS runtime explicitly; the tool does not download one:

```sh
python3 Tools/verify_deployment.py \
  --output-directory .build/deployment --report .build/reports/deployment.json
python3 Tools/verify_ios_conformance.py \
  --deployment-report .build/reports/deployment.json \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --report .build/reports/ios-conformance.json
python3 Tools/verify_ios_conformance.py \
  --deployment-report .build/reports/deployment.json \
  --report-check .build/reports/ios-conformance.json --negative-controls
python3 Tools/test_ios_conformance.py
```

The source-bound deployment receipt and retained binaries must still match the
checkout. The qualifier compiles a Swift 6/MainActor SwiftUI shell, packages both
local source libraries, actual privacy metadata and the frozen development inputs,
then inspects the three app Mach-O files for arm64/iOS simulator, an iOS 15 floor
and Apple/system or local-module dependencies. Local ad-hoc signatures require
no signing identity. No reference artifact enters the production library.

The shell starts qualification off the UI thread after launch. It encodes the
original JSON bytes into bounded 1,024-character base64 lines, avoiding a blocked
simulator console on large reports. The host rejects missing/duplicate frames,
invalid encoding or JSON, altered observations and missing commands. All fourteen
commands must execute in the recorded order on the same newly created simulator.
The receipt retains compiler, source/input/package hashes, installed and booted
runtime evidence, complete command output and owned-device shutdown/deletion.
Commands have bounded timeouts, and cleanup also runs after failures or interruption.
No existing simulator, physical device or downloaded runtime is used.

Three fixture helpers previously assumed `/private/tmp`. They now share the
existing local-loading qualification's POSIX-canonical temporary-directory logic.
Fixtures therefore remain writable inside an iOS app sandbox, and origin checks
retain exact canonical paths. This changes development support only; the production
local-file loader is unchanged.

Fifteen offline Python tests use explicitly synthetic receipts/packages; twenty
controls corrupt actual saved evidence. They cover omitted/reordered commands,
host-command substitution, stale input/deployment pins, false minimum-OS claims,
encoding/JSON failures, passing/pending-ID omissions, false corpus completion,
Boolean counters, Unicode/diagnostic drift, wrong runtimes and owned cleanup.
Saved checks need no Simulator service or compiler, but still require current
checkout bytes, the retained deployment receipt/binaries and built app. Receipts
are local evidence, without authentication of files supplied by another party.

CI runs offline tests on both compiler tracks. A manual workflow with
`ios_runtime` runs both the packaged consumer and this suite on its current arm64
track. An unavailable/incompatible requested runtime fails the step; hosted CI
execution remains unverified locally.

## Current evidence and remaining gates

The local run uses Swift 6.4/Xcode 27 and iOS 26.5 build 23F77. Reports are
`.build/reports/m8m-deployment.json`, `m8m-ios-conformance.json`,
`m8m-ios-conformance-check.json` and `m8m-qualification-summary.json`.
The original M8K/M8L receipts remain historical; their source stamps predate the
development fixture change. Fresh M8M SDK/native-coverage and packaged-delivery
receipts replace them for checks against this checkout.

This closes execution of the existing standalone suite on a current iOS simulator.
Swift 6.2, iOS 15/macOS 12 runtime, physical-device, Intel and hosted-CI execution
remain open. The iOS CLI binaries remain link probes; runtime evidence comes from
the actual app. There are no new external runtime dependencies or HTTP loading.
