#!/usr/bin/env python3
"""Check or explicitly sync the frozen shared native-contract snapshot.

All source bytes are verified before any sync writes. Offline checks need no
sibling repository, compiler, oracle, external package or network.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COPIES = [
    ('conformance/swift-native-v1.json', 'Reference/swift-native-v1.json', '376e7ebf854c8b0216033ffbc9cb570a2c819eb79fa73d820e26e4b54a96479e', 178531),
    ('schema/native-adaptations.schema.json', 'Reference/native-adaptations.schema.json', 'f9e997efc51af70aa10d2a54c7e64c002aaf839da38d64c244cd3f4db2530e6b', 10034),
    ('tools/native_adaptations/__init__.py', 'Tools/NativeAdaptations/__init__.py', 'e55c8f5621d291d4c288d4b0cedbee51ab5e04fd98e7c8ec8de9d3f75cbf993b', 84),
    ('tools/native_adaptations/contract.py', 'Tools/NativeAdaptations/contract.py', 'f9e8a1d798d9b06a91bee2e8599d477fe93ab156e9c21af602627bc7ac3b95e4', 18831),
]


def read_pinned(base, source=False):
    result = {}
    for original, local, pin, count in COPIES:
        path = base / (original if source else local)
        raw = path.read_bytes()
        if len(raw) != count or hashlib.sha256(raw).hexdigest() != pin:
            raise ValueError('Shared native contract snapshot differs: ' + str(path))
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
        raise ValueError('Native contract snapshot differs from canonical spec bytes')
    print(json.dumps({'status': 'passed', 'sourceRepository': 'lokalized-spec', 'artifacts': len(COPIES),
        'mode': 'synced' if args.sync else 'source-check' if args.check_source else 'offline-check'}))


if __name__ == '__main__':
    main()
