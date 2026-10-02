#!/usr/bin/env python3
"""Copy or verify the M0 reference baseline using only Python's standard library.

--check reads this repository's Reference directory only. --sync requires an explicit
source workspace and imports already generated, pinned bytes; it never runs an oracle.
Changing a reference is a deliberate source change to the pins below, not --sync.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import sys


BASELINE_ID = "java-3.1.0-cldr-48.2-iana-2026-09-17"
REPOSITORIES = {
    "lokalized-spec": {"commit": "2d9547700d88ad8b7bc73e4d2c0fe18bdffb68a4", "role": "shared artifacts", "uncommittedArtifact": "API-NAMING.md"},
    "lokalized-java": {"commit": "491346ba50df65e1e51791f21246ff8bc47e44e9", "version": "3.1.1", "role": "reviewed feature reference", "sourceSha256": "dab6dc8028a27605eff9ef131841bbe517ed30977bcb3514083eaf62c1790a5e"},
    "lokalized-js": {"commit": "617670da887b0c684e2589882447b6b93297f2f7", "version": "1.0.0-rc.2", "role": "reviewed API and transport reference; commit includes unreleased changes"},
}
JAVA_CORPUS_REFERENCE = {
    "commit": "63b63e47c982f7a87873c52ac2289cc0392f3329",
    "version": "3.1.0",
    "sourceSha256": "db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0",
}

# Repository, original path, local filename, SHA-256, exact byte count.
# These pins also prevent replacing both an artifact and its manifest checksum unnoticed.
COPIES = [
    ("lokalized-spec", "generated/behavioral-vectors.json", "behavioral-vectors.json", "1eb74caf8524c0a3b33dca99addb268c86b64eb8321fac03257474ddaa3c9753", 4270021),
    ("lokalized-spec", "schema/behavioral-vectors.schema.json", "behavioral-vectors.schema.json", "766502c1dfa84186e698852105b01501dade62c3e4aa83c9e154d74b7c897996", 55283),
    ("lokalized-spec", "vendor/lokalized-java/src/build/resources/cldr/cldr-locale-data.json", "cldr-locale-data.json", "6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93", 360048),
    ("lokalized-spec", "vendor/lokalized-java/src/build/resources/cldr/cldr-plural-data.json", "cldr-plural-data.json", "7ade4692762aac80144f915b62de19f29eb039ec3cf28c3f9f2c34b810cdc0e7", 79598),
    ("lokalized-spec", "vendor/lokalized-java/src/build/resources/cldr/cldr-conformance-vectors.json", "cldr-conformance-vectors.json", "404e2fb3fbff0ee9564226527c0645c723a16afaf76dff2db7942e5015a54926", 48325),
    ("lokalized-spec", "generated/cldr-data-lock.json", "cldr-data-lock.json", "607ee6493964c02f9b350c31669524a167eba912206c969c9dcc3c74eb212e4b", 2525),
    ("lokalized-spec", "generated/iana-language-equivalences.json", "iana-language-equivalences.json", "2398b866e6739ae81d9484da929567e68e8255fe31aefe5bf2ef25846c611462", 7378),
    ("lokalized-spec", "generated/iana-data-lock.json", "iana-data-lock.json", "18f59f6e490ff1e1d9b719178be6d27f5404d6e26785f741ec712bad7f226229", 1885),
    ("lokalized-spec", "tools/iana-oracle/jdk-compatibility.json", "iana-jdk-compatibility.json", "4ce249f3d5b47890ed367dc0f6ae61925c47eddbd18af26f9b612606ccb82c54", 855),
    ("lokalized-spec", "schema/iana-language-equivalences.schema.json", "iana-language-equivalences.schema.json", "3f969e00ce0e6d9e2e0978d229d0cf1a03aca30ac6feac5e8057f15d3e7afaa7", 7789),
    ("lokalized-spec", "schema/cldr-locale-data.schema.json", "cldr-locale-data.schema.json", "03097cf61a52b4e21b35a2f1d986373b706010ebaba61e89c72921905cf41784", 4560),
    ("lokalized-spec", "schema/cldr-conformance-vectors.schema.json", "cldr-conformance-vectors.schema.json", "3de4d4757ed93cb72988dd96666e90d8087ea7fc5c010006a8c728b5090b0f39", 4233),
    ("lokalized-spec", "vendor/lokalized-java/snapshot.json", "cldr-export-snapshot.json", "05995c1b3a2dec0fa9a2649722840ce22314fb1187d25e51cc5a6fd7918fe229", 1192),
    ("lokalized-spec", "generated/data-archive-lock.json", "data-archive-lock.json", "8f364f91988e2e1711b013d1fd034ec0913d42d56401a6fb3f7d905c6eac591f", 433),
    ("lokalized-spec", "API-NAMING.md", "API-NAMING.md", "307c914c99c95a088b2f6f41bc02f24a208a6eb3b7f59b68727487df17415c38", 4036),
    ("lokalized-spec", "generated/IANA-PROVENANCE.md", "IANA-PROVENANCE.md", "975bde61f1263c9c69bb147a78a43dbe75e1b5f5db409eab33ab0c1aafb00f0c", 12948),
    ("lokalized-spec", "THIRD-PARTY-NOTICES.md", "THIRD-PARTY-NOTICES.spec.md", "c2bc90441602897b9e4190534e1dfafad7d4af2bfcbd46d021b335a41e51d707", 4105),
    ("lokalized-spec", "LICENSE", "LICENSE.spec", "c251818bcacf032ffd5592441c6aba99bee187d80d12155843d0c001b9f4d469", 11596),
    ("lokalized-js", "measurements/reference-runtime-lock.json", "reference-runtime-lock.json", "4544c2b9e1f74d85294ae83fdfe9a2cc9667a781a771ee90af01a4b812140756", 951),
    ("lokalized-java", "THIRD-PARTY-NOTICES.md", "THIRD-PARTY-NOTICES.java.md", "4318f4573023233f8b8c51f5794f0508283e8a56152220c039c7807178e3ea81", 4255),
    ("lokalized-java", "LICENSE", "LICENSE.java", "6791ccd02d13840e56d6bfe227f93ba6056aed52452143cf22557f99ca0575fb", 12856),
]

POLICY_HANDLER_NULL_IDS = [
    "null-callbacks.handler.null-response-is-rejected-after-the-walk",
    "null-callbacks.policy.null-decision-carries-the-resolution-failure-cause",
    "null-callbacks.policy.null-decision-is-rejected-at-the-consultation",
    "null-callbacks.policy.null-decision-propagates-out-of-get",
    "null-callbacks.precedence.the-null-policy-is-rejected-before-the-null-handler",
]
PHONETIC_NULL_IDS = [
    "callback-interaction.null-resolver.first-of-two-identical-type-causes-is-retained",
    "callback-interaction.null-resolver.retained-null-failure-rethrown-verbatim",
    "callback-smoke.resolver.null-return-is-rejected",
    "phonetic-resolver.constants.unmapped-term-returns-null",
    "phonetic-resolver.expression.null-return-diagnostic",
]
REGRESSION_IDS = [
    "lvariant.exhausting-walk.en-us-posix.duplicate-attempted-language-tag",
    "lvariant.exhausting-walk.ja-jp.ill-formed-attempted-locale",
    "lvariant.exhausting-walk.th-th.ill-formed-attempted-locale",
]
OPERATIONS = {
    "acceptLanguage", "getResult", "get", "matchFor", "cardinalityForNumber",
    "cardinalityForOperands", "cardinalityForRange", "ordinalityForNumber",
    "ordinalityForOperands", "supportedCardinalitiesForLocale",
    "supportedOrdinalitiesForLocale", "loadClasspath", "loadClasspathResources",
    "load", "parse", "languageForms", "construct", "define",
}
PARTITIONS = {"requiredPortableIds", "requiredImplementationIds", "informationalIds"}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def compact_json(value):
    # These source-hash/data-lock projections contain ASCII keys, finite integers,
    # strings, arrays and objects only. This is not a general RFC 8785 encoder.
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def read_json(path):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"{path}: duplicate JSON member {key!r}")
            result[key] = value
        return result
    return json.loads(path.read_bytes(), object_pairs_hook=unique_object)


def corpus_summary(corpus):
    if corpus.get("formatVersion") != 1 or corpus.get("behavioralVectorsVersion") != "1.1.0":
        raise ValueError("unexpected corpus format/version")
    cases, fixtures = corpus["cases"], corpus["fixtures"]
    ids = set()
    for case in cases:
        if case["id"] in ids:
            raise ValueError(f"duplicate case ID {case['id']}")
        ids.add(case["id"])
        if case["fixture"] not in fixtures:
            raise ValueError(f"{case['id']}: absent fixture")
        if case["operation"] not in OPERATIONS or case["partition"] not in PARTITIONS:
            raise ValueError(f"{case['id']}: unknown operation/partition")
        if not isinstance(case["expected"], dict) or not case["expected"]:
            raise ValueError(f"{case['id']}: absent expected projection")
        if case["partition"] == "requiredImplementationIds" and not case.get("implementationFamily"):
            raise ValueError(f"{case['id']}: implementation family missing")
    partitions = Counter(case["partition"] for case in cases)
    summary = {
        "path": "behavioral-vectors.json", "schemaPath": "behavioral-vectors.schema.json",
        "sha256": COPIES[0][3], "formatVersion": corpus["formatVersion"],
        "behavioralVectorsVersion": corpus["behavioralVectorsVersion"],
        "cases": len(cases), "fixtures": len(fixtures),
        **{key: partitions[key] for key in sorted(PARTITIONS)},
        "operations": dict(sorted(Counter(case["operation"] for case in cases).items())),
    }
    if (summary["cases"], summary["fixtures"], partitions["requiredPortableIds"], partitions["informationalIds"], partitions["requiredImplementationIds"]) != (2381, 586, 2155, 226, 0):
        raise ValueError("pinned corpus case/fixture/partition inventory moved")
    required_ids = {case["id"] for case in cases if case["partition"] == "requiredPortableIds"}
    if not set(POLICY_HANDLER_NULL_IDS + PHONETIC_NULL_IDS + REGRESSION_IDS) <= required_ids:
        raise ValueError("baseline dispositions refer to absent/nonportable cases")
    if corpus["oracle"]["librarySourcesSha256"] != JAVA_CORPUS_REFERENCE["sourceSha256"] or corpus["oracle"]["javaVersion"] != "21.0.11":
        raise ValueError("corpus oracle source/runtime provenance moved")
    return summary


def manifest_for(reference):
    corpus = read_json(reference / "behavioral-vectors.json")
    summary = corpus_summary(corpus)
    return {
        "formatVersion": 1,
        "baselineId": BASELINE_ID,
        "purpose": "Development-only immutable reference data; no Swift runtime behavior is implemented or certified by this archive.",
        "sourceRepositories": REPOSITORIES,
        "javaCorpusReference": JAVA_CORPUS_REFERENCE,
        "corpus": summary,
        "data": {
            "cldrVersion": "48.2", "dataFingerprint": "9b4f24165b6dd1ee6dbb5f0822abc7bcde49c5b94d35903045826b45e1f30e68",
            "ianaRegistryDate": "2026-09-17", "ianaDataFingerprint": "87b3a43b03f490206cead05d865357bd7cfc3953a52ec4d8405243f699385815",
            "identifierUnicodeVersion": "15.0",
            "identifierUnicodeStatus": "planned oracle policy; generated Swift identifier tables are not included in this M0 archive",
        },
        "artifacts": [
            {"path": name, "sourceRepository": repo, "sourcePath": original, "bytes": size, "sha256": digest}
            for repo, original, name, digest, size in COPIES
        ],
        "knownJava311Regression": {
            "status": "observed regression; retain recorded Java 3.1.0 expectations",
            "requiredIds": REGRESSION_IDS,
            "description": "Java 3.1.1 validates successful results outside the candidate catch; handler/callback traces differ. PrecedingFailure validation can also shorten walks when an observer is installed. Observation must not change the walk; any shared rebaseline requires a deliberate corrected contract.",
        },
        "nativeRepresentationMappings": {
            "status": "candidates-awaiting-compiler-evidence",
            "countsAsRuntimePassed": False,
            "groups": [
                {"reason": "A nonoptional Swift policy/handler return type cannot express Java's invalid null return. Negative compilation evidence must establish the mapping; Java runtime timing/traces are not replayed.", "requiredIds": POLICY_HANDLER_NULL_IDS},
                {"reason": "A nonoptional Swift phonetic resolver return type cannot express Java's invalid null return. These five cases need their own mapping/evidence; Java's contextualized runtime failure is not reproduced by inventing a runner error.", "requiredIds": PHONETIC_NULL_IDS},
            ],
        },
        "corpusGaps": {
            "observer": "No observer fixture/operation/output exists in this corpus; qualify observer behavior separately until shared tooling is extended.",
            "implementationSpecific": "No requiredImplementationIds exist. Apple-only cases need a Swift-local qualification registry until shared schema/oracle tooling supports native expectations.",
            "decomposedText": ["phonetic-resolver.by-term.non-ascii-decomposed-misses", "phonetic-resolver.first-letter.decomposed-accent"],
            "decomposedTextNote": "These IDs contain precomposed inputs despite their notes. Retain recorded meanings and add genuinely decomposed cases with new IDs.",
            "formalGovernance": "Shared requirement/evidence closure and independently ratified language-neutral release profiles remain incomplete; this archive makes no certification claim.",
        },
        "licensing": {
            "specLicense": "LICENSE.spec",
            "javaLicense": "LICENSE.java",
            "notices": ["THIRD-PARTY-NOTICES.spec.md", "THIRD-PARTY-NOTICES.java.md", "IANA-PROVENANCE.md"],
            "note": "Original notices retain original upstream paths. This manifest maps those paths to local copies. Unicode-derived CLDR data carries Unicode-3.0 notices; no Java/JS library code is vendored here.",
        },
    }


def verify_files(reference):
    for _, _, name, digest, size in COPIES:
        path = reference / name
        data = path.read_bytes()
        if len(data) != size or sha256(data) != digest:
            raise ValueError(f"{path}: pinned bytes/digest mismatch")
    cldr = read_json(reference / "cldr-data-lock.json")
    for artifact in cldr["artifacts"]:
        if sha256((reference / Path(artifact["path"]).name).read_bytes()) != artifact["sha256"]:
            raise ValueError("CLDR export does not match its original lock")
    cldr_projection = {key: cldr[key] for key in ["formatVersion", "cldrVersion", "artifacts"]}
    if sha256(compact_json(cldr_projection)) != cldr["dataFingerprint"]:
        raise ValueError("CLDR fingerprint projection mismatch")
    iana = read_json(reference / "iana-data-lock.json")
    for artifact in iana["artifacts"]:
        if sha256((reference / Path(artifact["path"]).name).read_bytes()) != artifact["sha256"]:
            raise ValueError("IANA export does not match its original lock")
    projection = {key: iana[key] for key in ["formatVersion", "ianaRegistryDate", "sourceSha256", "closureSchemaVersion", "compatibilityOverridesSha256"]}
    projection["artifacts"] = [{key: artifact[key] for key in ["path", "sha256"]} for artifact in iana["artifacts"]]
    if sha256(compact_json(projection)) != iana["ianaDataFingerprint"]:
        raise ValueError("IANA fingerprint projection mismatch")
    if sha256((reference / "iana-jdk-compatibility.json").read_bytes()) != iana["compatibilityOverridesSha256"]:
        raise ValueError("IANA compatibility overlay mismatch")


def git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments], stderr=subprocess.PIPE)


def verify_source_repositories(source_root):
    for name, pin in REPOSITORIES.items():
        if git(source_root / name, "rev-parse", "HEAD").decode().strip() != pin["commit"]:
            raise ValueError(f"{name}: HEAD does not match the reviewed commit")
    java = source_root / "lokalized-java"
    source_path = "src/main/java/com/lokalized"
    for pin in [JAVA_CORPUS_REFERENCE, REPOSITORIES["lokalized-java"]]:
        names = git(java, "ls-tree", "--name-only", f"{pin['commit']}:{source_path}").decode().splitlines()
        sources = [{"path": name, "sha256": sha256(git(java, "show", f"{pin['commit']}:{source_path}/{name}"))} for name in sorted(names)]
        if sha256(compact_json(sources)) != pin["sourceSha256"]:
            raise ValueError(f"Java {pin['version']}: committed source hash does not match its reference")


def sync(source_root, reference):
    verify_source_repositories(source_root)
    # Validate every source before copying any artifact. A stale checkout cannot
    # replace a valid baseline halfway through a failed synchronization.
    contents = []
    for repo, original, name, digest, size in COPIES:
        data = (source_root / repo / original).read_bytes()
        if len(data) != size or sha256(data) != digest:
            raise ValueError(f"{repo}/{original}: source does not match the pinned reference")
        contents.append((name, data))
    reference.mkdir(parents=True, exist_ok=True)
    for name, data in contents:
        (reference / name).write_bytes(data)
    verify_files(reference)
    manifest = manifest_for(reference)
    (reference / "baseline.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def check(reference):
    verify_files(reference)
    expected = manifest_for(reference)
    actual = read_json(reference / "baseline.json")
    if actual != expected:
        raise ValueError(f"{reference / 'baseline.json'}: manifest/provenance/disposition mismatch")
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="verify local pinned reference; no sibling repositories required")
    mode.add_argument("--sync", action="store_true", help="import the explicitly selected pinned source workspace")
    parser.add_argument("--source-root", type=Path, help="workspace containing lokalized-java, lokalized-js and lokalized-spec; required by --sync")
    parser.add_argument("--reference", type=Path, default=Path(__file__).resolve().parents[1] / "Reference", help="reference directory (default: this repository's Reference)")
    args = parser.parse_args()
    if args.sync and args.source_root is None:
        parser.error("--sync requires --source-root; no implicit sibling checkout is used")
    if args.check and args.source_root is not None:
        parser.error("--check is self-contained; --source-root is only for --sync")
    try:
        if args.sync:
            sync(args.source_root.resolve(), args.reference.resolve())
        manifest = check(args.reference.resolve())
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"reference baseline FAILED: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": "verified", "baselineId": manifest["baselineId"], "artifacts": len(COPIES), "corpus": manifest["corpus"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
