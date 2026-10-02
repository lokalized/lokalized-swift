# Catalog identity

M7A provides synchronous `LocalizedStringLoader.computeCatalogIdentity`, `catalogIdentityBytes`, and `catalogIdentityInputFor`. They perform no I/O. `CatalogIdentity` is an immutable claim with exact UTF-16 equality/hash for both fields; possession of a well-shaped fingerprint does not prove that catalog bytes were loaded or verified.

The fingerprint is the full lowercase hexadecimal SHA-256 of this precise projection:

```json
{"catalogVersion":"v1","formatVersion":1,"localeToSha256":{"en":"<64 lowercase hex digits>"},"resolvedFallbackLocale":"en","tiebreakerLocalesByLanguageCode":{}}
```

`CatalogIdentityInputV1` carries only these five fields. Catalog version, elected fallback, file digests and ordered tiebreaker arrays affect the identity. Base/per-file URLs, decoded sizes, the fingerprint itself and all seven runtime data-identity fields are excluded. Those runtime fields still require separate compatibility validation before planning. See [manifest validation](MANIFEST-VALIDATION.md).

The original narrow canonicalizer follows [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785): object names sort by UTF-16 code units, arrays retain order, strings use minimal JSON escaping, and text retains its authored Unicode spelling. UTF-8 output has neither BOM nor trailing newline. NFC/NFD names remain distinct through `ExactString`; supplementary characters sort by their surrogate code units. Slash and U+2028/U+2029 remain literal. Only the fixed numeric value `1` enters this projection, so this API is not a general floating-point JCS serializer. Swift's valid `String` carrier cannot represent a lone UTF-16 surrogate; those JS-only malformed identity inputs remain explicitly pending in the native contract report.

The implementation uses Apple's system CryptoKit SHA-256. Independent native qualification checks the published empty-string and `abc` known answers, hand-authored canonical bytes, field perturbations, map order, exact Unicode, escaping, invalid digests and identity equality/hash. The frozen [JS contract archive](MANIFEST-CONTRACT.md) additionally checks actual reference canonical bytes, byte counts and digests. Consumer builds need no Node, Python, reference archive or external package.

`catalogIdentityInputFor` copies file digest keys and tiebreaker arrays and resolves the configured fallback using the pinned manifest locale helpers. It does not validate the claim; malformed tag/election input leaves the authored fallback for subsequent semantic validation. As in pinned JS, it sets projection format version 1. Standalone identity map names are arbitrary exact strings; manifest validation separately enforces data-known locale tags and complete tiebreaker orders.

The pinned JS normalizer is not idempotent for some undetermined/private-use spellings. For example, `UND-x-foo` first becomes `und-x-foo`, then becomes `x-foo`. The identity helper re-normalizes the elected fallback, and planning doors repeat validation/normalization as the reference does. Paired frozen vectors preserve this behavior and its possible later fingerprint refusal. This is reference compatibility evidence, not a proposed rule for a future shared standard; correcting it requires coordinated contract versioning across ports.

Swift's typed identity door uses `ConfigurationError(.invalidArgument)` where JS uses `TypeError` or `RangeError`. The differential adapter records native observations and explicitly reports semantic error projections separately. Typed dictionary inputs use deterministic UTF-16 validation order; the ordered decoded manifest door preserves JS declaration order. Dynamic JS identity shapes that the typed Swift input cannot carry are inventoried without fabricated execution.

Identity detects disagreement with supplied claims. It does not verify catalog bodies or authenticate manifests. HTTP acquisition, verified-network records, cancellation and publishing are outside the Swift runtime scope; applications own those workflows.
