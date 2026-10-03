#!/usr/bin/env python3
"""Check or explicitly sync the shared diagnostic-text snapshot.

All source bytes are verified before any sync writes. Offline checks need no
sibling repository, compiler, oracle, external package or network.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COPIES = [('generated/diagnostic-text/v1.1.json', 'Reference/diagnostic-text-v1.1.json', '1394c9136089b2b343f562f4ff7ade8d209f7b049b784fe1cc02eb041045c2a2', 273874), ('schema/diagnostic-text.schema.json', 'Reference/diagnostic-text.schema.json', '92477fd48404f5d022a85f646323f2fd8c245c4a050ced340ebba7eb250509ec', 1982), ('tools/diagnostic_text/contract.py', 'Tools/DiagnosticText/contract.py', '6959e1aafd911300be15a037fb2ebf1c8b75f53faf697cac82f4fc6ff6fa1a43', 4238), ('tools/diagnostic_text/report.py', 'Tools/DiagnosticText/report.py', 'c7c97c619e3893628a39bd2301e38024961eb419b6de073d92f53a4567a4b590', 3467), ('tools/diagnostic_text/__init__.py', 'Tools/DiagnosticText/__init__.py', '786bd4bb4743c7d592b4133bec5199c75645bac533e490d7b94441570a91adef', 52)]


def read_pinned(base, source=False):
    result = {}
    for original, local, pin, count in COPIES:
        path = base / (original if source else local)
        raw = path.read_bytes()
        if len(raw) != count or hashlib.sha256(raw).hexdigest() != pin:
            raise ValueError('Shared diagnostic text snapshot differs: ' + str(path))
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
        raise ValueError('Diagnostic text snapshot differs from canonical spec bytes')
    print(json.dumps({'status': 'passed', 'sourceRepository': 'lokalized-spec', 'artifacts': len(COPIES),
        'mode': 'synced' if args.sync else 'source-check' if args.check_source else 'offline-check'}))


if __name__ == '__main__':
    main()
