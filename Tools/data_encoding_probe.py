#!/usr/bin/env python3
"""Measure a compiled UTF-8 StaticString + offsets candidate using pinned exports.

Development only: Python standard library + selected Apple swiftc. No network,
consumer build hook, package plugin, external dependency or core Sources changes.
The experimental records retain complete JSON exports, not final M2/M3 schemas.
"""

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
INPUTS = [
    ("cldr-locale-data.json", "6241d8889b507a6edc0d6dae7e7812c372b62208ba8649701a819de877eade93"),
    ("cldr-plural-data.json", "7ade4692762aac80144f915b62de19f29eb039ec3cf28c3f9f2c34b810cdc0e7"),
    ("iana-language-equivalences.json", "2398b866e6739ae81d9484da929567e68e8255fe31aefe5bf2ef25846c611462"),
]
MASK = (1 << 64) - 1


@dataclass(frozen=True)
class NumberLexeme:
    text: str


def load_exact(data):
    def object_members(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON member: {key!r}")
            result[key] = value
        return result

    def invalid_constant(text):
        raise ValueError(f"Non-JSON number: {text}")

    # json.loads rejects trailing input; strict UTF-8 rejects encoded surrogates.
    return json.loads(data.decode("utf-8"), parse_int=NumberLexeme,
                      parse_float=NumberLexeme, parse_constant=invalid_constant,
                      object_pairs_hook=object_members)


def compact(value):
    if isinstance(value, NumberLexeme):
        return value.text
    if isinstance(value, str):
        value.encode("utf-8")  # Reject unpaired surrogate escape results.
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, list):
        return "[" + ",".join(compact(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(compact(key) + ":" + compact(item) for key, item in value.items()) + "}"
    raise ValueError(f"Unexpected JSON value: {type(value)}")


def fnv64(data):
    checksum = 14695981039346656037
    for byte in data:
        checksum = ((checksum ^ byte) * 1099511628211) & MASK
    return checksum


def lexical_self_test():
    sample = '{"decimal":1.2300,"exponent":1E+0003,"negativeZero":-0,"text":"e\\u0301😀","escaped":"\\n"}'.encode("utf-8")
    original = load_exact(sample)
    encoded = compact(original).encode("utf-8")
    if load_exact(encoded) != original or b"1.2300" not in encoded or b"1E+0003" not in encoded or b"-0" not in encoded:
        raise ValueError("Exact numeric/string encoding self-test failed")
    for bad in [b'{"a":1,"a":2}', b'{}{}', b'{"x":NaN}', b'{"x":"\\ud800"}', b'"\xed\xa0\x80"']:
        try:
            compact(load_exact(bad))
        except (ValueError, UnicodeError):
            continue
        raise ValueError("Invalid encoded input accepted by self-test")


def source_for(payloads):
    entries = []
    offset = 0
    for data in payloads:
        entries.append((offset, len(data), fnv64(data)))
        offset += len(data) + 1
    blob = b"\n".join(payloads)
    text = blob.decode("utf-8")
    hashes = "#"
    while ('"""' + hashes) in text or ("\\" + hashes + "(") in text:
        hashes += "#"
    literal = hashes + '"""\n' + text + '\n"""' + hashes
    rows = ",\n        ".join(f"Entry(offset: {offset}, length: {length}, checksum: {checksum})" for offset, length, checksum in entries)
    expected = sum(entry[2] for entry in entries) & MASK
    swift = SWIFT_TEMPLATE.replace("__PAYLOAD__", literal).replace("__ROWS__", rows).replace("__EXPECTED__", str(expected))
    return swift, blob, entries, expected


SWIFT_TEMPLATE = r'''import Foundation
import Darwin

struct Entry { let offset: Int; let length: Int; let checksum: UInt64 }
enum Tables {
    static let blob: StaticString = __PAYLOAD__
    static let index: [Entry] = [__ROWS__]
}
func heapBytes() -> UInt64 {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats) // Apple SDK: nil sums all malloc zones.
    return UInt64(stats.size_in_use)
}
func nanoseconds() -> UInt64 {
    var now = timespec()
    precondition(clock_gettime(CLOCK_MONOTONIC_RAW, &now) == 0)
    return UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
}
@inline(never) func readEntries(_ bytes: UnsafePointer<UInt8>, _ entries: [Entry]) -> UInt64 {
    var total: UInt64 = 0
    for entry in entries {
        var checksum: UInt64 = 14695981039346656037
        for offset in entry.offset..<(entry.offset + entry.length) {
            checksum = (checksum ^ UInt64(bytes[offset])) &* 1099511628211
        }
        precondition(checksum == entry.checksum, "Encoded record checksum mismatch")
        total = total &+ checksum
    }
    return total
}
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "compact"
let rounds = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 25
precondition(mode == "compact" || mode == "eager" || mode == "control")
precondition(rounds > 0 && rounds <= 10_000)
_ = heapBytes(); _ = nanoseconds() // Warm measurement helpers before snapshot.
let before = heapBytes()
let start = nanoseconds()
let blob = Tables.blob
let entries = Tables.index
let bytes = blob.utf8Start
var cursor = 0
for (index, entry) in entries.enumerated() {
    precondition(entry.offset == cursor && entry.length > 0)
    precondition(entry.offset <= blob.utf8CodeUnitCount && entry.length <= blob.utf8CodeUnitCount - entry.offset)
    cursor += entry.length
    if index + 1 < entries.count { precondition(bytes[cursor] == 10); cursor += 1 }
}
precondition(cursor == blob.utf8CodeUnitCount, "Unindexed trailing data")
var decoded: [Any] = []
if mode == "eager" {
    for entry in entries {
        let data = Data(bytes: bytes.advanced(by: entry.offset), count: entry.length)
        decoded.append(try JSONSerialization.jsonObject(with: data))
    }
}
let initialized = nanoseconds()
let afterInitialization = heapBytes()
let firstStarted = nanoseconds()
let first = readEntries(bytes, entries)
precondition(first == __EXPECTED__)
let afterFirst = nanoseconds()
let firstHeap = heapBytes()
var repeated: UInt64 = 0
let repeatedStarted = nanoseconds()
for round in 0..<rounds { repeated = repeated &+ readEntries(bytes, entries) &+ UInt64(round) }
let afterRepeated = nanoseconds()
let lastHeap = heapBytes()
let expectedRepeated = UInt64(__EXPECTED__) &* UInt64(rounds) &+ UInt64(rounds * (rounds - 1) / 2)
precondition(repeated == expectedRepeated)
var usage = rusage()
precondition(getrusage(RUSAGE_SELF, &usage) == 0)
withExtendedLifetime(decoded) {
    print("{\"mode\":\"\(mode)\",\"payloadBytes\":\(blob.utf8CodeUnitCount),\"records\":\(entries.count),\"indexLogicalBytes\":\(entries.count * MemoryLayout<Entry>.stride),\"initializationNs\":\(initialized-start),\"initializationHeapDeltaBytes\":\(Int64(afterInitialization)-Int64(before)),\"firstReadNs\":\(afterFirst-firstStarted),\"firstReadHeapDeltaBytes\":\(Int64(firstHeap)-Int64(afterInitialization)),\"repeatedReadNs\":\(afterRepeated-repeatedStarted),\"repeatedReadHeapDeltaBytes\":\(Int64(lastHeap)-Int64(firstHeap)),\"rounds\":\(rounds),\"firstChecksum\":\"\(first)\",\"repeatedChecksum\":\"\(repeated)\",\"decodedExports\":\(decoded.count),\"peakResidentBytes\":\(usage.ru_maxrss)}")
}
'''


def invoke(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{arguments[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout.strip()


def compile_swift(source, output, cache):
    start = time.perf_counter_ns()
    invoke(["swiftc", "-O", "-whole-module-optimization", "-module-cache-path", str(cache), str(source), "-o", str(output)])
    return time.perf_counter_ns() - start


def run_probe(args, work):
    lexical_self_test()
    inputs = []
    payloads = []
    for name, digest in INPUTS:
        source = (args.reference / name).read_bytes()
        if hashlib.sha256(source).hexdigest() != digest:
            raise ValueError(f"{name}: pinned source SHA-256 mismatch")
        value = load_exact(source)
        data = compact(value).encode("utf-8")
        if load_exact(data) != value:
            raise ValueError(f"{name}: compact export changed a number lexeme/string/value")
        inputs.append({"path": name, "sourceBytes": len(source), "sourceSHA256": digest, "compactBytes": len(data)})
        payloads.append(data)
    source, blob, entries, expected = source_for(payloads)
    source_path = work / "DataEncodingProbe.swift"
    source_path.write_text(source, encoding="utf-8")
    # Empty-data harness has the same imports/measurement/checksum routines.
    control_source, _, _, _ = source_for([])
    control_path = work / "Control.swift"
    control_path.write_text(control_source, encoding="utf-8")
    cache = work / "ModuleCache"
    warmup = compile_swift(control_path, work / "Warmup", cache)
    compile_times = {"control": [], "compact": []}
    binaries = {}
    for kind, path in [("control", control_path), ("compact", source_path)]:
        for repetition in range(args.samples):
            binary = work / f"{kind}-{repetition}"
            compile_times[kind].append(compile_swift(path, binary, cache))
            binaries[kind] = binary
    runtime = {}
    for mode in ["control", "compact", "eager"]:
        binary = binaries["control" if mode == "control" else "compact"]
        samples = [json.loads(invoke([str(binary), mode, str(args.rounds)])) for _ in range(args.samples)]
        expected_checksum = "0" if mode == "control" else str(expected)
        if any(sample["firstChecksum"] != expected_checksum for sample in samples):
            raise ValueError("Independent runtime checksum mismatch")
        runtime[mode] = {"samples": samples, "median": {
            key: statistics.median(sample[key] for sample in samples)
            for key in ["initializationNs", "initializationHeapDeltaBytes", "firstReadNs", "firstReadHeapDeltaBytes", "repeatedReadNs", "repeatedReadHeapDeltaBytes", "peakResidentBytes"]
        }}
    version = invoke(["swiftc", "--version"])
    return {
        "formatVersion": 1, "status": "measured", "encoding": "compiled compact UTF-8 StaticString with contiguous offset/length/checksum index",
        "decisionScope": "initial M2/M3 representation family; experimental whole-export JSON records, not final typed schemas or localization behavior",
        "sourceInputs": inputs, "payloadBytes": len(blob), "payloadSHA256": hashlib.sha256(blob).hexdigest(),
        "generatedSwiftSHA256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "indexRecords": len(entries), "indexLogicalBytes64Bit": len(entries) * 24,
        "integrity": "original inputs independently SHA-256 pinned; exact JSON numbers and strings round-trip; runtime per-record FNV-1a checksums, contiguous bounds and final consumed-length validation",
        "compiler": version, "sdk": invoke(["xcrun", "--show-sdk-path"]),
        "sdkVersion": invoke(["xcrun", "--show-sdk-version"]), "xcode": invoke(["xcodebuild", "-version"]), "host": platform.platform(),
        "hostArchitecture": platform.machine(), "minimumSwift62Executed": "Swift version 6.2 " in version,
        "compilerCachePolicy": "fresh application compilations, -O whole-module optimization; one excluded warmup populated a shared system SDK module cache; no incremental application objects",
        "compileTargetPolicy": "swiftc default target for selected host; not a minimum-OS build",
        "excludedSDKWarmupNs": warmup, "compileNs": compile_times,
        "compileMedianNs": {key: statistics.median(values) for key, values in compile_times.items()},
        "binaryBytes": {key: path.stat().st_size for key, path in binaries.items()},
        "binaryBytesDelta": binaries["compact"].stat().st_size - binaries["control"].stat().st_size,
        "heapPolicy": "malloc_zone_statistics(nil) sums live requested bytes across Apple malloc zones; snapshots follow warmed helpers and precede report formatting; decoder objects held alive; not allocation counts or process RSS",
        "runtime": runtime,
        "limitations": ["Current host/toolchain only; no Swift 6.2, minimum-OS, Intel, iOS or device measurements unless reported explicitly.", "Process/OS page and filesystem caches are not flushed; cold means fresh application compilation/process, not cold hardware.", "Whole-export eager Foundation JSON decode is a heap/init control; it is not an exact-decimal production decoder or a proposed runtime dependency.", "No expression-heavy full Swift table literal comparison was compiled; final typed schemas/index sizes must be remeasured in M2/M3."],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--rounds", type=int, default=25)
    parser.add_argument("--work-dir", type=Path, help="retain generated Swift, binaries and module cache in this directory")
    parser.add_argument("--report", type=Path, help="write measured JSON report here")
    args = parser.parse_args()
    if not 1 <= args.samples <= 20 or not 1 <= args.rounds <= 10_000:
        parser.error("samples must be 1...20 and rounds 1...10000")
    if sys.platform != "darwin":
        parser.error("This measurement requires Apple Swift/Darwin malloc statistics")
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=True)
        report = run_probe(args, args.work_dir.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="lokalized-data-encoding-") as temporary:
            report = run_probe(args, Path(temporary))
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, TypeError) as error:
        print(f"Data encoding experiment failed: {error}", file=sys.stderr)
        sys.exit(1)
