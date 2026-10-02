#!/usr/bin/env python3
"""Qualify the original Unicode 17 NFC implementation without host normalization.

--check compiles only the pinned tables and original NFC implementation and
compares actual scalar arrays with every official NFC equation and scalar
identity outside Part 1. Python standard library only; no network or oracle
runtime is needed. --report-check validates a native executable's audit report.
"""
import argparse
import copy
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'Reference/Unicode-17.0.0/NormalizationTest.txt'
ARCHIVE_SHA = '5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db'
DRIVER = r'''
while let line = readLine() {
    let input = line.split(separator: " ").map { UInt32($0, radix: 16)! }
    print(PinnedNFC.normalize(input).map { String($0, radix: 16) }.joined(separator: " "))
}
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory(reference_directory=ROOT / 'Reference'):
    raw = (Path(reference_directory) / 'Unicode-17.0.0/NormalizationTest.txt').read_bytes()
    if sha(raw) != ARCHIVE_SHA or not raw.startswith(b'# NormalizationTest-17.0.0.txt\n'):
        raise RuntimeError('Unicode 17 normalization archive digest/version differs')
    rows, part1 = [], set()
    part = None
    for line in raw.decode('utf-8').splitlines():
        text = line.split('#', 1)[0].strip()
        if not text:
            continue
        if text.startswith('@'):
            part = text
            continue
        fields = text.split(';')
        if len(fields) != 6 or fields[5].strip():
            raise RuntimeError('Unicode normalization row shape differs')
        columns = [tuple(int(member, 16) for member in field.split()) for field in fields[:5]]
        if any(cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF for column in columns for cp in column):
            raise RuntimeError('Unicode normalization scalar differs')
        rows.append(columns)
        if part == '@Part1':
            if len(columns[0]) != 1 or columns[0][0] in part1:
                raise RuntimeError('Unicode normalization Part 1 inventory differs')
            part1.add(columns[0][0])
    if len(rows) != 20034 or len(part1) != 17086:
        raise RuntimeError('Unicode normalization inventory differs')
    return rows, part1


def observations(rows, part1):
    for row_index, columns in enumerate(rows, 1):
        for column_index, column in enumerate(columns, 1):
            yield (f'normalization:row:{row_index:05d}:c{column_index}', column,
                   columns[1] if column_index <= 3 else columns[3])
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF or cp in part1:
            continue
        yield f'normalization:identity:{cp:06x}', (cp,), (cp,)


def expected_report(rows, part1):
    official = hashlib.sha256()
    identity = hashlib.sha256()
    identity_count = 0
    for observation_id, _, _ in observations(rows, part1):
        if observation_id.startswith('normalization:row:'):
            official.update((observation_id + '\n').encode())
        else:
            identity.update((observation_id + '\n').encode())
            identity_count += 1
    if identity_count != 1094978:
        raise RuntimeError('Unicode normalization identity inventory differs')
    total = 5 * len(rows) + identity_count
    return dict(status='passed', unicodeVersion='17.0.0', archiveSHA256=ARCHIVE_SHA,
                officialRows=len(rows), officialNFCEquations=5 * len(rows),
                identityScalarChecks=identity_count, totalChecks=total, passed=total,
                failed=0, officialEquationIDSetSHA256=official.hexdigest(),
                identityScalarIDSetSHA256=identity.hexdigest(), failures=[])


def check_report(actual, expected):
    # Exact shape and exact value types prevent Boolean counts and added claims.
    if not isinstance(actual, dict) or set(actual) != set(expected):
        raise RuntimeError('Unicode normalization report shape differs')
    for key, value in expected.items():
        if type(actual[key]) is not type(value) or actual[key] != value:
            raise RuntimeError('Unicode normalization report differs: ' + key)


def negative_controls(expected):
    corruptions = [dict(passed=True), dict(totalChecks=expected['totalChecks'] - 1),
                   dict(failed=1), dict(unicodeVersion='16.0.0'),
                   dict(officialEquationIDSetSHA256='0' * 64), dict(failures=['x']),
                   dict(identityScalarChecks=expected['identityScalarChecks'] - 1)]
    for mutation in corruptions:
        changed = copy.deepcopy(expected)
        changed.update(mutation)
        try:
            check_report(changed, expected)
        except RuntimeError:
            continue
        raise RuntimeError('Normalization report negative control was accepted')
    return len(corruptions)


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RuntimeError('Duplicate normalization report field: ' + key)
        result[key] = value
    return result


def report_check(report_path, reference_directory=ROOT / 'Reference'):
    """Strict reusable gate for package and deployment qualification."""
    rows, part1 = inventory(reference_directory)
    expected = expected_report(rows, part1)
    actual = json.loads(Path(report_path).read_bytes(), object_pairs_hook=no_duplicate_keys)
    check_report(actual, expected)
    negative_controls(expected)
    return actual


def check_native(rows, part1, swiftc):
    sources = [ROOT / 'Sources/Lokalized/Data/IDNAUnicodeTables.swift',
               ROOT / 'Sources/Lokalized/Loading/PinnedNFC.swift']
    with tempfile.TemporaryDirectory(prefix='lokalized-nfc-check-') as directory:
        scratch = Path(directory)
        main = scratch / 'main.swift'
        main.write_text(DRIVER)
        executable = scratch / 'nfc-check'
        build = subprocess.run([swiftc, '-O', '-swift-version', '6', '-package-name', 'Lokalized',
                                '-module-cache-path', str(scratch / 'module-cache'),
                                *map(str, sources), str(main), '-o', str(executable)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if build.returncode:
            raise RuntimeError('Normalization probe build failed:\n' + build.stderr.decode(errors='replace'))
        inputs = scratch / 'inputs.txt'
        outputs = scratch / 'outputs.txt'
        with inputs.open('w') as stream:
            for _, source, _ in observations(rows, part1):
                stream.write(' '.join(f'{cp:x}' for cp in source) + '\n')
        with inputs.open('rb') as input_stream, outputs.open('wb') as output_stream:
            result = subprocess.run([str(executable)], stdin=input_stream, stdout=output_stream,
                                    stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError('Normalization probe failed:\n' + result.stderr.decode(errors='replace'))
        failures = []
        with outputs.open() as stream:
            for observation_id, _, expected in observations(rows, part1):
                line = stream.readline()
                if not line:
                    raise RuntimeError('Normalization probe omitted observation ' + observation_id)
                actual = tuple(int(member, 16) for member in line.split())
                if actual != expected and len(failures) < 32:
                    failures.append(observation_id)
            if stream.readline():
                raise RuntimeError('Normalization probe emitted extra observations')
        if failures:
            raise RuntimeError('Unicode 17 NFC qualification failed: ' + ', '.join(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--report-check', type=Path)
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--reference', type=Path, default=ROOT / 'Reference')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    rows, part1 = inventory(args.reference)
    expected = expected_report(rows, part1)
    if args.check:
        check_native(rows, part1, args.swiftc)
    else:
        actual = json.loads(args.report_check.read_bytes(), object_pairs_hook=no_duplicate_keys)
        check_report(actual, expected)
    controls = negative_controls(expected)
    output = dict(expected, reportNegativeControls=controls,
                  qualificationMode='standalone-scalar-array-probe' if args.check else 'native-report-gate')
    data = json.dumps(output, indent=2, sort_keys=True) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(data)
    print(data, end='')


if __name__ == '__main__':
    main()
