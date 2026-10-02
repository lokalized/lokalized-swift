#!/usr/bin/env python3
"""Generate original lookup code for the separately frozen Node URL profile.

The input contains property data only, extracted from the SHA-pinned official
Node source. No upstream executable algorithms are copied or consulted by this
offline generator or by the consumer library. Actual compatibility behavior is
qualified against a separately pinned Node binary; source algorithm identity
is deliberately not asserted.
"""
import argparse
from URLOracle import property_inputs as shared_inputs
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE_SHA256 = '84ae2c73b06823e54716dff80f7f539e588a676e7ff8529424046fe34f7a1098'
LICENSE_SHA256 = 'af0d7d2cef91fc243cf4ad98570b03d1f26f5e0227cad0f5f4a7376e2feb3160'
SOURCE_SHA256 = 'ac8fba37ceddb7c10ca5a24fd57a0f0a0ca32cd3d391e40c6f9f6b7af3801fd4'
NODE_BINARY_SHA256 = '87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511'
OUTPUT = ROOT / 'Sources/Lokalized/Data/IDNACompatibilityProperties.swift'
BIDI = {'L': 0, 'R': 1, 'AL': 2, 'AN': 3, 'EN': 4, 'ES': 5,
        'CS': 6, 'ET': 7, 'ON': 8, 'BN': 9, 'NSM': 10}
JOINING = {'U': 0, 'L': 1, 'R': 2, 'D': 3}
MAX = 0x110000


def sha(value):
    return hashlib.sha256(value).hexdigest()


def load_profile(reference_directory=ROOT / 'Reference'):
    directory = Path(reference_directory) / 'IDNA-Compatibility'
    raw = (directory / 'property-profile.json').read_bytes()
    license_bytes = (directory / 'LICENSE-MIT.txt').read_bytes()
    if sha(raw) != PROFILE_SHA256 or sha(license_bytes) != LICENSE_SHA256:
        raise ValueError('IDNA compatibility property/license digest differs')
    profile = json.loads(raw)
    authority = profile['compatibilityAuthority']
    source = profile['propertyDataSource']
    if (profile['formatVersion'] != 1 or authority['nodeVersion'] != 'v26.5.0'
            or authority['adaVersion'] != '4.0.0' or authority['nodeBinarySHA256'] != NODE_BINARY_SHA256
            or source['sha256'] != SOURCE_SHA256 or source['section'] != 'src/validity.cpp'
            or profile['defaults'] != dict(mark=False, virama=False, joiningType='U', bidiClass='NONE')):
        raise ValueError('IDNA compatibility profile metadata differs')
    properties = profile['properties']
    counts = {'marks': 2295, 'viramas': 61}
    for name, count in counts.items():
        values = properties[name]
        if len(values) != count or values != sorted(set(values)) or any(type(cp) is not int or not 0 <= cp < MAX for cp in values):
            raise ValueError('IDNA compatibility scalar inventory differs: ' + name)
    joining = properties['joiningTypes']
    if set(joining) != {'L', 'R', 'D'} or {name: len(values) for name, values in joining.items()} != {'L': 1, 'R': 71, 'D': 326}:
        raise ValueError('IDNA compatibility joining inventory differs')
    seen = set()
    for values in joining.values():
        if values != sorted(set(values)) or seen.intersection(values):
            raise ValueError('IDNA compatibility joining data overlaps')
        seen.update(values)
    previous = -1
    ranges = properties['bidiClasses']
    if len(ranges) != 1449:
        raise ValueError('IDNA compatibility Bidi inventory differs')
    names = set(BIDI) | {'WS', 'RLO', 'LRO', 'PDF', 'RLE', 'RLI', 'FSI', 'PDI', 'LRI', 'B', 'S', 'LRE'}
    for first, last, value in ranges:
        if not previous < first <= last < MAX or value not in names:
            raise ValueError('IDNA compatibility Bidi ranges differ')
        previous = last
    return profile, license_bytes.decode('utf-8')


def coalesce(values, default):
    result = []
    first, previous = 0, values[0]
    for scalar in range(1, MAX + 1):
        value = values[scalar] if scalar < MAX else None
        if value != previous:
            if previous != default:
                result.append((first, scalar - 1, previous))
            first, previous = scalar, value
    return result


def property_arrays(profile, diagnostic_bidi_default=11):
    properties = profile['properties']
    mark, virama, joining = bytearray(MAX), bytearray(MAX), bytearray(MAX)
    bidi = bytearray([diagnostic_bidi_default]) * MAX
    for cp in properties['marks']:
        mark[cp] = 1
    for cp in properties['viramas']:
        virama[cp] = 1
    for name, values in properties['joiningTypes'].items():
        for cp in values:
            joining[cp] = JOINING[name]
    for first, last, name in properties['bidiClasses']:
        bidi[first:last + 1] = bytes([BIDI.get(name, 11)]) * (last - first + 1)
    return {'marks': mark, 'viramas': virama, 'joiningTypes': joining, 'bidiClasses': bidi}


def generate(profile, license_text):
    arrays = property_arrays(profile)
    encoded = {name: ''.join(f'{first:06x}{last:06x}{value:x}' for first, last, value in coalesce(values, 11 if name == 'bidiClasses' else 0))
               for name, values in arrays.items()}
    declarations = '\n'.join(f'    private static let {name}: StaticString = "{payload}"' for name, payload in encoded.items())
    notice = '\n'.join('// ' + line if line else '//' for line in license_text.rstrip().splitlines())
    return f'''// Generated by Tools/generate_idna_compatibility.py. Do not edit.
// Separately pinned Node 26.5.0 URL validity properties; this is not Unicode 17.
// Raw data, source SHA, compatibility authority and notices:
// Reference/IDNA-Compatibility/property-profile.json and README.md.
// Original lookup implementation; no upstream runtime algorithm is vendored.
{notice}
package enum IDNACompatibilityProperties {{
    package static let profileName = "Node 26.5.0 URL validity properties"
    // Joining: U=0,L=1,R=2,D=3. No transparent/join-causing membership is used.
    // Bidi: L=0,R=1,AL=2,AN=3,EN=4,ES=5,CS=6,ET=7,ON=8,BN=9,NSM=10,other=11.
{declarations}

    package static func isMark(_ scalar: UInt32) -> Bool {{ value(scalar, in: marks, default: 0) != 0 }}
    package static func isVirama(_ scalar: UInt32) -> Bool {{ value(scalar, in: viramas, default: 0) != 0 }}
    package static func joiningType(_ scalar: UInt32) -> UInt8 {{ value(scalar, in: joiningTypes, default: 0) }}
    package static func bidiClass(_ scalar: UInt32) -> UInt8 {{ value(scalar, in: bidiClasses, default: 11) }}

    private static func value(_ scalar: UInt32, in table: StaticString, default fallback: UInt8) -> UInt8 {{
        guard scalar <= 0x10ffff else {{ return fallback }}
        let bytes = table.utf8Start
        var low = 0, high = table.utf8CodeUnitCount / 13
        while low < high {{
            let middle = low + (high - low) / 2, offset = middle * 13
            if scalar < hex(bytes, offset, 6) {{ high = middle }}
            else if scalar > hex(bytes, offset + 6, 6) {{ low = middle + 1 }}
            else {{ return UInt8(hex(bytes, offset + 12, 1)) }}
        }}
        return fallback
    }}
    private static func hex(_ bytes: UnsafePointer<UInt8>, _ offset: Int, _ digits: Int) -> UInt32 {{
        var value: UInt32 = 0
        for index in offset..<(offset + digits) {{
            let byte = bytes[index]
            value = (value << 4) | UInt32(byte <= 57 ? byte - 48 : byte - 87)
        }}
        return value
    }}
}}
''', {name: len(payload) // 13 for name, payload in encoded.items()}


def property_discriminant_inputs(reference_directory=ROOT / 'Reference'):
    return shared_inputs.property_discriminant_inputs(reference_directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--write', action='store_true')
    parser.add_argument('--reference', type=Path, default=ROOT / 'Reference')
    args = parser.parse_args()
    profile, license_text = load_profile(args.reference)
    source, counts = generate(profile, license_text)
    if args.write:
        OUTPUT.write_text(source)
    elif OUTPUT.read_text() != source:
        raise ValueError('Generated IDNA compatibility properties differ')
    print(json.dumps(dict(status='passed', profileSHA256=PROFILE_SHA256, propertyDataSourceSHA256=SOURCE_SHA256,
                          generatedSourceSHA256=sha(source.encode()), generatedRanges=counts), sort_keys=True))


if __name__ == '__main__':
    main()
