# Concurrency and Thread Sanitizer qualification

`DefaultStrings` is immutable and has checked `Sendable` conformance. Concurrent
calls can share an instance and select different locales through per-call
`TranslationOptions`. Catalog compilation belongs to construction; lookup
attempts, rendered values, generated fragments, bidi conversion and callback
snapshots belong to each invocation. The catalog supplier runs at construction.
Locale suppliers, resolvers and other runtime callbacks run synchronously when
their operation requires them.

Callbacks can reenter the same runtime. Callers synchronize mutable callback
state and release their own locks before reentry. Each concurrent load uses its
own caller stream and parsing session; aggregate limits and warnings belong to
that load. A caller-owned stream remains open after loading.

## M8O stress coverage

Four public-API XCTest methods add 992 parallel worker iterations:

- 512 workers use one runtime across English, French, Arabic and Japanese. They
  check independent caller values, UTF-16-distinct NFC/NFD keys, explicit bidi
  overrides, Double π formatting, cardinality of two, exact key inspection and
  retained negotiated-match identity.
- 256 workers use two instances with the same catalog and opposite phonetic
  resolvers. Repeated generated placeholders reuse their per-call result;
  resolver calls retain their own terms and instance context.
- 128 workers trigger fallback observers that reenter the same runtime. Outer
  and nested results retain their own values and attempts; throwing per-call
  failure handlers retain the original error object and caller inputs.
- 96 workers independently load the same two immutable local files with exact
  aggregate byte/file/warning budgets. They reenter parsing from warning
  callbacks, verify an adjacent byte-limit failure and parse their own streams
  without losing ownership or source attribution.

All four methods pass normally. Thread Sanitizer also runs the existing runtime
semantics, preferred-language and local-loader classes. On this Swift 6.4 arm64
macOS 27.0.1 host, all 37 selected methods are accounted for: 36 pass and the
existing invalid-UTF8 filename fixture is skipped because that filesystem
operation is unavailable (errno 92). No sanitizer problem is reported.

An intentionally racy C program is a separate development control. The selected
Apple sanitizer must identify its shared `unprotected` variable and source,
then exit 66. It lives outside the SwiftPM test target and consumer products.
The receipt checker also inspects `DefaultStrings`' actual object for sanitizer
read/write calls and the actual XCTest binary for its sanitizer runtime link.
The current normal object and test binary are both refused. Nine altered logs
or detector results are refused, including missing/repeated methods, an
unapproved skip, a test failure, a race report and missing control attribution.

## Reproduction

Run from the repository root, using a separate sanitizer build directory:

```sh
mkdir -p .build/reports
export TSAN_OPTIONS=halt_on_error=1:abort_on_error=0:exitcode=66:report_bugs=1
python3 Tests/ConcurrencyControls/check_sanitizer.py --snapshot .build/reports/sanitizer-inputs.json
xcrun clang -g -O1 -fsanitize=thread Tests/ConcurrencyControls/ThreadSanitizerRace.c -o .build/ThreadSanitizerRace
control_status=0
.build/ThreadSanitizerRace > .build/reports/sanitizer-positive-control.log 2>&1 || control_status=$?
test "$control_status" -eq 66
swift test --sanitize thread --scratch-path .build/thread-sanitizer \
  --filter 'ConcurrencyTests|RuntimeSemanticsTests|PreferredLanguageChooserTests|LocalCatalogLoaderTests' \
  > .build/reports/thread-sanitizer.log 2>&1
python3 Tests/ConcurrencyControls/check_sanitizer.py --check \
  --input-snapshot .build/reports/sanitizer-inputs.json \
  --scratch-directory .build/thread-sanitizer \
  --test-log .build/reports/thread-sanitizer.log \
  --control-log .build/reports/sanitizer-positive-control.log \
  --control-exit-code "$control_status" \
  --report .build/reports/thread-sanitizer.json
```

The Swift test command must exit 0. Source and test inputs are recorded before
compilation and revalidated afterward. The checker requires every selected
method's actual start and terminal observation, allowing only the named
filesystem fixture to skip. It parses both macOS XCTest output formats; the
current Swift build engine does not produce the requested xUnit file, so an
absent XML file cannot serve as evidence. Reports retain exact passing/skipped
IDs, input/log/artifact hashes, instrumentation output and compiler/host context.

CI runs this recipe on all three configured compiler/architecture tracks and
retains its logs and JSON report. No hosted execution is claimed. Local evidence
is `.build/reports/m8o-thread-sanitizer.json`,
`.build/reports/m8o-sanitizer-refusal-controls.json` and the scoped summary
`.build/reports/m8o-qualification-summary.json`.

This is finite workload coverage on the recorded macOS host. It does not prove
universal race freedom, application callback safety, minimum compiler/OS, iOS
sanitizer behavior or Intel execution. Runtime sources, API, external dependency
count, corpus dispositions and HTTP scope are unchanged. Sanitized products
remain in their separate development directory; consumer builds use the normal
source targets. The existing M8N SDK/native/iOS evidence still matches current
runtime and qualification-tool inputs.
