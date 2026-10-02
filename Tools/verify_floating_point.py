#!/usr/bin/env python3
"""Self-contained Swift golden check, or explicit pinned-JDK differential probe.
Python standard library only. Java is development-only and never fetched.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import platform
import struct
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/Lokalized/Numeric/JavaFloatingPoint.swift"
ORACLE = ROOT / "Tools/FloatingPointOracle.java"
GOLDENS = ROOT / "Reference/floating-point-goldens.json"
GOLDENS_SHA256 = "a6320c2ba4d9154352b3eeb1aeb520f989a8f783039414034c2da3e2cc10de1c"
RELEASE_SHA256 = "31c8dd26f07b2bd2c394663b57a93879ea139f525c76c730b13956890c151239"
JDK_SOURCES = {
    "java.base/java/lang/Float.java": "cb82e6f79de34e09e62e9be3dfd8c8e180319fce76d34f7769f8689d4920fd24",
    "java.base/java/lang/Double.java": "67b1cc47b33b99eab0d2f41da98b2d84ebc5e727cac4c09badca043bb5ea2a39",
    "java.base/jdk/internal/math/FloatToDecimal.java": "7424783724b75cda0eaebc7d42e81e91c25a1eac243ebe3fdf9d2770ca4d0228",
    "java.base/jdk/internal/math/DoubleToDecimal.java": "3317806f576950308c67c11be997f45d83691258eec9b9166120df85a0cdae0e",
    "java.base/jdk/internal/math/MathUtils.java": "bdc4f9def2088610109f74a01ce79c21202f824b059bea0d213ed94000bbff2c",
}
SEED = 0x8D351A69C27F045B
SWIFT_DRIVER = """while let line = readLine() {
    let fields = line.split(separator: "\\t", omittingEmptySubsequences: false)
    precondition(fields.count == 2)
    if fields[0] == "float" {
        let value = Float(bitPattern: UInt32(fields[1], radix: 16)!)
        let decimal = JavaFloatingPoint.decimalString(value)
        precondition(decimal == JavaFloatingPoint.render(value))
        print(decimal)
    } else {
        precondition(fields[0] == "double")
        let value = Double(bitPattern: UInt64(fields[1], radix: 16)!)
        let decimal = JavaFloatingPoint.decimalString(value)
        precondition(decimal == JavaFloatingPoint.render(value))
        print(decimal)
    }
}
"""


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], *, input_bytes: bytes | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(command, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(f"Command failed ({result.returncode}): {command}\n{result.stderr.decode(errors='replace')}")
    return result


def verify_jdk(jdk: Path) -> dict:
    release = (jdk / "release").read_bytes()
    if sha(release) != RELEASE_SHA256:
        raise ValueError("JDK release bytes do not match pinned Corretto 21.0.11")
    with zipfile.ZipFile(jdk / "lib/src.zip") as archive:
        for name, expected in JDK_SOURCES.items():
            if sha(archive.read(name)) != expected:
                raise ValueError(f"JDK source pin differs: {name}")
    version = run([str(jdk / "bin/java"), "-version"]).stderr.decode()
    if '"21.0.11"' not in version or "Corretto-21.0.11.10.1" not in version:
        raise ValueError("Java executable does not identify the pinned version/vendor/build")
    return {"vendor": "Amazon.com Inc.", "javaVersion": "21.0.11", "build": "Corretto-21.0.11.10.1",
            "releaseSHA256": RELEASE_SHA256, "sources": JDK_SOURCES, "versionOutput": version}


def random_words(seed: int):
    # Fixed xorshift64, avoiding Python random module/version state conventions.
    state = seed
    mask = (1 << 64) - 1
    while True:
        state ^= (state << 13) & mask
        state ^= state >> 7
        state ^= (state << 17) & mask
        state &= mask
        yield state


def sample_set(*, full_edges: bool, random_count: int) -> list[tuple[str, int]]:
    samples: set[tuple[str, int]] = set()
    for width, fraction_bits, exponent_bits in [("float", 23, 8), ("double", 52, 11)]:
        sign = 1 << (fraction_bits + exponent_bits)
        fraction_mask = (1 << fraction_bits) - 1
        exponent_max = (1 << exponent_bits) - 1
        positive: set[int] = {0, sign - 1, exponent_max << fraction_bits,
                              (exponent_max << fraction_bits) | 1,
                              (exponent_max << fraction_bits) | (1 << (fraction_bits - 1)),
                              (exponent_max << fraction_bits) | fraction_mask}
        positive.update(range(0, 2049 if width == "float" and full_edges else 257 if full_edges else 33))
        for boundary in [1 << fraction_bits, exponent_max << fraction_bits]:
            positive.update(range(boundary - 16, boundary + 17))
        exponents = range(1, exponent_max) if full_edges else [1, 2, 3, 20, exponent_max // 2 - 1,
                  exponent_max // 2, exponent_max // 2 + 1, exponent_max - 3, exponent_max - 2, exponent_max - 1]
        for exponent in exponents:
            for fraction in [0, 1, 2, fraction_mask - 1, fraction_mask]:
                positive.add((exponent << fraction_bits) | fraction)
        # Explicit exact ties of closest minimal-length decimals, even-significand wins.
        positive.update([0x4a000001, 0x4a000003] if width == "float" else
                        [0x4300000000000002, 0x4300000000000006])
        decades = range(-45, 39) if width == "float" and full_edges else range(-324, 309) if full_edges else [-45, -44, -4, -3, -1, 0, 6, 7, 23, 38]
        for exponent in decades:
            value = float(f"1e{exponent}")
            try:
                raw = int.from_bytes(struct.pack(">f" if width == "float" else ">d", value), "big")
            except OverflowError:
                continue
            for offset in range(-3, 4):
                if 0 <= raw + offset < sign: positive.add(raw + offset)
        for bits in positive:
            samples.add((width, bits))
            samples.add((width, bits | sign))
    words = random_words(SEED)
    for _ in range(random_count):
        samples.add(("float", next(words) & 0xffffffff))
        samples.add(("double", next(words)))
    return sorted(samples, key=lambda entry: (entry[0], entry[1]))


def encoded_inputs(samples: list[tuple[str, int]]) -> bytes:
    return "".join(f"{width}\t{bits:0{8 if width == 'float' else 16}x}\n" for width, bits in samples).encode("ascii")


def compile_swift(scratch: Path, swiftc: str) -> tuple[Path, dict]:
    driver = scratch / "main.swift"
    driver.write_text(SWIFT_DRIVER)
    executable = scratch / "floating-point-check"
    started = time.monotonic_ns()
    run([swiftc, "-O", "-swift-version", "6", "-package-name", "Lokalized",
         "-module-cache-path", str(scratch / "module-cache"), str(SOURCE), str(driver), "-o", str(executable)])
    return executable, {"swiftVersion": run([swiftc, "--version"]).stdout.decode(),
                        "compileNanoseconds": time.monotonic_ns() - started,
                        "sourceSHA256": sha(SOURCE.read_bytes()), "driverSHA256": sha(driver.read_bytes())}


def outputs(command: list[str], inputs: bytes, expected_count: int) -> tuple[list[str], int]:
    started = time.monotonic_ns()
    data = run(command, input_bytes=inputs).stdout
    elapsed = time.monotonic_ns() - started
    lines = data.decode("ascii").splitlines()
    if len(lines) != expected_count:
        raise ValueError(f"Expected {expected_count} output lines, received {len(lines)}")
    return lines, elapsed


def compare(samples, actual, expected):
    differences = [{"width": width, "bits": f"{bits:0{8 if width == 'float' else 16}x}",
                    "actual": a, "expected": e}
                   for (width, bits), a, e in zip(samples, actual, expected) if a != e]
    if differences:
        raise ValueError(f"{len(differences)} conversion differences: " + json.dumps(differences[:20]))


def load_goldens() -> tuple[dict, list[tuple[str, int]], list[str]]:
    data = GOLDENS.read_bytes()
    if sha(data) != GOLDENS_SHA256:
        raise ValueError("Checked-in floating golden bytes differ from fixed tool pin")
    archive = json.loads(data)
    if archive["formatVersion"] != 1 or archive["jdk"]["releaseSHA256"] != RELEASE_SHA256 or archive["jdk"]["sources"] != JDK_SOURCES:
        raise ValueError("Unexpected golden format or oracle provenance")
    if archive["oracleSourceSHA256"] != sha(ORACLE.read_bytes()):
        raise ValueError("Golden oracle program provenance differs")
    samples = [(entry["width"], int(entry["bits"], 16)) for entry in archive["samples"]]
    expected_samples = sample_set(full_edges=False, random_count=384)
    if samples != expected_samples:
        raise ValueError("Golden bit inventory differs from independently generated fixed inventory")
    if archive["inputSHA256"] != sha(encoded_inputs(samples)):
        raise ValueError("Golden input digest differs")
    return archive, samples, [entry["decimal"] for entry in archive["samples"]]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Run Swift against pinned local goldens; no Java/siblings/network")
    mode.add_argument("--oracle", action="store_true", help="Run a broad explicit pinned-JDK differential")
    mode.add_argument("--refresh-goldens", action="store_true", help="Explicitly recreate the small native bit golden inventory")
    parser.add_argument("--jdk", type=Path, help="Explicit local Corretto 21.0.11 home (required for oracle/refresh)")
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--random-count", type=int, default=32768, help="Independent raw-bit random samples per width, oracle only")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.random_count < 0 or args.random_count > 1_000_000:
        raise ValueError("random-count must be within 0...1000000")
    if not args.check and args.jdk is None:
        raise ValueError("--jdk is required; no JDK is inferred or downloaded")
    jdk = verify_jdk(args.jdk.resolve()) if not args.check else None
    with tempfile.TemporaryDirectory(prefix="lokalized-floating-point-") as directory:
        scratch = Path(directory)
        executable, swift = compile_swift(scratch, args.swiftc)
        if args.check:
            _, samples, expected = load_goldens()
        else:
            samples = sample_set(full_edges=not args.refresh_goldens,
                                 random_count=384 if args.refresh_goldens else args.random_count)
            run([str(args.jdk / "bin/javac"), "-d", str(scratch), str(ORACLE)])
            expected, java_ns = outputs([str(args.jdk / "bin/java"), "-cp", str(scratch), "FloatingPointOracle"],
                                        encoded_inputs(samples), len(samples))
        inputs = encoded_inputs(samples)
        actual, swift_ns = outputs([str(executable)], inputs, len(samples))
        compare(samples, actual, expected)
        if args.refresh_goldens:
            archive = {"formatVersion": 1, "selection": "Java21 shortest/one-or-two-digit, closest, even-significand tie",
                       "jdk": jdk, "oracleSourceSHA256": sha(ORACLE.read_bytes()), "seed": f"{SEED:016x}",
                       "inputSHA256": sha(inputs), "samples": [
                           {"width": width, "bits": f"{bits:0{8 if width == 'float' else 16}x}", "decimal": decimal}
                           for (width, bits), decimal in zip(samples, expected)]}
            data = (json.dumps(archive, ensure_ascii=True, indent=2) + "\n").encode()
            GOLDENS.write_bytes(data)
            print(f"Golden SHA256: {sha(data)} ({len(samples)} samples)")
        report = {"formatVersion": 1, "mode": "goldens" if args.check else "jdk-oracle",
                  "passed": len(samples), "failed": 0, "floatCount": sum(w == "float" for w, _ in samples),
                  "doubleCount": sum(w == "double" for w, _ in samples), "inputSHA256": sha(inputs),
                  "outputSHA256": sha(("\n".join(actual) + "\n").encode("ascii")),
                  "randomSamplesPerWidth": 384 if args.refresh_goldens or args.check else args.random_count,
                  "seed": f"{SEED:016x}", "jdk": jdk, "swift": swift,
                  "oracleSourceSHA256": sha(ORACLE.read_bytes()), "swiftExecutionNanoseconds": swift_ns,
                  "platform": platform.platform(), "architecture": platform.machine()}
        if not args.check: report["javaExecutionNanoseconds"] = java_ns
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Floating-point {report['mode']}: {len(samples)} passed, 0 failed; float={report['floatCount']}, double={report['doubleCount']}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        print(f"Floating-point verification failed: {error}", file=sys.stderr)
        sys.exit(1)
