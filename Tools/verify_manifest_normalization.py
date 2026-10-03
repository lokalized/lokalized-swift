#!/usr/bin/env python3
"""Check pinned shared normalization inputs and actual saved native observations."""
import argparse
import json
from pathlib import Path
from ManifestContracts import native_report as raw
from ManifestNormalization.contract import check
from ManifestNormalization.report import normalization_report_check, negative_controls
from sync_manifest_normalization import read_pinned
ROOT=Path(__file__).resolve().parents[1]

def report_check(path, reference=ROOT/'Reference'):
    read_pinned(ROOT)
    return normalization_report_check(path,reference,raw)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check',action='store_true');mode.add_argument('--report-check',type=Path)
    parser.add_argument('--negative-controls',action='store_true');parser.add_argument('--reference',type=Path,default=ROOT/'Reference')
    args=parser.parse_args();read_pinned(ROOT)
    if args.check:
        if args.negative_controls:parser.error('--negative-controls requires --report-check')
        result=check(args.reference/'manifest-normalization-v1.1.json',args.reference/'manifest-contract-vectors.json')
    else:
        result=report_check(args.report_check,args.reference)
        if args.negative_controls:result=negative_controls(args.report_check,args.reference,raw)
    print(json.dumps(result,sort_keys=True))
if __name__=='__main__':main()
