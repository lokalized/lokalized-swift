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
COPIES = [('conformance/swift-manifest-v1.json', 'Reference/swift-manifest-v1.json', '504d65b919ee73f65a74469846004df45364213b7ecff88d0417f8a5d7ce585f', 57851), ('generated/manifest-contract/LICENSE.js', 'Reference/LICENSE.js', 'b40930bbcf80744c86c46a12bc9da056641d722716c378f5659b9e555ef833e1', 11357), ('generated/manifest-contract/NOTICE.js', 'Reference/NOTICE.js', '48ce2bbc1bcfff38d31ebff6961d8c9ee98f9bf164e5d7c56f6806fd09faa287', 2231), ('generated/manifest-contract/THIRD-PARTY-NOTICES.js.md', 'Reference/THIRD-PARTY-NOTICES.js.md', '9ba3ebc846fd70b63bcb53a0a24dd3076398f5c21aede474ca6c95dd979e5ab7', 5091), ('generated/manifest-contract/api-inventory.json', 'Reference/api-inventory.json', '7fd80fa679123fb1f679b179efc2280d4e70086d03f4c91c498b0a26fda5ffcc', 192292), ('generated/manifest-contract/manifest-contract-lock.json', 'Reference/manifest-contract-lock.json', 'faaa51bdacd19f1fbd407848ac545221aad4da5d6d02a1095f1d927a2a96bf03', 27619), ('generated/manifest-contract/manifest-contract-vectors.json', 'Reference/manifest-contract-vectors.json', '6356098bbde353a66886e9552c45efe7ec6353697cf26be2141d3e9f4811d50a', 1176486), ('generated/manifest-contract/manifest-contract-vectors.schema.json', 'Reference/manifest-contract-vectors.schema.json', '903b506519022ddc929ca42220958634330079013e5a6b8462deb87704f7e4c5', 2375), ('tools/manifest_contracts/__init__.py', 'Tools/ManifestContracts/__init__.py', '851f0d922aaef14497b88e6b26fd556b7b685156fd6f687fb4946c3560e66d72', 85), ('tools/manifest_contracts/archive.py', 'Tools/ManifestContracts/archive.py', '6d25ec4725dfc9547c74551580b9699df57c10ffbc974b66b93c75fa44f3874d', 37454), ('tools/manifest_contracts/native_policy.py', 'Tools/ManifestContracts/native_policy.py', 'c84205a9a4a97430b88d184d87c7e2007e91ed7a7aa5a44427701a2cc02bd543', 11320), ('tools/manifest_contracts/native_report.py', 'Tools/ManifestContracts/native_report.py', 'ec6d9e1eaf815ef247145afdce091ec9125611b9f9daa81b4ebdb264cec5d075', 24174), ('tools/manifest_contracts/oracle.mjs', 'Tools/ManifestContracts/oracle.mjs', 'e72d30e741c948edf82b360968dcdbfd35dd1cf4127edd39960687afffb49fc7', 4430), ('schema/manifest-native-adaptations.schema.json', 'Reference/manifest-native-adaptations.schema.json', '8fc16ddabbd42c1a731d98dd18c736e603b71dd30b424aff3143f94510d6eb4e', 3783)]


def read_pinned(base, source=False):
    result = {}
    for original, local, pin, count in COPIES:
        path = base / (original if source else local)
        raw = path.read_bytes()
        if len(raw) != count or hashlib.sha256(raw).hexdigest() != pin:
            raise ValueError('Shared manifest contract snapshot differs: ' + str(path))
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
        raise ValueError('Manifest contract snapshot differs from canonical spec bytes')
    print(json.dumps({'status': 'passed', 'sourceRepository': 'lokalized-spec', 'artifacts': len(COPIES),
        'mode': 'synced' if args.sync else 'source-check' if args.check_source else 'offline-check'}))


if __name__ == '__main__':
    main()
