#!/usr/bin/env python3
"""Swift adapter for the shared URL oracle's recorded engine provenance."""
import argparse
import json
from pathlib import Path
from URLOracle import oracle_runtime as shared_runtime

ROOT = Path(__file__).resolve().parents[1]
LOCK_SHA256 = shared_runtime.LOCK_SHA256
EXPECTED_NAMES = shared_runtime.EXPECTED_NAMES


def read_lock(reference_directory=ROOT / "Reference"):
    return shared_runtime.read_lock(reference_directory)


def verify_loaded(node, reference_directory=ROOT / "Reference"):
    return shared_runtime.verify_loaded(node, reference_directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--verify-loaded", action="store_true")
    parser.add_argument("--node")
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    args = parser.parse_args()
    if args.verify_loaded:
        if not args.node:
            parser.error("--verify-loaded requires an explicitly selected Node executable")
        result = verify_loaded(args.node, args.reference)
    else:
        value = read_lock(args.reference)
        result = {"status": "passed", "oracleRuntimeLockSHA256": LOCK_SHA256, "pinnedEngineImages": len(value["libraries"]), "qualificationMode": "offline metadata check"}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
