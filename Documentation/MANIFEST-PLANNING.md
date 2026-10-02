# Manifest planning

M7A implements manifest schema validation, catalog identity and deterministic planning. It performs no catalog I/O. Network loading, integrity-checked transport, partial failures, cancellation and loaded snapshots remain later work. The production library has no package dependencies.

`LocalizedStringLoader.localeConfigurationForManifest(_:loadingOptions:)` returns the resolved authored fallback, every declared normalized file tag in exact UTF-16 order, and only the manifest's explicit tiebreakers. It does not synthesize singleton language orders into this returned configuration or into catalog identity.

`LocalizedStringLoader.chain(_:lookupLocale:loadingOptions:)` plans from the caller's locale through the per-key candidate walk. It retains absent ancestors, chooses likely-script-compatible authored catalogs, applies tiebreakers, adds the fallback, rewrites candidates to canonically equivalent backed tags, and deduplicates the elected tags in first-use order. An already encountered fallback keeps its earlier position. This operation does not negotiate a diagnostic selection before constructing the walk.

`LocalizedStringLoader.fetchSet(_:lookupLocale:loadingOptions:)` filters that walk to declared files and returns immutable `FetchEntry` values. Each entry has a locale, an already resolved absolute `url`, its declared `sha256`, and optional `expectedDecodedBytes`. An explicit zero byte count stays distinct from an omitted count. Different locale entries sharing one URL remain distinct entries. A future transport must use the resolved URL without resolving it again.

```swift
let manifest = try LocalizedStringLoader.parseStringsManifest(manifestBytes)
let configuration = try LocalizedStringLoader.localeConfigurationForManifest(manifest)
let candidates = try LocalizedStringLoader.chain(manifest, lookupLocale: "fr-CA")
let files = try LocalizedStringLoader.fetchSet(manifest, lookupLocale: "fr-CA")
```

Each public planning door revalidates all manifest structure, build/data identity, authored locale coverage, tiebreakers and catalog fingerprint under the supplied loading options before looking at the requested locale. A lowered file limit therefore wins over malformed lookup input. The internal `wholeManifestPlan` projects every validated file in normalized exact tag order; it is reserved for a future complete-catalog loader.

The manifest door follows serialized JS locale semantics. Locale normalization uses pinned JDK tag parsing and rendering; CLDR aliases are used for election and candidate resolution, without replacing every ingress tag by its alias. The planner accepts syntactically valid lookup tags such as unknown `zz-AA` and the non-rebuildable serialized `en-x-lvariant-NY`. Case-distinct known authored variants such as `en-FONIPA` and `en-fonipa` can coexist when their resolution order is explicit. The direct native matcher keeps its existing stricter `LocaleTag` construction contract.

Actual source operations are retained where JDK projection is not idempotent. For example, `UND-x-foo` first renders as `und-x-foo`, while a second projection renders as `x-foo`. The pinned JS public chain projects the lookup before its candidate engine projects again; `fetchSet` revalidates its manifest before invoking public `chain`. These repeated operations remain observable instead of being optimized away.

## URL qualification scope

Manifest bases and resolved entries permit `http:`, `https:` and `file:`. Raw base and entry spellings remain in the validated manifest and do not enter catalog identity. Planning serializes the resolved URL: it folds scheme and ASCII host casing, removes default ports, resolves relative references and dot segments, retains encoded path separators, and applies component-specific UTF-8 percent encoding. A base without a final slash replaces its final path segment when resolving a relative filename.

The resolver is original Swift code following the [WHATWG URL Standard](https://url.spec.whatwg.org/), with scalar/byte separators rather than Swift grapheme-cluster counting. IPv4 number forms and IPv6 serialization are parsed directly; host `Foundation.URL`, host ICU/IDNA data and Darwin address parsers do not determine their behavior. Other schemes are recognized for the manifest validator's scheme diagnostics and are not a general-purpose URL API.

Full WHATWG URL parity is unfinished. Unicode special-host domain processing and every ASCII hostname label beginning `xn--` are explicitly unqualified because pinned UTS46/IDNA processing is not yet implemented. They report `URL feature is not yet qualified: unicodeDomain` or `punycodeDomain`; the developer adapter records these input-defined capabilities as pending. This is an unfinished native capability, not a change to the broader JS manifest wire contract. Unicode path, query, fragment and credential text remains supported by UTF-8 percent encoding. Passing the matrix below does not claim complete coverage of the WHATWG web-platform test suite.

## Reproducible evidence

`Reference/manifest-contract-vectors.json` records the separate pinned JS manifest contract. Java has no manifest or URL fetch-plan API; its candidate-walk behavior supplies the locale core, while the manifest projection uses the JS oracle.

`Reference/manifest-url-goldens.json` contains a separately authored 3,479-input URL matrix observed with Node's built-in `URL` implementation, Node `v26.5.0`. The archive pins the Node binary SHA-256, input recipe SHA-256, every row ID, every actual oracle observation, and each authored unqualified host capability. It covers relative bases, encoded dot segments, credentials, ASCII domain and port variants, decimal/octal/hex IPv4, IPv6 compression and embedded IPv4, Windows drive and UNC file URLs, Unicode separators, Unicode component text and malformed inputs.

Local qualification compares the actual resolver with all 3,250 qualified oracle observations, with zero differences. The other 229 rows remain explicitly pending Unicode/punycode host capability; the tool verifies their actual input classifier rather than counting them as parity successes. The LF-terminated sorted ID digests are:

- Qualified: `6cacf8b9a67eff0820f9a1c7ac2e372d78f9af5647d6b0b5f2fec07f25d095ec`.
- Pending: `6090d605bc5c52cbbab21d81ae3ad12135d2a9017f372cd66f10d9b9e44e1f50`.
- Complete archive: `5aeef3e07d1a1f0464baf4f0748d6902cebe4a61964cb1398419d1eb89ddd6fd`.

```sh
python3 Tools/verify_manifest_urls.py --check > /private/tmp/manifest-url-report.json
swift run LokalizedConformance --manifest-urls
```

Normal checking requires only Python's standard library and the available Swift compiler. It compiles the actual URL source in an isolated writable temporary directory and needs neither Node nor sibling repositories. The native audit independently pins the archive, checks every ID and capability partition, and refuses tampered bytes before performing observations. Focused native tests also exercise embedded NUL in IPv6, 10,000 leading port zeroes, combining marks after URL separators, exact locale election, shared URL entries, optional byte counts and error precedence.

An intentional oracle refresh is explicit:

```sh
python3 Tools/verify_manifest_urls.py --refresh-goldens --node /absolute/path/to/node
```

A refresh replaces the developer archive and prints its new SHA-256 for review. Updating the compiled digest and provenance pins is a separate review step. No oracle archive or JavaScript engine is consumed by the production library.
