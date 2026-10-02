#!/usr/bin/env python3
"""Independently qualify frozen Node URL normalization data and Swift decoding.

--check executes native CCC/decomposition lookups over every Unicode codepoint,
composition lookups along both zero axes and the complete stored starter/second
cross product, neighboring pairs, and out-of-range boundaries. --source-check
compares the frozen property archive directly with the SHA-pinned Ada data
arrays. Neither mode infers URL acceptance from an upstream source algorithm.
Normal checks need only committed files, Python's standard library, and swiftc.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROFILE_SHA = '9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c'
ADA_SHA = 'ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4'
NODE_SHA = '87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511'
TABLE_SHA = '72e648aa5b5c493aac951ca1b4b9e5622f87687cfcbc0bbbc023e60bae0d7945'
PROJECTION_SHA = 'aafd7b428b8f19dab7a4e60ff04f51fd862604459df782fc30d1f1f7fba1cd91'
QUERY_SHA = '3fe47e3c50afcba114f8b549b788999697930b5691feb76ed75f981d964c855d'
TABLE = ROOT / 'Sources/Lokalized/Data/IDNACompatibilityNormalizationTables.swift'
MAX = 0x110000
OUT_OF_RANGE = (MAX, MAX + 1, 0xffffffff)
DRIVER = r'''
import Foundation
var output = Data()
output.reserveCapacity(65_536)
@MainActor func append(_ value: UInt32) {
    output.append(UInt8(truncatingIfNeeded: value >> 24))
    output.append(UInt8(truncatingIfNeeded: value >> 16))
    output.append(UInt8(truncatingIfNeeded: value >> 8))
    output.append(UInt8(truncatingIfNeeded: value))
}
@MainActor func flush() {
    if output.count >= 65_536 {
        FileHandle.standardOutput.write(output)
        output.removeAll(keepingCapacity: true)
    }
}
@MainActor func inspect(_ scalar: UInt32) {
    output.append(IDNACompatibilityNormalizationTables.combiningClass(scalar))
    if let sequence = IDNACompatibilityNormalizationTables.decomposition(scalar) {
        guard sequence.count < 255 else { fatalError("Invalid decomposition size") }
        output.append(UInt8(sequence.count))
        for member in sequence { append(member) }
    } else { output.append(255) }
    append(IDNACompatibilityNormalizationTables.composition(scalar, 0) ?? UInt32.max)
    append(IDNACompatibilityNormalizationTables.composition(0, scalar) ?? UInt32.max)
    flush()
}
for scalar: UInt32 in 0...0x10ffff { inspect(scalar) }
for scalar: UInt32 in [0x110000, 0x110001, UInt32.max] { inspect(scalar) }
while let line = readLine() {
    let values = line.split(separator: " ").map { UInt32($0, radix: 16)! }
    guard values.count == 2 else { fatalError("Invalid development query") }
    append(IDNACompatibilityNormalizationTables.composition(values[0], values[1]) ?? UInt32.max)
    flush()
}
FileHandle.standardOutput.write(output)
'''


def sha(value):
    return hashlib.sha256(value).hexdigest()


def no_duplicates(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise RuntimeError('Duplicate normalization decoder report/profile key: ' + name)
        result[name] = value
    return result


def same(actual, expected):
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return set(actual) == set(expected) and all(same(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(same(a, b) for a, b in zip(actual, expected))
    return actual == expected


def load_profile(reference=ROOT / 'Reference'):
    raw = (Path(reference) / 'IDNA-Compatibility/normalization-profile.json').read_bytes()
    if sha(raw) != PROFILE_SHA:
        raise RuntimeError('Normalization property archive differs from its frozen pin')
    profile = json.loads(raw, object_pairs_hook=no_duplicates)
    expected_authority = dict(adaVersion='4.0.0', nodeVersion='v26.5.0', nodeBinarySHA256=NODE_SHA)
    if type(profile.get('formatVersion')) is not int or profile['formatVersion'] != 1 or not same(profile['compatibilityAuthority'], expected_authority):
        raise RuntimeError('Normalization compatibility authority differs')
    if profile['propertyDataSource']['sha256'] != ADA_SHA or profile['propertyDataSource']['section'] != 'src/normalization_tables.cpp':
        raise RuntimeError('Normalization data-source identity differs')
    properties = profile['properties']
    if set(properties) != {'combiningClasses', 'compositionPairs', 'decompositions'}:
        raise RuntimeError('Normalization property archive fields differ')
    ccc = bytearray(MAX)
    previous = -1
    ranges = properties['combiningClasses']
    if len(ranges) != 388:
        raise RuntimeError('Normalization CCC range count differs')
    for row in ranges:
        if type(row) is not list or len(row) != 3 or any(type(value) is not int for value in row):
            raise RuntimeError('Normalization CCC field types differ')
        first, last, value = row
        if not previous < first <= last < MAX or not 0 < value < 256:
            raise RuntimeError('Normalization CCC ranges overlap or exceed bounds')
        previous = last
        ccc[first:last + 1] = bytes([value]) * (last - first + 1)
    compositions = {}
    pairs = properties['compositionPairs']
    if len(pairs) != 941 or pairs != sorted(pairs):
        raise RuntimeError('Normalization composition inventory differs')
    for row in pairs:
        if type(row) is not list or len(row) != 3 or any(type(value) is not int or not 0 <= value < MAX or 0xd800 <= value <= 0xdfff for value in row):
            raise RuntimeError('Normalization composition scalar types/bounds differ')
        first, second, result = row
        if (first, second) in compositions:
            raise RuntimeError('Duplicate normalization composition pair')
        compositions[first, second] = result
    if any(first == 0 or second == 0 for first, second in compositions):
        raise RuntimeError('Zero-axis composition expectation must be empty')
    decompositions = {}
    previous = -1
    records = properties['decompositions']
    if len(records) != 2061:
        raise RuntimeError('Normalization decomposition inventory differs')
    for row in records:
        if type(row) is not list or len(row) != 2:
            raise RuntimeError('Normalization decomposition record shape differs')
        scalar, sequence = row
        if type(scalar) is not int or not previous < scalar < MAX or 0xd800 <= scalar <= 0xdfff or type(sequence) is not list or not 1 <= len(sequence) < 255:
            raise RuntimeError('Normalization decomposition key/length differs')
        if any(type(member) is not int or not 0 <= member < MAX or 0xd800 <= member <= 0xdfff for member in sequence):
            raise RuntimeError('Normalization decomposition member type/bounds differ')
        previous = scalar
        decompositions[scalar] = tuple(sequence)
    if sum(map(len, decompositions.values())) != 3406:
        raise RuntimeError('Normalization decomposition scalar count differs')
    if sha(TABLE.read_bytes()) != TABLE_SHA:
        raise RuntimeError('Native normalization lookup source changed')
    return profile, ccc, compositions, decompositions


def queries(compositions):
    firsts = sorted({first for first, _ in compositions})
    seconds = sorted({second for _, second in compositions})
    result = {(first, second) for first in firsts for second in seconds}
    for first, second in compositions:
        for pair in ((first - 1, second), (first + 1, second), (first, second - 1), (first, second + 1)):
            if all(0 <= value <= 0xffffffff for value in pair):
                result.add(pair)
    for invalid in OUT_OF_RANGE:
        result.update((first, invalid) for first in firsts)
        result.update((invalid, second) for second in seconds)
        result.update((invalid, other) for other in OUT_OF_RANGE)
    return sorted(result), len(firsts) * len(seconds)


def expected(reference=ROOT / 'Reference'):
    _, ccc, compositions, decompositions = load_profile(reference)
    pairs, cross_count = queries(compositions)
    answers = bytearray()
    for scalar in range(MAX + len(OUT_OF_RANGE)):
        point = scalar if scalar < MAX else OUT_OF_RANGE[scalar - MAX]
        answers.append(ccc[point] if point < MAX else 0)
        sequence = decompositions.get(point)
        answers.append(len(sequence) if sequence is not None else 255)
        if sequence is not None:
            for member in sequence:
                answers.extend(member.to_bytes(4, 'big'))
        answers.extend(b'\xff' * 8)
    for pair in pairs:
        answers.extend(compositions.get(pair, 0xffffffff).to_bytes(4, 'big'))
    lookups = 4 * (MAX + len(OUT_OF_RANGE)) + len(pairs)
    query_bytes = ''.join(f'{first:x} {second:x}\n' for first, second in pairs).encode()
    if len(answers) != 11261090 or sha(answers) != PROJECTION_SHA or sha(query_bytes) != QUERY_SHA:
        raise RuntimeError('Frozen independent normalization projection differs')
    report = dict(status='passed', scope='native normalization table decoding only; no URL acceptance inferred',
                  nodeVersion='v26.5.0', nodeBinarySHA256=NODE_SHA, adaVersion='4.0.0',
                  normalizationProfileSHA256=PROFILE_SHA, propertyDataSourceSHA256=ADA_SHA,
                  generatedSourceSHA256=TABLE_SHA, probeRecipeSHA256=sha(DRIVER.encode()),
                  codepointCount=MAX, surrogateCodepointCount=0x800, outOfRangeCount=len(OUT_OF_RANGE),
                  combiningClassRanges=388, decompositionRecords=2061, decompositionScalars=3406,
                  compositionPairs=941, compositionCrossProductQueries=cross_count,
                  compositionAdditionalQueries=len(pairs), querySHA256=sha(query_bytes),
                  zeroAxisCompositionQueries=2 * (MAX + len(OUT_OF_RANGE)),
                  totalLookups=lookups, passed=lookups, failed=0,
                  negativeControlCount=13,
                  decodedPropertyByteCount=len(answers), decodedPropertyBytesSHA256=sha(answers))
    return report, answers, query_bytes


def check_report(actual, expected_report):
    if not same(actual, expected_report):
        raise RuntimeError('Normalization decoder report shape, value, or value type differs')


def negative_controls(report):
    mutations = [dict(passed=True), dict(failed=1), dict(codepointCount=MAX - 1),
                 dict(outOfRangeCount=0), dict(decompositionRecords=2060),
                 dict(compositionPairs=940), dict(compositionAdditionalQueries=0),
                 dict(decodedPropertyBytesSHA256='0' * 64), dict(normalizationProfileSHA256='0' * 64),
                 dict(generatedSourceSHA256='0' * 64), dict(nodeVersion='v26.6.0'), dict(extraClaim=True)]
    for mutation in mutations:
        modified = copy.deepcopy(report)
        modified.update(mutation)
        try:
            check_report(modified, report)
        except RuntimeError:
            continue
        raise RuntimeError('Normalization decoder negative control accepted: ' + str(mutation))
    duplicated = json.dumps(report)[:-1] + ',"status":"passed"}'
    try:
        json.loads(duplicated, object_pairs_hook=no_duplicates)
    except RuntimeError:
        pass
    else:
        raise RuntimeError('Duplicate normalization report key was accepted')
    count = len(mutations) + 1
    if report['negativeControlCount'] != count:
        raise RuntimeError('Normalization report-control inventory differs')
    return count


def source_array(section, name):
    matches = list(re.finditer(r'const\s+(uint8_t|uint16_t|char32_t)\s+' + re.escape(name) + r'((?:\[\d+\])+)\s*=\s*\{', section))
    if len(matches) != 1:
        raise RuntimeError('Ada data declaration count differs: ' + name)
    declaration = matches[0]
    dimensions = [int(value) for value in re.findall(r'\d+', declaration.group(2))]
    beginning = declaration.end() - 1
    level, ending = 0, None
    for offset in range(beginning, len(section)):
        if section[offset] == '{':
            level += 1
        elif section[offset] == '}':
            level -= 1
            if level == 0:
                ending = offset + 1
                break
    if ending is None:
        raise RuntimeError('Unterminated Ada data initializer: ' + name)
    text = section[beginning:ending]
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    values = ast.literal_eval(text.replace('{', '[').replace('}', ']'))
    ceiling = {'uint8_t': 255, 'uint16_t': 65535, 'char32_t': 0xffffffff}[declaration.group(1)]

    def padded(value, shape):
        if type(value) is not list or len(value) > shape[0]:
            raise RuntimeError('Ada data initializer shape differs: ' + name)
        if len(shape) == 1:
            if any(type(member) is not int or not 0 <= member <= ceiling for member in value):
                raise RuntimeError('Ada data initializer scalar differs: ' + name)
            return value + [0] * (shape[0] - len(value))
        rows = [padded(member, shape[1:]) for member in value]
        rows.extend(padded([], shape[1:]) for _ in range(shape[0] - len(value)))
        return rows

    return padded(values, dimensions), dimensions


def source_check(path, reference=ROOT / 'Reference'):
    profile, expected_ccc, expected_compositions, expected_decompositions = load_profile(reference)
    raw = Path(path).read_bytes()
    if sha(raw) != ADA_SHA:
        raise RuntimeError('Official Ada source bytes do not match the data-source pin')
    text = raw.decode('utf-8')
    section = text.split('/* begin file src/normalization_tables.cpp */', 1)[1].split('/* end file src/normalization_tables.cpp */', 1)[0]
    arrays, dimensions = {}, {}
    for name in ['canonical_combining_class_index', 'canonical_combining_class_block',
                 'composition_index', 'composition_block', 'composition_data',
                 'decomposition_index', 'decomposition_block', 'decomposition_data']:
        arrays[name], dimensions[name] = source_array(section, name)
    ccc = bytearray(MAX)
    compositions, decompositions = {}, {}
    for scalar in range(MAX):
        page, offset = scalar >> 8, scalar & 255
        block = arrays['canonical_combining_class_index'][page]
        ccc[scalar] = arrays['canonical_combining_class_block'][block][offset]
        block = arrays['composition_index'][page]
        first, last = arrays['composition_block'][block][offset:offset + 2]
        data = arrays['composition_data']
        if not 0 <= first <= last <= len(data) or (last - first) % 2:
            raise RuntimeError('Invalid Ada composition slice')
        for index in range(first, last, 2):
            compositions[scalar, data[index]] = data[index + 1]
        block = arrays['decomposition_index'][page]
        tagged_first, tagged_last = arrays['decomposition_block'][block][offset:offset + 2]
        first, last = tagged_first >> 2, tagged_last >> 2
        data = arrays['decomposition_data']
        if not 0 <= first <= last <= len(data):
            raise RuntimeError('Invalid Ada decomposition slice')
        if first != last and tagged_first & 1 == 0:
            decompositions[scalar] = tuple(data[first:last])
    if ccc != expected_ccc or compositions != expected_compositions or decompositions != expected_decompositions:
        raise RuntimeError('Frozen normalization profile differs from independent Ada data extraction')
    return dict(status='passed', scope='independent Ada property-data extraction only; source algorithm identity and URL acceptance not asserted',
                propertyDataSourceSHA256=ADA_SHA, normalizationProfileSHA256=PROFILE_SHA,
                codepointCount=MAX, combiningClassRanges=388, compositionPairs=len(compositions),
                decompositionRecords=len(decompositions), decompositionScalars=sum(map(len, decompositions.values())),
                rawCCCBytesSHA256=sha(ccc), sourceArrayDimensions=dimensions,
                compositionDataSHA256=sha(json.dumps([[a, b, value] for (a, b), value in sorted(compositions.items())], separators=(',', ':')).encode()),
                decompositionDataSHA256=sha(json.dumps([[scalar, list(sequence)] for scalar, sequence in sorted(decompositions.items())], separators=(',', ':')).encode()))


def probe(swiftc, answers, queries_bytes):
    with tempfile.TemporaryDirectory(prefix='lokalized-idna-normalization-tables-') as directory:
        scratch = Path(directory)
        driver = scratch / 'main.swift'
        driver.write_text(DRIVER)
        executable = scratch / 'normalization-table-probe'
        build = subprocess.run([swiftc, '-O', '-swift-version', '6', '-package-name', 'Lokalized',
                                '-module-cache-path', str(scratch / 'module-cache'), str(TABLE),
                                str(driver), '-o', str(executable)], capture_output=True)
        if build.returncode:
            raise RuntimeError('Normalization table probe build failed:\n' + build.stderr.decode(errors='replace'))
        result = subprocess.run([str(executable)], input=queries_bytes, capture_output=True)
        if result.returncode:
            raise RuntimeError('Normalization table probe failed:\n' + result.stderr.decode(errors='replace'))
        if result.stdout != answers:
            if len(result.stdout) != len(answers):
                raise RuntimeError('Normalization table projection byte count differs')
            offset = next(index for index, values in enumerate(zip(result.stdout, answers)) if values[0] != values[1])
            raise RuntimeError(f'Normalization table decoded data differs at byte {offset}')


def report_check(path, reference=ROOT / 'Reference'):
    report, _, _ = expected(reference)
    actual = json.loads(Path(path).read_bytes(), object_pairs_hook=no_duplicates)
    check_report(actual, report)
    negative_controls(report)
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--report-check', type=Path)
    mode.add_argument('--source-check', type=Path)
    parser.add_argument('--swiftc', default='swiftc')
    parser.add_argument('--reference', type=Path, default=ROOT / 'Reference')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.source_check:
        report = source_check(args.source_check, args.reference)
    else:
        report, answers, query_bytes = expected(args.reference)
        if args.check:
            probe(args.swiftc, answers, query_bytes)
        else:
            report_check(args.report_check, args.reference)
        negative_controls(report)
    output = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output)
    print(output, end='')


if __name__ == '__main__':
    main()
