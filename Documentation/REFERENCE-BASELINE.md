# M0 reference baseline

`Reference/` is a development-only, self-contained snapshot of the reviewed shared
artifacts. It provides fixed inputs for the Swift conformance runner; copying the
artifacts implements no translation behavior and establishes no passing Swift cases.
Consumer builds must not fetch these files, run an oracle, or execute a generator.

The archive uses the existing Java **3.1.0** behavioral recording, even though the
reviewed Java feature reference is **3.1.1**. Its 2,381 cases use 586 fixtures:
2,155 `requiredPortableIds`, zero `requiredImplementationIds`, and 226
`informationalIds`. Corpus version is 1.1.0. The full input file is 4,270,021 bytes;
its SHA-256 is
`1eb74caf8524c0a3b33dca99addb268c86b64eb8321fac03257474ddaa3c9753`.

## Files and provenance

[`baseline.json`](../Reference/baseline.json) records the resolved source commits,
source hashes, per-file byte counts/SHA-256 values, corpus inventory, CLDR/IANA
identities, licensing paths, known regression, and candidate native mappings.
Every archived input is copied byte-for-byte. The checker also carries independent
pins, so changing an artifact and its manifest checksum together still fails.

| Source | Pinned reference |
|---|---|
| Java corpus oracle | 3.1.0, `63b63e47c982f7a87873c52ac2289cc0392f3329`; source SHA-256 `db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0` |
| Reviewed Java features | 3.1.1, `491346ba50df65e1e51791f21246ff8bc47e44e9`; source SHA-256 `dab6dc8028a27605eff9ef131841bbe517ed30977bcb3514083eaf62c1790a5e` |
| Reviewed JS API/transports | `617670da887b0c684e2589882447b6b93297f2f7`; package metadata still says 1.0.0-rc.2, so the version alone does not identify these unreleased changes |
| Shared specification artifacts | `2d9547700d88ad8b7bc73e4d2c0fe18bdffb68a4` |
| Naming policy | Reviewed uncommitted `API-NAMING.md`, SHA-256 `307c914c99c95a088b2f6f41bc02f24a208a6eb3b7f59b68727487df17415c38` |
| Reference runtime | Amazon Corretto 21.0.11, build Corretto-21.0.11.10.1; copied `reference-runtime-lock.json` pins the distribution's release-file SHA-256 |
| CLDR | 48.2; data fingerprint `9b4f24165b6dd1ee6dbb5f0822abc7bcde49c5b94d35903045826b45e1f30e68` |
| IANA | Registry File-Date 2026-09-17; fingerprint `87b3a43b03f490206cead05d865357bd7cfc3953a52ec4d8405243f699385815` |

The baseline includes the behavioral corpus and schema, locale/plural exports and
plural vectors, the relevant schemas, the original CLDR export snapshot and data
locks, IANA equivalences and compatibility overlay, provenance, naming policy,
runtime lock, and upstream licenses/notices. Original notices refer to original
upstream paths; `artifacts` maps those paths to local filenames.
`LICENSE.java` preserves the corresponding upstream license text, including the
minimal-json notice mentioned by the original Java notices. No minimal-json code
is copied into this archive or added to the Swift runtime.

The CLDR/IANA source files and generator implementations are not all included.
Their original input/source hashes remain in the copied locks. This archive verifies
the exported bytes and recomputes the lock fingerprint projections; it cannot
regenerate CLDR from XML or IANA from registry text alone. `data-archive-lock.json`
describes the upstream data-only tar and is provenance, not a claim that the tar
is included here. Neither that tar nor this directory is the deferred immutable
porting-contract archive.

M1 implements the oracle's Unicode 15.0 identifier category policy in generated
Swift tables. The original 21-artifact baseline remains unchanged;
`identifier-data.json` and its Unicode notices are separately pinned development
inputs, described in [identifier provenance](IDENTIFIER-DATA.md). Host Unicode
categories cannot replace that policy. JS currently accepts additional Unicode 17
identifiers; that cross-port version difference remains explicit.

M1 also adds [`materialized-fixtures.json`](MATERIALIZED-FIXTURES.md), reconstructed from the pinned authored
fixture sources using the oracle's exact materialization recipe. The canonical
behavioral artifact sorts object keys and therefore loses insertion order. Replaying
its `files` objects directly would change warning traversal and byte-size diagnostics.
The sidecar supplies original file bytes, including raw-text/base64 overrides; it
contains no expected observations. Its independent checker verifies authored source
pins, semantic agreement with the frozen corpus and byte digests without sibling
repositories. The conformance runner requires its compiled SHA-256 pin before use.

```sh
python3 Tools/generate_identifier_tables.py --check
python3 Tools/materialize_fixtures.py --check
python3 Tools/generate_warning_forms.py --check
```

These checks and sidecars are development-only. The consumer library contains the
identifier and warning-support tables as Swift source and reads no Reference files.

## Verify or import

Run the ordinary verification from a clean checkout:

```sh
python3 Tools/reference_baseline.py --check
```

This command uses Python's standard library and the local `Reference/` files only.
It needs no sibling repositories, Git, Java, Node, network, or installed Python
packages. It checks pinned bytes, duplicate JSON members, corpus inventory and
operation/partition validity, fixture links, disposition IDs, oracle provenance,
CLDR/IANA locks/fingerprints, and the complete baseline manifest. It is a focused
structural checker, not a general-purpose JSON Schema implementation. The original
schemas remain available for schema-aware development tools.

To verify another copied archive, supply its directory:

```sh
python3 Tools/reference_baseline.py --check --reference /path/to/Reference
```

Import is explicit and intended for maintainers recreating this exact baseline:

```sh
python3 Tools/reference_baseline.py --sync --source-root /path/to/workspace
```

That workspace must contain `lokalized-spec`, `lokalized-java`, and `lokalized-js`
at the pinned commits, with matching source artifacts. Import verifies both Java
committed source hashes without trusting `target/classes`, validates every source
artifact before copying, and snapshots the already generated corpus. It never
executes Java or regenerates expected answers. A changed baseline requires an
explicit review and updates to pins/tool/manifest together; `--sync` cannot bless
arbitrary newer inputs.

## Compatibility facts and case accounting

Java 3.1.1 changes these required answers relative to the archived recording:

- `lvariant.exhausting-walk.en-us-posix.duplicate-attempted-language-tag`
- `lvariant.exhausting-walk.ja-jp.ill-formed-attempted-locale`
- `lvariant.exhausting-walk.th-th.ill-formed-attempted-locale`

Successful-result validation moved outside the candidate catch, changing the
failure-handler/callback traces. Preceding-failure validation can also shorten a
walk when an observer is installed. Preserve the 3.1.0 recorded expectations and
qualify the observer separately; installing observation must not change attempts
or policy calls. A corrected shared rebaseline requires a deliberate new contract.

`nativeRepresentationMappings` contains ten **candidate** IDs: five invalid
policy/handler null returns and five invalid phonetic resolver null returns.
Nonoptional Swift callback returns cannot represent these inputs. Each mapping
needs negative compilation evidence and an explicit account of Java runtime traces
that were not replayed. Merely appearing in this registry does not establish that
evidence or move an ID to `runtimePassed` or `nativeRepresentationMapped` in the
runner's result. Inventory additional native representation differences during M0;
this candidate list is not permission to skip an unexamined required case.

The corpus has no observer fixture/operation/output. Apple-only qualification cases
cannot simply be inserted into `requiredImplementationIds`: the existing shared
expected blocks come from the Java oracle, with a closed operation vocabulary.
Keep native qualification IDs in a separate Swift-local registry until shared
schema/oracle tooling supports them.

Two existing phonetic IDs mention decomposed input in their notes but contain
precomposed text. Their recorded meanings are preserved here. Add genuinely
decomposed cases with new IDs rather than silently changing those IDs.

M3 compares the 149 parser, 22 constructor, one language-form, 105 numeric/plural, 312 matching and 31 Accept-Language cases. The report accounts for every
required ID in disjoint runtime-passed/native-mapped/failed/unimplemented sets,
retains exact IDs and evidence, and reports strict runtime agreement separately from
type-system mappings. Shared requirements/evidence closure and independent standards
governance remain incomplete; this archive makes no certification claim.

M2 separately audits the pinned expanded CLDR samples, every cardinal range category pair and example/support inventories. It adds an independent Java 21 raw-bit golden archive at `Reference/floating-point-goldens.json` without rewriting any common-baseline artifact. [Plural data](PLURAL-DATA.md) and [floating conversion](FLOATING-POINT.md) document exact pins, regeneration and qualification scope.

M3 adds independent development locale and language-range goldens, pinned Java 21 equivalence/casing facts and the original IANA parser source used by the development oracle. These archives supplement the common baseline; they do not alter its 21 artifacts or behavioral expectations. Normal golden checks need no sibling checkouts, Java, Node or network. Explicit differential refreshes require the pinned Java 21 toolchain and sources. [Locale data](LOCALE-DATA.md), [language ranges](LANGUAGE-RANGES.md) and [matching](LOCALE-MATCHING.md) record those pins and API adaptations.
