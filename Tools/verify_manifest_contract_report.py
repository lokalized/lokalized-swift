#!/usr/bin/env python3
"""Verify raw manifest observations with the pinned shared comparison contract."""
from pathlib import Path
from ManifestContracts.native_report import *
from ManifestContracts import native_report as historical
from ManifestNormalization import report as amended
from sync_manifest_normalization import read_pinned

def report_check(path, reference):
    scope = read_json(Path(path).read_bytes()).get("scope")
    if scope == "native-manifest-validation-identity-planning":
        return historical.report_check(path, reference)
    read_pinned(Path(__file__).resolve().parents[1])
    return amended.manifest_report_check(path, reference, historical)

def self_test(path, reference):
    if read_json(Path(path).read_bytes()).get("scope") == "native-manifest-validation-identity-planning":
        return historical.self_test(path, reference)
    read_pinned(Path(__file__).resolve().parents[1])
    return amended.negative_controls(path, reference, historical, archive_report=True)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--reference", type=Path, default=Path(__file__).resolve().parents[1] / "Reference")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--integrity-report", type=Path)
    args = parser.parse_args()
    result = self_test(args.report, args.reference) if args.self_test else report_check(args.report, args.reference)
    if args.integrity_report:
        require(args.self_test, "--integrity-report requires --self-test")
        args.integrity_report.parent.mkdir(parents=True, exist_ok=True)
        args.integrity_report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))
