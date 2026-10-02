#!/usr/bin/env python3
"""Exhaustively check native Unicode 17 table decoding against pinned raw data.

Development qualification only. Uses Python's standard library and swiftc;
no network, ICU APIs, host Unicode data, or consumer build hook is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import generate_idna_tables as generator

ROOT = Path(__file__).resolve().parents[1]
PROJECTION_SHA = 'de375da459ccff1ccb12ed6b8137019f84d0761f5a40585a34b4f586b05b5f62'
DRIVER = r'''
import Foundation
var output = Data()
output.reserveCapacity(9_000_000)
func append(_ value: UInt32) {
    output.append(UInt8(truncatingIfNeeded: value >> 24))
    output.append(UInt8(truncatingIfNeeded: value >> 16))
    output.append(UInt8(truncatingIfNeeded: value >> 8))
    output.append(UInt8(truncatingIfNeeded: value))
}
for scalar in UInt32(0)..<0x110000 {
    let mapping = IDNAUnicodeTables.mapping(scalar)
    output.append(mapping.status)
    output.append(IDNAUnicodeTables.combiningClass(scalar))
    output.append(IDNAUnicodeTables.isMark(scalar) ? 1 : 0)
    output.append(IDNAUnicodeTables.bidiClass(scalar))
    output.append(IDNAUnicodeTables.joiningType(scalar))
    output.append(UInt8(mapping.replacement.count))
    for member in mapping.replacement { append(member) }
    let decomposition = IDNAUnicodeTables.decomposition(scalar) ?? []
    output.append(UInt8(decomposition.count))
    for member in decomposition { append(member) }
    if decomposition.count == 2 {
        append(IDNAUnicodeTables.composition(decomposition[0], decomposition[1]) ?? 0xffffffff)
    }
}
FileHandle.standardOutput.write(output)
'''


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def rows(text):
    for line in text.splitlines():
        value = line.split('#', 1)[0].strip()
        if value:
            yield [field.strip() for field in value.split(';')]


def endpoints(value):
    split = value.split('..')
    return int(split[0], 16), int(split[-1], 16)


def property_values(text, names, default):
    values = bytearray([default]) * 0x110000
    for line in text.splitlines():
        if line.startswith('# @missing:'):
            first, last = endpoints(line.split(':', 1)[1].split(';', 1)[0].strip())
            name = line.split(';', 1)[1].strip()
            values[first:last + 1] = bytes([names.get(name, 11)]) * (last - first + 1)
    for row in rows(text):
        first, last = endpoints(row[0])
        values[first:last + 1] = bytes([names.get(row[1], 11)]) * (last - first + 1)
    return values


def expected_projection(texts):
    maximum = 0x110000
    classes, marks = bytearray(maximum), bytearray(maximum)
    decompositions, compositions = {}, {}
    first = None
    for row in rows(texts['UnicodeData.txt']):
        scalar = int(row[0], 16)
        if row[1].endswith(', First>'):
            first = scalar
            continue
        beginning = first if row[1].endswith(', Last>') else scalar
        if row[1].endswith(', Last>'):
            first = None
        classes[beginning:scalar + 1] = bytes([int(row[3])]) * (scalar - beginning + 1)
        if row[2][0] == 'M':
            marks[beginning:scalar + 1] = bytes([1]) * (scalar - beginning + 1)
        if row[5] and not row[5].startswith('<'):
            decompositions[scalar] = tuple(int(item, 16) for item in row[5].split())
    exclusions = set()
    for row in rows(texts['DerivedNormalizationProps.txt']):
        if row[1] == 'Full_Composition_Exclusion':
            first, last = endpoints(row[0])
            exclusions.update(range(first, last + 1))
    for scalar, sequence in decompositions.items():
        if len(sequence) == 2 and scalar not in exclusions:
            compositions[sequence] = scalar
    bidi_names = dict(L=0, R=1, AL=2, AN=3, EN=4, ES=5, CS=6, ET=7, ON=8, BN=9, NSM=10,
                      Left_To_Right=0, Right_To_Left=1, Arabic_Letter=2, European_Terminator=7)
    joining_names = dict(U=0, L=1, R=2, D=3, T=4, C=5, Non_Joining=0)
    bidi = property_values(texts['DerivedBidiClass.txt'], bidi_names, 0)
    joining = property_values(texts['DerivedJoiningType.txt'], joining_names, 0)
    status_codes = {'valid': 0, 'ignored': 1, 'mapped': 2, 'deviation': 3, 'disallowed': 4}
    mapping_rows = list(rows(texts['IdnaMappingTable.txt']))
    mapping_index = 0
    mapping_last = -1
    output = bytearray()
    pairs = 0
    for scalar in range(maximum):
        if scalar > mapping_last:
            row = mapping_rows[mapping_index]
            _, mapping_last = endpoints(row[0])
            mapping_index += 1
            status = status_codes[row[1]]
            replacement = tuple(int(item, 16) for item in row[2].split()) if len(row) > 2 else ()
        output.extend((status, classes[scalar], marks[scalar], bidi[scalar], joining[scalar], len(replacement)))
        for member in replacement:
            output.extend(member.to_bytes(4, 'big'))
        decomposition = decompositions.get(scalar, ())
        output.append(len(decomposition))
        for member in decomposition:
            output.extend(member.to_bytes(4, 'big'))
        if len(decomposition) == 2:
            output.extend(compositions.get(decomposition, 0xffffffff).to_bytes(4, 'big'))
            pairs += 1
    return bytes(output), pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', required=True)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    texts = generator.read_inputs()
    tables = generator.project(texts)
    source = generator.swift_source(tables, texts['LICENSE.txt'])
    if generator.OUTPUT.read_bytes() != source.encode('utf-8'):
        raise RuntimeError('Native source differs from offline data projection')
    expected, pairs = expected_projection(texts)
    if len(expected) != 7848540 or pairs != 1046 or digest(expected) != PROJECTION_SHA:
        raise RuntimeError('Frozen raw Unicode property projection inventory differs')
    with tempfile.TemporaryDirectory(prefix='lokalized-idna-tables-') as directory:
        temporary = Path(directory)
        driver = temporary / 'main.swift'
        driver.write_text(DRIVER, encoding='utf-8')
        binary = temporary / 'table-probe'
        result = subprocess.run(['swiftc', '-O', '-package-name', 'Lokalized', '-module-cache-path',
                                 '/private/tmp/lokalized-swift-module-cache', str(generator.OUTPUT),
                                 str(driver), '-o', str(binary)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        result = subprocess.run([str(binary)], capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
        if result.stdout != expected:
            offset = next((index for index, values in enumerate(zip(result.stdout, expected))
                           if values[0] != values[1]), min(len(result.stdout), len(expected)))
            raise RuntimeError(f'Native Unicode table projection differs at byte {offset}')
    report = dict(status='passed', unicodeVersion='17.0.0', codePointsChecked=0x110000,
                  validScalarsChecked=0x110000 - 0x800, surrogateCodePointsChecked=0x800,
                  canonicalCompositionPairsChecked=pairs, projectionByteCount=len(expected),
                  projectionSHA256=digest(expected), sourceSHA256=digest(source.encode('utf-8')),
                  failed=0, hostUnicodeAPIsUsed=False,
                  scope='mapping, CCC, Mark, bidi, joining, canonical decomposition, and all canonical pair results')
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    main()
