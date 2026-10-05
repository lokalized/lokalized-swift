# Changelog

## 1.0.0 - 2026-10-05

First stable release of Lokalized for Swift. Requires Swift 6.2+ in Swift 6
language mode and declares iOS 15+ and macOS 12+ deployment targets. The library
has zero external runtime dependencies and no build plugins.

- Share JSON catalog syntax with the Java and JavaScript ports, including
  expressions, recursive fragments and all ten language-form axes.
- Evaluate cardinal, ordinal and range plural rules with exact numeric operands
  and compiled CLDR 48.2 data. Ship pinned locale, IANA and Unicode data.
- Provide immutable translation configuration, application-supplied locale
  callbacks, locale negotiation, Apple preferred-language selection, bidi
  isolation, structured results and fallback/failure observers.
- Load catalogs synchronously from text, Data, caller-owned streams, local files,
  directories, Bundles and explicit resource maps with bounded parsing/loading
  limits. Applications own remote acquisition; the library provides no HTTP loader.
- Parse and validate manifests, compute catalog identity and plan references
  without performing catalog I/O. Follow shared manifest-normalization 1.1.0,
  diagnostic-text 1.1.0, exact-identifier and fallback-observer profiles.
- Package an Apple privacy declaration, complete third-party data notices,
  executable macOS/iOS examples and DocC API documentation.

Swift's typed values, error representations and Bundle loading adapt the Java
and JavaScript APIs to Apple platforms. See
[API mappings](Documentation/API-MAPPING.md) and
[native compatibility contracts](Documentation/NATIVE-CONTRACTS.md) for the
declared differences. [Deployment evidence](Documentation/DEPLOYMENT.md)
distinguishes compilation for an OS deployment target from execution on that OS.
