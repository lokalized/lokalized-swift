# Manifest URL and Unicode domain processing

M7B1 completes the formerly pending Unicode/punycode domain capability in the synchronous manifest resolver. Validation accepts Unicode hosts and planning serializes their ASCII form: `https://bücher.example/catalogs/` becomes `https://xn--bcher-kva.example/catalogs/`. Authored base/file URL spelling remains in the validated manifest claim. Relative references, percent-decoded UTF-8 hosts, numeric IPv4 and IPv6 continue through the existing original parser.

Mapping is pinned to **Unicode 17.0.0**. The URL-specific normalization and auxiliary mark, virama, joining and bidi properties use a separate recorded Node `v26.5.0`/Ada `4.0.0` compatibility profile: the oracle's auxiliary tables are older or incomplete even though its mapping data is Unicode 17, and its normalizer has measured departures from canonical NFC. These policies do not change identifier Unicode 15.0, CLDR/IANA data, the seven manifest runtime identity fields, or catalog fingerprint bytes. Device Foundation URL/ICU/Unicode properties do not determine host acceptance or normalization. No external runtime package, build plugin, generator, downloaded resource, Node executable or reference archive is required by a consumer. Compact immutable tables are compiled into the library, with their full Unicode/Ada license notices embedded in source.

For non-ASCII input, the original processor maps and removes scalars using the pinned table, applies the separately pinned URL normalization profile, splits mapped dot separators, decodes and validates ACE labels without remapping their decoded contents, checks the compatibility profile's leading marks and joiner contexts, and encodes non-ASCII labels with an original overflow-checked RFC 3492 codec. Successfully validated ACE labels preserve their ASCII spelling. The mapping stage uses [Unicode UTS #46 revision 34](https://www.unicode.org/reports/tr46/tr46-34.html). Punycode follows [RFC 3492](https://www.rfc-editor.org/rfc/rfc3492).

The manifest URL profile uses nontransitional processing, permits the URL profile's ASCII punctuation and hyphen positions, and does not impose DNS registration length limits. An entirely ASCII input is lowercased without ACE validation, including malformed `xn--` labels; this matches the pinned oracle and the [URL Standard domain parser](https://url.spec.whatwg.org/#idna). A Unicode-containing decoded domain must fit the oracle's 16,384-byte UTF-8 input limit before mapping, including ignored scalars; literal ASCII hosts bypass this limit, while percent-bearing hosts enforce it after decoding even when the result is ASCII. ACE decoding, compatibility normalization and scalar validity must succeed, and Punycode arithmetic stays within the oracle's signed 31-bit ceiling. Forbidden domain code points and empty final hosts are rejected, and numeric hosts still undergo IPv4 parsing after mapping.

For example, an otherwise composed domain preserves `é` followed by U+0323, while canonical Unicode NFC produces `ẹ` followed by U+0301. A later composable or disordered sequence can fail the oracle's global quick check and trigger decomposition across the entire domain, including earlier labels. Existing Hangul syllables followed by Jamo also participate in this observed fast/slow distinction. The same compatibility normalization is used when validating decoded ACE labels. This is retained as an observed oracle behavior, with separate data and tests from the complete canonical NFC utility.

The joiner and directional rules originate in [RFC 5892 Appendix A](https://www.rfc-editor.org/rfc/rfc5892#appendix-A) and [RFC 5893](https://www.rfc-editor.org/rfc/rfc5893), but this pinned Node oracle has measurable departures. Its first joiner determines the label's contextual result and bypasses later joiners and bidi checks; ZWNJ searches the entire prefix/suffix for a joining direction, even across nontransparent characters. Ordinary scalar validity still precedes that shortcut. Labels without joiners check RTL start/end, allowed directional classes and separation of European/Arabic numbers; LTR labels such as `1é`, `_a` and `a-` remain permitted elsewhere in the domain. These observations are explicitly frozen as compatibility behavior, rather than advertised as strict UTS #46 conformance. Correcting them requires a coordinated shared URL-policy/oracle decision. This internal utility is scoped to manifest special URLs and is not a public general-purpose IDNA or URL API.

The original 3,479-row URL archive is unchanged. Its 229 historical Unicode/punycode capability labels now describe coverage, and every row is compared with its recorded outcome. A separate 56,513-row archive observes 6,389 scalar-compatible Unicode 17 `IdnaTestV2.txt` inputs through the pinned Node URL oracle, plus 32,203 property discriminators, 17,062 normalization discriminators and 859 authored URL boundaries. The latter cover mapping, joiners, bidi, ACE, DNS lengths, relative bases, Unicode versions, BOM-preserving strict UTF-8 decoding, the decoded Unicode input byte boundary and the oracle's signed 31-bit Punycode arithmetic ceiling. Those URL expectations are actual oracle results, independently frozen from Swift; they are not UTS #46 test status columns rewritten to fit the implementation. Two official source strings containing lone UTF-16 surrogates cannot be represented by Swift `String` and are explicitly excluded from that archive's scalar inventory.

The independent Unicode 17 canonical NFC utility compares all five NFC equations for each of Unicode's 20,034 normalization rows and scalar identity outside Part 1: **1,195,148 checks**. Long unordered combining-mark runs retain stable canonical ordering with bounded sorting complexity. Localization keys continue to preserve exact authored scalar spelling; the URL compatibility normalizer is used only for IDNA, and the canonical utility remains separately qualified.

Normal development checks are offline:

```sh
python3 Tools/generate_idna_tables.py --check
python3 Tools/verify_idna_tables.py --check
python3 Tools/generate_idna_compatibility.py --check
python3 Tools/generate_idna_normalization_compatibility.py --check
python3 Tools/oracle_runtime.py --check
python3 Tools/verify_idna_compatibility.py --check
python3 Tools/verify_idna_compatibility_normalization_tables.py --check
python3 Tools/verify_manifest_urls.py --check
python3 Tools/sync_url_oracle.py --check
python3 Tools/test_idna_archive.py
python3 Tools/verify_idna_urls.py --check
python3 Tools/verify_idna_normalization.py --check
swift run LokalizedConformance --manifest-urls
swift run LokalizedConformance --idna-normalization
```

Reference source, table, input-recipe, oracle-executable, loaded URL/Unicode engine and output digests are checked before qualification. The explicit oracle refresh verifies the executable and five actual loaded engine images before and after observations; normal checks use their frozen metadata offline. Reports enumerate exact qualified IDs and digests, retain actual failures, and refuse altered receipts. This evidence covers the declared resolver/profile and archived inputs; it does not certify the entire WHATWG web-platform suite. URL processing remains a pure manifest compatibility utility. The October 2 scope decision excludes HTTP loading and its transport/verified-result machinery from Swift. Applications own acquisition; M8 release qualification is next.

The developer fixture is stored as `Reference/manifest-idna-goldens.json.gz`: **731,845 bytes**, decoding to the original **19,308,094 JSON bytes** without changing any of its 56,513 cases or the decoded archive digest. Both readers require a single complete gzip member with a valid CRC/size trailer, refuse trailing data or concatenated members, and enforce separate 2 MiB stored / 32 MiB decoded limits before JSON parsing. Swift's conformance support uses the Apple SDK's system zlib; Python tools use only the standard library. The production `Lokalized` target and its dependency list are unchanged, and these limits do not affect production manifest budgets. Explicit golden refreshes write gzip with no filename and a zero timestamp and print both decoded and stored digests for review. `archiveSHA256` in existing qualification reports continues to identify the decoded JSON, so earlier evidence identities remain valid. To inspect the fixture, run `gzip -dc Reference/manifest-idna-goldens.json.gz`.

The canonical archive is now owned by `lokalized-spec` at `generated/url-oracle/manifest-idna-goldens.json.gz`. Its portable input recipe, pinned Unicode/Ada data and oracle/profile provenance live under `tools/url_oracle`, with `generated/url-oracle/manifest-idna-lock.json` recording the shared snapshot. Swift vendors twenty pinned artifacts (archive, shared lock, six Python modules and twelve data/license files) for independent offline checks. The Swift native emitter/probe adapters call that vendored recipe; they no longer author these cases or refresh the oracle archive. `Tools/sync_url_oracle.py --check` verifies the local snapshot without sibling repositories, and `--check-source --source ../lokalized-spec` verifies it against the canonical checkout. Use `--sync --source ../lokalized-spec` only after reviewing changes to the pinned snapshot. Shared ownership preserves the recorded Node URL compatibility profile and all expectation identities.

Final M7B1 evidence is `.build/reports/m7b1-qualification-summary.json`. All 59,992 frozen URL observations and the separate 50,030-input review pass; all fifteen URL report corruption controls reject altered receipts. The principal frozen digests are:

| Evidence | SHA-256 |
| --- | --- |
| New 56,513-row URL archive (decoded JSON) | `7f84ecb403b6e772f00dfa851d7de42e6d9556998dbb0b47feca23c8fff380db` |
| Stored gzip archive | `325a22caa753d399319dd0572d99f159042ca32acdae9548d5db87a628ba7603` |
| Sorted new qualified IDs | `c9c6944a8e63b3d92680f19fd53c3a1f4ee871db10efca26183a2ead699a9432` |
| Compatibility normalization profile | `9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c` |
| Loaded oracle-engine lock | `e0fa1af12b31b3750be894db9a892775b672e5d2577923b84e7c83154130cb1d` |
