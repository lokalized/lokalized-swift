#!/usr/bin/env python3
"""Generate/check Unicode 17.0.0 IDNA and canonical normalization tables offline.

Only committed, SHA-pinned Unicode data inputs and the Python standard library
are used. This development tool is not part of a consumer build or runtime.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "Reference/Unicode-17.0.0"
OUTPUT = ROOT / "Sources/Lokalized/Data/IDNAUnicodeTables.swift"
LOCK = INPUT / "data-lock.json"
VERSION = "17.0.0"
PINS = {
    "IdnaMappingTable.txt": ("https://www.unicode.org/Public/17.0.0/idna/IdnaMappingTable.txt", "87f05505dc026fdb2bff16132bdc68a8014675836882a9a2b1844540ad3be382"),
    "UnicodeData.txt": ("https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt", "2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c"),
    "DerivedNormalizationProps.txt": ("https://www.unicode.org/Public/17.0.0/ucd/DerivedNormalizationProps.txt", "71fd6a206a2c0cdd41feb6b7f656aa31091db45e9cedc926985d718397f9e488"),
    "DerivedBidiClass.txt": ("https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedBidiClass.txt", "4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4"),
    "DerivedJoiningType.txt": ("https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedJoiningType.txt", "f39ebe974825d6736aee15582250307aa532b2cfab3caf3f86bd23fddc9c5c4d"),
    "NormalizationTest.txt": ("https://www.unicode.org/Public/17.0.0/ucd/NormalizationTest.txt", "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db"),
    "LICENSE.txt": ("https://www.unicode.org/license.txt", "e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96"),
}
STATUS = {"valid": 0, "ignored": 1, "mapped": 2, "deviation": 3, "disallowed": 4}
BIDI = {"L": 0, "R": 1, "AL": 2, "AN": 3, "EN": 4, "ES": 5,
        "CS": 6, "ET": 7, "ON": 8, "BN": 9, "NSM": 10}
BIDI_NAMES = {"Left_To_Right": "L", "Right_To_Left": "R", "Arabic_Letter": "AL",
              "Arabic_Number": "AN", "European_Number": "EN", "European_Separator": "ES",
              "Common_Separator": "CS", "European_Terminator": "ET", "Other_Neutral": "ON",
              "Boundary_Neutral": "BN", "Nonspacing_Mark": "NSM"}
JOINING = {"U": 0, "L": 1, "R": 2, "D": 3, "T": 4, "C": 5}
JOINING_NAMES = {"Non_Joining": "U", "Left_Joining": "L", "Right_Joining": "R",
                 "Dual_Joining": "D", "Transparent": "T", "Join_Causing": "C"}
MAX = 0x110000


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_inputs():
    texts = {}
    for name, (_, expected) in PINS.items():
        raw = (INPUT / name).read_bytes()
        if sha(raw) != expected:
            raise ValueError(f"Pinned Unicode input changed: {name}")
        texts[name] = raw.decode("utf-8")
    return texts


def interval(text):
    values = [int(part, 16) for part in text.strip().split("..")]
    if len(values) == 1:
        values *= 2
    if len(values) != 2 or not 0 <= values[0] <= values[1] < MAX:
        raise ValueError(f"Invalid Unicode interval: {text}")
    return values


def fields(text):
    for line in text.splitlines():
        data = line.split("#", 1)[0].strip()
        if data:
            yield [part.strip() for part in data.split(";")]


def ranges(values, default):
    """Coalesce scalar-indexed byte properties, omitting the default value."""
    result = []
    start, previous = 0, values[0]
    for scalar in range(1, MAX + 1):
        current = values[scalar] if scalar < MAX else None
        if current != previous:
            if previous != default:
                result.append((start, scalar - 1, previous))
            start, previous = scalar, current
    return result


def derived_property(text, codes, names, default, unknown=None):
    values = bytearray([default]) * MAX
    for line in text.splitlines():
        match = re.match(r"#\s*@missing:\s*([^;]+);\s*(\S+)", line)
        if match:
            first, last = interval(match.group(1))
            name = names.get(match.group(2), match.group(2))
            code = codes.get(name, unknown)
            if code is None:
                raise ValueError(f"Unknown missing property: {name}")
            values[first:last + 1] = bytes([code]) * (last - first + 1)
    assigned = bytearray(MAX)
    for row in fields(text):
        first, last = interval(row[0])
        name = names.get(row[1], row[1])
        code = codes.get(name, unknown)
        if code is None or any(assigned[first:last + 1]):
            raise ValueError(f"Unknown or overlapping Unicode property: {row}")
        values[first:last + 1] = bytes([code]) * (last - first + 1)
        assigned[first:last + 1] = bytes([1]) * (last - first + 1)
    return values


def project(texts):
    ccc, marks = bytearray(MAX), bytearray(MAX)
    decompositions = {}
    pending = None
    for row in fields(texts["UnicodeData.txt"]):
        scalar = int(row[0], 16)
        if row[1].endswith(", First>"):
            if pending is not None:
                raise ValueError("Nested UnicodeData range")
            pending = (scalar, row)
            continue
        if row[1].endswith(", Last>"):
            if pending is None or pending[1][2:] != row[2:]:
                raise ValueError("Mismatched UnicodeData range")
            first, _ = pending
            pending = None
        else:
            if pending is not None:
                raise ValueError("Unterminated UnicodeData range")
            first = scalar
        ccc[first:scalar + 1] = bytes([int(row[3])]) * (scalar - first + 1)
        if row[2].startswith("M"):
            marks[first:scalar + 1] = bytes([1]) * (scalar - first + 1)
        if row[5] and not row[5].startswith("<"):
            if first != scalar:
                raise ValueError("Unexpected range decomposition")
            decompositions[scalar] = tuple(int(item, 16) for item in row[5].split())
    if pending is not None:
        raise ValueError("Unterminated UnicodeData range")
    excluded = set()
    for row in fields(texts["DerivedNormalizationProps.txt"]):
        if row[1] == "Full_Composition_Exclusion":
            first, last = interval(row[0])
            excluded.update(range(first, last + 1))
    compositions = {}
    for scalar, sequence in decompositions.items():
        if len(sequence) == 2 and scalar not in excluded:
            if ccc[sequence[0]] != 0 or sequence in compositions:
                raise ValueError("Invalid canonical composition projection")
            compositions[sequence] = scalar
    bidi = derived_property(texts["DerivedBidiClass.txt"], BIDI, BIDI_NAMES, 0, 11)
    joining = derived_property(texts["DerivedJoiningType.txt"], JOINING, JOINING_NAMES, 0)
    sequences, sequence_offsets = [], {}

    def sequence_index(sequence):
        if not sequence:
            return 0
        if sequence not in sequence_offsets:
            sequence_offsets[sequence] = len(sequences)
            sequences.extend(sequence)
        return sequence_offsets[sequence]

    mappings = []
    next_scalar = 0
    for row in fields(texts["IdnaMappingTable.txt"]):
        first, last = interval(row[0])
        status = STATUS.get(row[1])
        if first != next_scalar or status is None:
            raise ValueError("Incomplete, unordered, or unknown IDNA mapping")
        next_scalar = last + 1
        replacement = tuple(int(item, 16) for item in row[2].split()) if len(row) > 2 else ()
        if replacement and status not in (2, 3):
            raise ValueError("Unexpected IDNA replacement")
        item = (first, last, status, sequence_index(replacement), len(replacement))
        if mappings and mappings[-1][1] + 1 == first and mappings[-1][2:] == item[2:]:
            mappings[-1] = (mappings[-1][0], last, *item[2:])
        else:
            mappings.append(item)
    if next_scalar != MAX:
        raise ValueError("Incomplete IDNA mapping coverage")
    decomposition_rows = [(scalar, sequence_index(sequence), len(sequence))
                          for scalar, sequence in sorted(decompositions.items())]
    if len(sequences) >= 0x1000000 or max(map(len, decompositions.values())) > 255:
        raise ValueError("Static sequence encoding overflow")
    encoded = {
        "mappings": (21, "".join(f"{a:06x}{b:06x}{s:x}{o:06x}{n:02x}" for a, b, s, o, n in mappings)),
        "combiningClasses": (14, "".join(f"{a:06x}{b:06x}{v:02x}" for a, b, v in ranges(ccc, 0))),
        "marks": (13, "".join(f"{a:06x}{b:06x}{v:x}" for a, b, v in ranges(marks, 0))),
        "bidiClasses": (13, "".join(f"{a:06x}{b:06x}{v:x}" for a, b, v in ranges(bidi, 0))),
        "joiningTypes": (13, "".join(f"{a:06x}{b:06x}{v:x}" for a, b, v in ranges(joining, 0))),
        "decompositions": (14, "".join(f"{s:06x}{o:06x}{n:02x}" for s, o, n in decomposition_rows)),
        "compositions": (18, "".join(f"{a:06x}{b:06x}{v:06x}" for (a, b), v in sorted(compositions.items()))),
        "scalarSequences": (6, "".join(f"{s:06x}" for s in sequences)),
    }
    if any(len(payload) % width for width, payload in encoded.values()):
        raise ValueError("Invalid fixed-width table")
    return encoded


def swift_source(tables, license_text):
    declarations = "\n".join(f'    private static let {name}: StaticString = "{payload}"' for name, (_, payload) in tables.items())
    notice = "\n".join("// " + line if line else "//" for line in license_text.rstrip().splitlines())
    return f'''// Generated by Tools/generate_idna_tables.py. Do not edit.
// Unicode {VERSION}; UTS #46 mapping and canonical normalization properties.
// Inputs and payload hashes: Reference/Unicode-17.0.0/data-lock.json.
// Independent of identifier Unicode 15.0 and runtime identity fields.
{notice}
package enum IDNAUnicodeTables {{
    package static let unicodeVersion = "{VERSION}"
    // Mapping: valid=0, ignored=1, mapped=2, deviation=3, disallowed=4.
    // Bidi: L=0,R=1,AL=2,AN=3,EN=4,ES=5,CS=6,ET=7,ON=8,BN=9,NSM=10,other=11.
    // Joining: U=0,L=1,R=2,D=3,T=4,C=5.
{declarations}

    package static func mapping(_ scalar: UInt32) -> (status: UInt8, replacement: [UInt32]) {{
        guard scalar <= 0x10ffff,
              let offset = rangeOffset(scalar, in: mappings, width: 21) else {{ return (4, []) }}
        let bytes = mappings.utf8Start
        return (UInt8(hex(bytes, offset + 12, 1)), sequence(bytes, offset + 13))
    }}

    package static func combiningClass(_ scalar: UInt32) -> UInt8 {{
        rangeValue(scalar, in: combiningClasses, width: 14, digits: 2)
    }}

    package static func isMark(_ scalar: UInt32) -> Bool {{
        rangeValue(scalar, in: marks, width: 13, digits: 1) != 0
    }}

    package static func bidiClass(_ scalar: UInt32) -> UInt8 {{
        guard scalar <= 0x10ffff else {{ return 11 }}
        return rangeValue(scalar, in: bidiClasses, width: 13, digits: 1)
    }}

    package static func joiningType(_ scalar: UInt32) -> UInt8 {{
        rangeValue(scalar, in: joiningTypes, width: 13, digits: 1)
    }}

    package static func decomposition(_ scalar: UInt32) -> [UInt32]? {{
        let bytes = decompositions.utf8Start
        var low = 0, high = decompositions.utf8CodeUnitCount / 14
        while low < high {{
            let middle = low + (high - low) / 2
            let offset = middle * 14
            let value = hex(bytes, offset, 6)
            if scalar < value {{ high = middle }}
            else if scalar > value {{ low = middle + 1 }}
            else {{ return sequence(bytes, offset + 6) }}
        }}
        return nil
    }}

    package static func composition(_ first: UInt32, _ second: UInt32) -> UInt32? {{
        guard first <= 0x10ffff, second <= 0x10ffff else {{ return nil }}
        let bytes = compositions.utf8Start
        let key = UInt64(first) << 24 | UInt64(second)
        var low = 0, high = compositions.utf8CodeUnitCount / 18
        while low < high {{
            let middle = low + (high - low) / 2
            let offset = middle * 18
            let value = UInt64(hex(bytes, offset, 6)) << 24 | UInt64(hex(bytes, offset + 6, 6))
            if key < value {{ high = middle }}
            else if key > value {{ low = middle + 1 }}
            else {{ return hex(bytes, offset + 12, 6) }}
        }}
        return nil
    }}

    private static func rangeOffset(_ scalar: UInt32, in table: StaticString, width: Int) -> Int? {{
        let bytes = table.utf8Start
        var low = 0, high = table.utf8CodeUnitCount / width
        while low < high {{
            let middle = low + (high - low) / 2
            let offset = middle * width
            let first = hex(bytes, offset, 6)
            let last = hex(bytes, offset + 6, 6)
            if scalar < first {{ high = middle }}
            else if scalar > last {{ low = middle + 1 }}
            else {{ return offset }}
        }}
        return nil
    }}

    private static func rangeValue(_ scalar: UInt32, in table: StaticString, width: Int, digits: Int) -> UInt8 {{
        guard let offset = rangeOffset(scalar, in: table, width: width) else {{ return 0 }}
        return UInt8(hex(table.utf8Start, offset + 12, digits))
    }}

    private static func sequence(_ bytes: UnsafePointer<UInt8>, _ offset: Int) -> [UInt32] {{
        let start = Int(hex(bytes, offset, 6))
        let count = Int(hex(bytes, offset + 6, 2))
        let payload = scalarSequences.utf8Start
        return (start..<(start + count)).map {{ hex(payload, $0 * 6, 6) }}
    }}

    private static func hex(_ bytes: UnsafePointer<UInt8>, _ offset: Int, _ count: Int) -> UInt32 {{
        var result: UInt32 = 0
        for index in offset..<(offset + count) {{
            let byte = bytes[index]
            result = result << 4 | UInt32(byte <= 57 ? byte - 48 : byte - 87)
        }}
        return result
    }}
}}
'''


def lock_data(tables, source):
    return {
        "formatVersion": 1, "unicodeVersion": VERSION,
        "scope": "UTS #46 IDNA mapping; NFC canonical decomposition/composition; CCC; General_Category=Mark; RFC 5893 bidi classes; RFC 5892 joining types",
        "generator": {"path": "Tools/generate_idna_tables.py", "sha256": sha(Path(__file__).read_bytes())},
        "inputs": {name: {"url": url, "sha256": digest, "byteCount": (INPUT / name).stat().st_size}
                   for name, (url, digest) in PINS.items()},
        "tables": {name: {"recordWidth": width, "recordCount": len(payload) // width,
                           "sha256": sha(payload.encode("ascii"))} for name, (width, payload) in tables.items()},
        "output": {"path": "Sources/Lokalized/Data/IDNAUnicodeTables.swift", "sha256": sha(source.encode("utf-8"))},
        "normalization": "Canonical-only UnicodeData decomposition; Full_Composition_Exclusion removes forbidden pairs; Hangul normalization is algorithmic in PinnedNFC",
        "defaults": "All @missing derived-property defaults applied before explicit rows; L and U table defaults omitted",
        "consumerPolicy": "Committed Swift StaticString constants only; no host Unicode/ICU data; no generator/network/build hook; zero external runtime dependencies",
        "license": "UNICODE LICENSE V3; complete notice also embedded in generated Swift source",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--generate", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    texts = read_inputs()
    tables = project(texts)
    source = swift_source(tables, texts["LICENSE.txt"])
    lock = json.dumps(lock_data(tables, source), ensure_ascii=False, indent=2) + "\n"
    if args.generate:
        OUTPUT.write_text(source, encoding="utf-8")
        LOCK.write_text(lock, encoding="utf-8")
    elif OUTPUT.read_bytes() != source.encode("utf-8") or LOCK.read_bytes() != lock.encode("utf-8"):
        raise ValueError("Unicode IDNA generated source or lock differs from pinned offline projection")
    print(json.dumps({"status": "passed", "unicodeVersion": VERSION,
                      "tableRecords": {name: len(payload) // width for name, (width, payload) in tables.items()},
                      "swiftSourceSHA256": sha(source.encode("utf-8")), "mode": "generate" if args.generate else "check"}))


if __name__ == "__main__":
    main()
