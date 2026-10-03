# Source distribution and notices

Consumer builds use the checked-in Swift sources and Apple's SDKs. The root
`Package.swift` declares zero external package dependencies and no plugins.
The only library resource is `PrivacyInfo.xcprivacy`; CLDR, IANA and Unicode
tables compile directly into the library.

`LICENSE`, `NOTICE`, `THIRD-PARTY-NOTICES.md` and `Licenses/` accompany source
distributions. The complete CLDR/Unicode/Ada notices are independently pinned
to the reviewed upstream bytes. The Unicode 15.0 notice preserves the complete
original runtime document. Keep these notices in associated documentation
when redistributing the library or a binary containing its derived data.
SwiftPM does not automatically put root license documents in an application's
resource bundle. The notices remain ordinary distribution documentation;
they do not introduce a runtime resource lookup or dependency.

## Local archive rehearsal

Run from the repository root:

```sh
python3 Tools/test_source_package.py
python3 Tools/source_package.py --check
python3 Tools/verify_package.py --offline-build \
  --source-archive .build/distribution/lokalized-swift-source.tar.gz \
  --report .build/reports/source-distribution.json
python3 Tools/source_package.py \
  --archive-check .build/distribution/lokalized-swift-source.tar.gz
```

The archive records the **current working tree**, including intended uncommitted
files in its explicit allowlist. It uses no Git commands and creates no commit,
tag, or published release. Before a real release, the user must commit the
reviewed work and tie the release to that resolved revision. This archive is
an executable packaging rehearsal, not certification or a versioned release.

The full source package preserves the original manifest and includes `Sources/`,
`Tests/`, `Reference/`, `Tools/`, `Documentation/`, `Examples/`, `Licenses/`,
`.github/`, the root README/notices and Git text settings. This retains the
conformance executable, offline development checks and native consumer examples.
The large IDNA oracle remains its pinned **compressed** development archive;
the uncompressed JSON is refused. Neither archive is a runtime library resource.

The allowlist excludes Git metadata, build products, SwiftPM caches, Python
bytecode, Xcode user settings, node_modules, Finder files and `Package.resolved`.
Symlinks and nonregular source files are refused. Archive entries have sorted
paths, fixed owners/timestamps and normalized permissions; gzip has no source
filename or wall-clock timestamp. Identical bytes and executable flags produce
identical archives on the same Python/zlib toolchain. Cross-version compression
output is not claimed to be identical; the per-file SHA-256 inventory remains
the source identity.

Before extraction, the checker requires exact names, sizes, permissions and
content digests, rejects duplicate or missing members and path traversal, and
validates every member as a regular file. It writes into a fresh destination
without using `tarfile.extractall`. Nineteen offline controls cover roundtrip
identity/determinism, exclusions, missing/changed notices, symlinks, privacy and
IDNA packaging, changed inputs, omitted/duplicate/corrupt members, unsafe paths,
metadata and reused extraction destinations.

## Consumer qualification

`--offline-build` now consumes that archive. It extracts a fresh package and
asks the selected Swift toolchain to inspect the **extracted** manifest's
dependencies, plugins, tools/language version and platform declarations.
It verifies the packaged notices, then removes actual `Reference/` and `Tools/`
directories before compiling the package and a separate local-path consumer.
The declared test/support sources remain present so the original manifest is
unchanged. Running conformance or XCTest separately still needs its archived
development inputs; ordinary library builds do not.

The consumer compiles and executes public catalog/model, exact number/plural,
locale/range/matching, translation, callback/reentry, bidi/display and pure
manifest/Unicode-domain APIs. Its executable is inspected for the macOS 12
deployment floor, Apple/system runtime links and absence of test frameworks.
The built SDK resource bundle must contain the exact source privacy declaration.
No resolver file may appear. Input identities are checked again after execution.
The retained JSON receipt includes the complete source inventory, archive digest,
actual compiler, manifest observations, consumer binary digest and privacy digest.
Temporary extracted packages and build products are removed after qualification;
the requested archive and receipt are retained under `.build/`.

This establishes current-host source distribution and consumer execution. It
does not measure network traffic or execute minimum OS versions. Swift 6.2,
native Intel, iOS 15/macOS 12, physical-device and hosted CI execution remain
separate gates. [Deployment](DEPLOYMENT.md), [packaged Apple resources](APPLE-LOCAL-DELIVERY.md),
[iOS conformance](IOS-CONFORMANCE.md) and [concurrency](CONCURRENCY.md) retain
their own evidence and scope. The original corpus remains 2,197 passed / 184
pending; packaging adds no behavioral case passes.
