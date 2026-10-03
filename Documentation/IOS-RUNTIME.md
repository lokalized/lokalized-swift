# Packaged iOS simulator execution

M8L executes the real source-built `IOSCatalogs` SwiftUI app on an arm64 iOS 26.5
simulator. The app uses `Bundle.main` local catalogs and the ordinary public
Lokalized API under default MainActor isolation and approachable concurrency.
Swift 6.4 / Xcode 27 builds the app for an iOS 15 deployment floor. It passes
English/French rendering, separate NFC/NFD keys and French integer plural lookup.
The app also constructs its Apple-preference display during initialization.
This is actual simulator execution, separately from SDK compile/link inspection.

## Run and check

First build fresh packaged consumers, then explicitly select a runtime already
installed on the host. The example identifier below records the local run:

```sh
python3 Tools/verify_local_delivery.py --report .build/reports/local-delivery.json
python3 Tools/verify_ios_runtime.py \
  --delivery-report .build/reports/local-delivery.json \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --report .build/reports/ios-runtime.json
python3 Tools/verify_ios_runtime.py \
  --delivery-report .build/reports/local-delivery.json \
  --report-check .build/reports/ios-runtime.json --negative-controls
python3 Tools/test_ios_runtime.py
```

The qualifier checks the fresh delivery receipt against current source/example/
packaging-tool hashes, app binary bytes, actual packaged catalogs, SDK privacy
manifest and Bundle identifier. It records installed runtime/version/build/
architecture and the booted device's membership in that runtime. It creates a
unique simulator, installs only this local app, runs its existing `--qualify`
entry point, requires the app's successful output, then shuts down and deletes
only the device it created. Runtime downloads and physical-device installation
are outside this tool. Commands have bounded timeouts; cleanup is attempted even
when boot, install or app execution fails. Failed cleanup prevents a passing
receipt. The tool also refuses source changes and stale packaged evidence.

Saved checks need no Simulator service or compiler, but still require the
retained app/delivery receipt and matching checkout bytes. Nine stdlib-only
Python tests use explicitly synthetic receipts to check refusals; they add no
runtime evidence. Ten controls reject false minimum-OS claims, stale sources,
changed binaries, omitted/failed launches, absent app output, wrong runtimes,
unowned devices, missing cleanup and unknown fields. Source, runtime and complete
command outputs are retained locally; there is no authentication claim for a
saved receipt supplied by another party.

CI runs the offline tests on both configured compiler tracks. A manual workflow
may supply an installed `ios_runtime` identifier to execute the consumer on its
current arm64 runner. An unavailable runtime or incompatible host fails this
requested step. Ordinary workflows do not silently count an unrequested simulator
run as executed. Hosted execution remains unverified until an actual run occurs.

## Local evidence and limits

The current receipts are `.build/reports/m8l-local-delivery.json`,
`m8l-ios-runtime.json`, `m8l-ios-runtime-check.json` and
`m8l-qualification-summary.json`. Both SwiftPM resource consumers (Swift 6/default
MainActor and Swift 5 caller language mode) execute; macOS, iOS simulator and iOS
device apps compile/package, with actual catalog/privacy bytes and deployment
floors verified. The packaged macOS app executes too. Only the iOS simulator app
is installed by the new qualifier. Temporary simulators are deleted after use.

The simulator runs iOS 26.5 build 23F77; it does not establish iOS 15 behavior,
physical-device execution or full iOS conformance-corpus parity. Swift 6.2,
macOS 12, Intel and hosted-CI execution remain separate gates. A future run on
exactly iOS 15.0 can record that this consumer executed at its declared floor;
that evidence alone still cannot certify the entire library or other workloads.
The iOS CLI binaries inspected by `verify_deployment.py` remain compile-only.
No production API/source, HTTP loader or external runtime dependency changes.

M8M subsequently runs [all standalone qualification commands](IOS-CONFORMANCE.md)
on the current simulator. Its fresh receipts include the development fixture
changes needed for an application sandbox; the M8L source stamps above remain
historical. Minimum-version, physical-device, Intel and hosted-CI gates remain.
