#!/usr/bin/env python3
"""Check or explicitly sync the shared manifest-normalization snapshot.

All source bytes are verified before any sync writes. Offline checks need no
sibling repository, compiler, oracle, external package or network.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COPIES = [('generated/manifest-normalization/v1.1.json', 'Reference/manifest-normalization-v1.1.json', '9fb02c5a607e6288ef46e49a9161a4bc0d0d23aed98931f7c0482a21a8714162', 85979), ('generated/manifest-normalization/swift-native-lock-v1.1.json', 'Reference/manifest-normalization-swift-native-lock-v1.1.json', '7c2ebd3fd8e360fcece519c48165549b59e18666ee9b407360cd55749fe9a700', 18716), ('schema/manifest-normalization.schema.json', 'Reference/manifest-normalization.schema.json', 'a9abdf59d3628582bf919650f8de33246d8c44883bcb2be5c838720117e5f5e5', 2471), ('tools/manifest_normalization/__init__.py', 'Tools/ManifestNormalization/__init__.py', '82590b368479bd0b4f7f4c9c7ac79efca6dd90833f63c267283dfeb27b964a13', 53), ('tools/manifest_normalization/contract.py', 'Tools/ManifestNormalization/contract.py', '9c518dca77e5074bc46db3177c8e21ad150fcf211109094e4f4e597cae99f591', 8182), ('tools/manifest_normalization/report.py', 'Tools/ManifestNormalization/report.py', 'a53f58694e70c27668cb670a88f1249feec8be4d7fb1060836a64d09766354e8', 14078)]


def read_pinned(base, source=False):
    result = {}
    for original, local, pin, count in COPIES:
        path = base / (original if source else local)
        raw = path.read_bytes()
        if len(raw) != count or hashlib.sha256(raw).hexdigest() != pin:
            raise ValueError('Shared manifest normalization snapshot differs: ' + str(path))
        result[local] = raw
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--check-source', action='store_true')
    mode.add_argument('--sync', action='store_true')
    parser.add_argument('--source', type=Path)
    args = parser.parse_args()
    if args.sync or args.check_source:
        if not args.source:
            parser.error('--sync/--check-source requires --source pointing to lokalized-spec')
        source = read_pinned(args.source.resolve(), source=True)
        if args.sync:
            for relative, raw in source.items():
                path = ROOT/relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
    local = read_pinned(ROOT)
    if args.check_source and local != source:
        raise ValueError('Manifest normalization snapshot differs from canonical spec bytes')
    print(json.dumps({'status': 'passed', 'sourceRepository': 'lokalized-spec', 'artifacts': len(COPIES),
        'mode': 'synced' if args.sync else 'source-check' if args.check_source else 'offline-check'}))


if __name__ == '__main__':
    main()
