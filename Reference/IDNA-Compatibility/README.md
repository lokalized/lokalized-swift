# Manifest URL compatibility data

This directory is a pinned development snapshot of the canonical data in
`lokalized-spec/tools/url_oracle/reference/IDNA-Compatibility/`. The portable
input recipes are vendored in `Tools/URLOracle/`; native Swift emitters remain
in `Tools/`. [Snapshot ownership and sync](../URL-ORACLE.md) describes the checks.

This separately pinned profile preserves the behavior of the existing JavaScript
port's URL runtime: Node **26.5.0**, binary SHA-256
`87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511`,
which reports Ada **4.0.0**. Node's Unicode version does not identify its URL
parser's validity property data.

`property-profile.json` contains property data extracted from `src/validity.cpp`
in the [official Node v26.5.0 Ada source](https://raw.githubusercontent.com/nodejs/node/v26.5.0/deps/ada/ada.cpp).
That complete source has SHA-256
`ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4`.
The input archive preserves the mark and virama scalar sets, joining memberships,
and named Bidi ranges. Its SHA-256 is
`84ae2c73b06823e54716dff80f7f539e588a676e7ff8529424046fe34f7a1098`.
The extracted data is distributed under Ada's MIT license, reproduced in
`LICENSE-MIT.txt` and in the generated source. Copyright 2023 Yagiz Nizipli and
Daniel Lemire.

**The source is data provenance, not proof of the binary's algorithm.** Actual
compatibility expectations are measured from the pinned Node binary. For example,
the downloaded source's Bidi loop predicts acceptance of `1ב`; the frozen binary
rejects it. No upstream executable implementation is vendored, and no consumer
build downloads or parses this archive. `Tools/generate_idna_compatibility.py`
creates original compact static lookups from the frozen data using only the Python
standard library.

The profile intentionally differs from current Unicode properties. Among Unicode
17 mapping-valid or deviation scalars, it differs on 247 mark classifications,
8 viramas, 341 joining memberships, and 15,676 Bidi classifications. Those counts
include newly assigned characters absent from the legacy tables. The development
recipe `property_discriminant_inputs(reference_directory)` creates 32,203 URLs
that exercise every differing scalar in meaningful positions. Their expected
results come from the frozen binary, not from its source algorithms or Swift.

UTS #46 mapping uses the separate
[official Unicode 17 profile](../Unicode-17.0.0/README.md). The independent
`PinnedNFC` implementation also uses that profile and passes every official NFC
conformance equation. Manifest URL normalization instead preserves the distinct
runtime behavior described below. These compatibility tables are used only for
manifest URLs. This scope does not claim strict Unicode 17 IDNA registration
conformance or change the existing identifier Unicode 15 profile and runtime
identity fields.

## Normalization and its global quick check

`normalization-profile.json` separately preserves 388 legacy combining-class
ranges, 2,061 flattened canonical decompositions, and 941 composition pairs
extracted from `src/normalization_tables.cpp` in the same pinned Node source. The
MIT notice above applies to this data too. The generated lookups and Swift
normalization algorithm are original implementations.

The actual URL runtime takes a global fast path. It preserves precomposed
characters when existing marks are ordered and no existing pair triggers
composition. A singleton decomposition, disordered marks, an applicable pair,
or certain adjacent Hangul contexts triggers decomposition of the entire input
before ordering and composition. For example, `é` followed by U+0323 remains
unchanged alone, while adding another label containing `a` followed by U+0301
causes the first label to become U+1EB9 followed by U+0301. Likewise, a
precomposed Hangul LV syllable followed by trailing Jamo remains separate alone
but can compose when another label triggers the slow path. Both mapped-domain
normalization and decoded ACE validation use this independently measured
profile.

The [official Ada 4.0.0 source](https://raw.githubusercontent.com/ada-url/ada/v4.0.0/src/ada_idna.cpp)
explains this quick check. It is an explanation source, not vendored executable
code. The pinned Homebrew Node build dynamically loads its Ada engine;
`oracle-runtime-lock.json` identifies the loaded engine images as well as the
Node executable. Archived expectations come exclusively from that runtime.
The development recipe `normalization_discriminant_inputs(reference_directory)`
creates 17,062 URLs covering every stored composition and decomposition,
combining-class differences, all Hangul L/V combinations, and forced slow paths
across label boundaries.

Regeneration and verification are offline:

```sh
python3 Tools/generate_idna_compatibility.py --write
python3 Tools/generate_idna_compatibility.py --check
python3 Tools/verify_idna_compatibility.py --check
python3 Tools/generate_idna_normalization_compatibility.py --write
python3 Tools/generate_idna_normalization_compatibility.py --check
python3 Tools/verify_idna_compatibility_normalization_tables.py --check
```

Changes to this profile require a reviewed compatibility-baseline update with
fresh independent observations; regenerating Swift cannot silently adopt a
different Node release or device Unicode implementation.
