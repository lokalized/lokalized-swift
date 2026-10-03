#!/usr/bin/env python3
"""Check the offline shared profile or actual saved Swift parser observations."""
import argparse
import json
from pathlib import Path
from DiagnosticText.contract import check, read
from DiagnosticText.report import report_check as shared_report_check, negative_controls
from sync_diagnostic_text import read_pinned

ROOT=Path(__file__).resolve().parents[1]

def report_check(path, reference=ROOT/'Reference'):
    read_pinned(ROOT)
    return shared_report_check(read(path),reference/'diagnostic-text-v1.1.json')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check',action='store_true')
    mode.add_argument('--report-check',type=Path)
    parser.add_argument('--reference',type=Path,default=ROOT/'Reference')
    parser.add_argument('--negative-controls',action='store_true')
    args=parser.parse_args()
    read_pinned(ROOT)
    artifact=args.reference/'diagnostic-text-v1.1.json'
    if args.check:
        if args.negative_controls: parser.error('--negative-controls requires --report-check')
        result=check(artifact)
    else:
        result=report_check(args.report_check,args.reference)
        if args.negative_controls: result['controls']=negative_controls(read(args.report_check),artifact)
    print(json.dumps(result,sort_keys=True))

if __name__=='__main__': main()
