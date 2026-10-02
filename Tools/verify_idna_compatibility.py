#!/usr/bin/env python3
"""Independent all-codepoint decoder qualification for frozen IDNA properties.

The native probe emits four raw property bytes for every Unicode codepoint,
including the surrogate interval, followed by two out-of-range values. Expected
bytes are projected independently from the pinned source-data archive. No Node,
network, host Unicode tables, or external packages are required.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Sources/Lokalized/Data/IDNACompatibilityProperties.swift'
DRIVER = r'''
import Foundation
var output: [UInt8] = []
output.reserveCapacity(65_536)
@MainActor func append(_ cp: UInt32) {
    output.append(IDNACompatibilityProperties.isMark(cp) ? 1 : 0)
    output.append(IDNACompatibilityProperties.isVirama(cp) ? 1 : 0)
    output.append(IDNACompatibilityProperties.joiningType(cp))
    output.append(IDNACompatibilityProperties.bidiClass(cp))
    if output.count >= 65_536 {
        FileHandle.standardOutput.write(Data(output))
        output.removeAll(keepingCapacity: true)
    }
}
for cp: UInt32 in 0...0x10FFFF { append(cp) }
append(0x110000)
append(UInt32.max)
FileHandle.standardOutput.write(Data(output))
'''


def sha(value):
    return hashlib.sha256(value).hexdigest()


def generator():
    spec = importlib.util.spec_from_file_location('idna_compatibility_generator', ROOT / 'Tools/generate_idna_compatibility.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected(reference_directory=ROOT / 'Reference'):
    gen = generator()
    profile, license_text = gen.load_profile(reference_directory)
    generated, _ = gen.generate(profile, license_text)
    if SOURCE.read_text() != generated:
        raise RuntimeError('Generated IDNA compatibility source differs')
    properties = profile['properties']
    answers = bytearray([0, 0, 0, 11]) * (0x110000 + 2)
    for cp in properties['marks']:
        answers[cp * 4] = 1
    for cp in properties['viramas']:
        answers[cp * 4 + 1] = 1
    for name, scalars in properties['joiningTypes'].items():
        for cp in scalars:
            answers[cp * 4 + 2] = {'L': 1, 'R': 2, 'D': 3}[name]
    codes = {'L': 0, 'R': 1, 'AL': 2, 'AN': 3, 'EN': 4, 'ES': 5,
             'CS': 6, 'ET': 7, 'ON': 8, 'BN': 9, 'NSM': 10}
    for first, last, name in properties['bidiClasses']:
        for cp in range(first, last + 1):
            answers[cp * 4 + 3] = codes.get(name, 11)
    report = dict(status='passed', nodeVersion='v26.5.0', adaVersion='4.0.0',
                  propertyProfileSHA256=gen.PROFILE_SHA256,
                  propertyDataSourceSHA256=gen.SOURCE_SHA256,
                  generatedSourceSHA256=sha(generated.encode()),
                  probeRecipeSHA256=sha(DRIVER.encode()),
                  codepointCount=0x110000, outOfRangeCount=2,
                  propertyFields=['mark', 'virama', 'joiningType', 'bidiClass'],
                  totalLookups=len(answers), passed=len(answers), failed=0,
                  decodedPropertyBytesSHA256=sha(answers))
    return report, answers


def check_report(actual, expected_report):
    if type(actual) is not dict or set(actual) != set(expected_report):
        raise RuntimeError('IDNA compatibility decoder report shape differs')
    for key, value in expected_report.items():
        if type(actual[key]) is not type(value) or actual[key] != value:
            raise RuntimeError('IDNA compatibility decoder report differs: ' + key)


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RuntimeError('Duplicate IDNA compatibility report field: ' + key)
        result[key] = value
    return result


def negative_controls(expected_report):
    mutations = [dict(passed=True), dict(failed=1), dict(codepointCount=0x110000 - 1),
                 dict(outOfRangeCount=0), dict(decodedPropertyBytesSHA256='0' * 64),
                 dict(propertyProfileSHA256='0' * 64), dict(nodeVersion='v26.6.0')]
    for mutation in mutations:
        changed = copy.deepcopy(expected_report)
        changed.update(mutation)
        try:
            check_report(changed, expected_report)
        except RuntimeError:
            continue
        raise RuntimeError('IDNA compatibility decoder negative control was accepted')
    return len(mutations)


def report_check(report_path, reference_directory=ROOT / 'Reference'):
    expected_report, _ = expected(reference_directory)
    actual = json.loads(Path(report_path).read_bytes(), object_pairs_hook=no_duplicate_keys)
    check_report(actual, expected_report)
    negative_controls(expected_report)
    return actual


def probe(swiftc, answers):
    with tempfile.TemporaryDirectory(prefix='lokalized-idna-compatibility-') as directory:
        scratch = Path(directory)
        main = scratch / 'main.swift'
        main.write_text(DRIVER)
        executable = scratch / 'property-probe'
        build = subprocess.run([swiftc, '-O', '-swift-version', '6', '-package-name', 'Lokalized',
                                '-module-cache-path', str(scratch / 'module-cache'), str(SOURCE),
                                str(main), '-o', str(executable)], capture_output=True)
        if build.returncode:
            raise RuntimeError('IDNA compatibility probe build failed:\n' + build.stderr.decode(errors='replace'))
        result = subprocess.run([str(executable)], capture_output=True)
        if result.returncode:
            raise RuntimeError('IDNA compatibility probe failed:\n' + result.stderr.decode(errors='replace'))
        if result.stdout != answers:
            if len(result.stdout) != len(answers):
                raise RuntimeError('IDNA compatibility probe output length differs')
            first = next(index for index, (actual, wanted) in enumerate(zip(result.stdout, answers)) if actual != wanted)
            raise RuntimeError(f'IDNA compatibility decoded property differs at codepoint index {first // 4}, field {first % 4}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--report-check', type=Path)
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--reference', type=Path, default=ROOT / 'Reference')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    expected_report, answers = expected(args.reference)
    if args.check:
        probe(args.swiftc, answers)
    else:
        report_check(args.report_check, args.reference)
    negative_controls(expected_report)
    output = json.dumps(expected_report, indent=2, sort_keys=True) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output)
    print(output, end='')


if __name__ == '__main__':
    main()
