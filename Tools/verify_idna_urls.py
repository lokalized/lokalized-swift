#!/usr/bin/env python3
"""Qualify the Swift URL resolver against the shared frozen IDNA oracle offline.

The canonical corpus and language-neutral recipe live in lokalized-spec. This
adapter uses its pinned development snapshot; a consumer needs none of these
files, Python, Node, sibling repositories or external runtime packages.
"""
import argparse
import json
from pathlib import Path
import shutil
import sys
from URLOracle import idna_corpus as corpus
import oracle_runtime

ROOT = Path(__file__).resolve().parents[1]
GOLDENS = ROOT / "Reference/manifest-idna-goldens.json.gz"
MAXIMUM_COMPRESSED_BYTES = corpus.MAXIMUM_COMPRESSED_BYTES
MAXIMUM_DECODED_BYTES = corpus.MAXIMUM_DECODED_BYTES
SOURCE_SHA256 = corpus.SOURCE_SHA256
PROPERTY_PROFILE_SHA256 = corpus.PROPERTY_PROFILE_SHA256
PROPERTY_DATA_SOURCE_SHA256 = corpus.PROPERTY_DATA_SOURCE_SHA256
NORMALIZATION_PROFILE_SHA256 = corpus.NORMALIZATION_PROFILE_SHA256
GOLDENS_SHA256 = corpus.GOLDENS_SHA256
NODE_SHA256 = corpus.NODE_SHA256
NODE_VERSIONS = corpus.NODE_VERSIONS
EXCLUDED_LINES = corpus.EXCLUDED_LINES
digest = corpus.digest
gzip_bytes = corpus.gzip_bytes
read_gzip = corpus.read_gzip


def matrix(reference_directory=ROOT / "Reference"):
    return corpus.matrix(reference_directory)


def archive_check(reference_directory=ROOT / "Reference"):
    return corpus.archive_check(Path(reference_directory) / GOLDENS.name, reference_directory)


def make_report(archive, actual):
    if len(actual) != len(archive["rows"]):
        raise ValueError("Native IDNA observation count differs")
    ids = [row["id"] for row in archive["rows"]]
    failed = [row["id"] for row, observation in zip(archive["rows"], actual) if observation != row["expected"]]
    return {"status": "failed" if failed else "passed", "total": len(ids), "failed": len(failed), "runtimePassed": len(ids) - len(failed),
            "qualifiedIDs": ids, "qualifiedIDSetSHA256": digest("".join(value + "\n" for value in ids).encode()),
            "archiveSHA256": GOLDENS_SHA256, "sourceSHA256": SOURCE_SHA256,
            "propertyProfileSHA256": PROPERTY_PROFILE_SHA256, "propertyDataSourceSHA256": PROPERTY_DATA_SOURCE_SHA256,
            "propertyDiscriminantRows": 32_203,
            "normalizationProfileSHA256": NORMALIZATION_PROFILE_SHA256, "normalizationDiscriminantRows": 17_062,
            "oracleRuntimeLockSHA256": oracle_runtime.LOCK_SHA256,
            "excludedIllFormedSourceLines": EXCLUDED_LINES, "failures": failed[:32]}


def report_check(report, reference_directory):
    archive = archive_check(reference_directory)
    expected = make_report(archive, [row["expected"] for row in archive["rows"]])
    if not isinstance(report, dict) or set(report) != set(expected):
        raise ValueError("Manifest IDNA report field inventory differs")
    if any(type(report[field]) is not int for field in ["total", "failed", "runtimePassed", "propertyDiscriminantRows", "normalizationDiscriminantRows"]):
        raise ValueError("Manifest IDNA report counters must be integers")
    for field, value in expected.items():
        if report[field] != value:
            raise ValueError("Manifest IDNA report differs at " + field)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--swiftc", default=shutil.which("swiftc"))
    parser.add_argument("--refresh-goldens", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--node", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.refresh_goldens:
        parser.error("Refresh the canonical corpus in lokalized-spec with tools/check-url-oracle.py --refresh-goldens, then use Tools/sync_url_oracle.py")
    archive = archive_check()
    from verify_manifest_urls import native_probe
    actual = native_probe([row["input"] for row in archive["rows"]], args.swiftc)
    report = make_report(archive, actual)
    print(json.dumps(report, indent=2))
    if report["failed"]:
        for row, observation in zip(archive["rows"], actual):
            if observation != row["expected"]:
                print(json.dumps({"id": row["id"], "origin": row["origin"], "input": row["input"], "expected": row["expected"], "actual": observation}, ensure_ascii=True), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
