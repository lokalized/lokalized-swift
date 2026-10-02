#!/usr/bin/env python3
"""Compare actual Swift numeric APIs with the pinned JDK's exact BigDecimal.

Development only: Python stdlib, swiftc, and the explicit pinned JDK are required.
No sibling checkout, dependency resolver, reference expected values, or download
participates. Example:
  python3 Tools/verify_numeric.py --java-home /path/to/pinned/jdk

The 632 deterministic inputs cover decimal representation, exact small modulus,
rounding refusal, and CLDR operand derivation. The declared Swift/JS convention
normalizes a negative-scale remainder to scale zero; the JDK oracle explicitly
normalizes that field before comparison. This does not test floating conversion
or plural category tables; their separate qualification must still run.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import random
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SWIFT_CONSUMER = r'''import Foundation
import Lokalized
for line in String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n") {
    let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    do {
        let d = try ExactDecimal(cells[0])
        let divisor = Int(cells[1])!
        let visible = cells[2] == "-" ? nil : Int(cells[2])
        let o = try PluralOperands(.decimal(d), visibleDecimalPlaces: visible, compactExponent: Int(cells[3])!)
        let r = try d.remainder(dividingBy: divisor)
        print([d.description, d.plainString, String(d.scale), String(d.precision), String(d.signum),
               r.description, r.plainString, String(r.scale), o.n.description, o.n.plainString,
               o.i.plainString, String(o.v), String(o.w), o.f.plainString, o.t.plainString,
               String(o.e), o.sourceNumber.description].joined(separator: "\t"))
    } catch { print("ERROR\t" + String(describing: error)) }
}
'''

JAVA_ORACLE = r'''import java.io.*;
import java.math.*;
public final class DecimalOracle {
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = reader.readLine()) != null) {
            String[] c = line.split("\\t", -1);
            try {
                BigDecimal d = new BigDecimal(c[0]);
                int modulus = Integer.parseInt(c[1]), exponent = Integer.parseInt(c[3]);
                BigDecimal n = d.abs();
                if (!c[2].equals("-")) n = n.setScale(Integer.parseInt(c[2]), RoundingMode.UNNECESSARY);
                n = n.movePointRight(exponent);
                BigDecimal stripped = n.stripTrailingZeros();
                BigDecimal r = d.remainder(BigDecimal.valueOf(modulus));
                // Swift's documented negative-scale remainder normalization.
                if (r.scale() < 0) r = r.setScale(0, RoundingMode.UNNECESSARY);
                BigInteger f = n.remainder(BigDecimal.ONE).movePointRight(Math.max(0, n.scale())).abs().toBigInteger();
                BigInteger t = stripped.remainder(BigDecimal.ONE).movePointRight(Math.max(0, stripped.scale())).abs().toBigInteger();
                String[] out = {d.toString(), d.toPlainString(), "" + d.scale(), "" + d.precision(), "" + d.signum(),
                                r.toString(), r.toPlainString(), "" + r.scale(), n.toString(), n.toPlainString(),
                                n.toBigInteger().toString(), "" + Math.max(0, n.scale()), "" + Math.max(0, stripped.scale()),
                                f.toString(), t.toString(), "" + exponent, d.toString()};
                System.out.println(String.join("\t", out));
            } catch (ArithmeticException failure) { System.out.println("ERROR\t" + failure.getMessage()); }
        }
    }
}
'''

FIELD_NAMES = ["decimal.canonical", "decimal.plain", "decimal.scale", "decimal.precision", "decimal.sign",
               "remainder.canonical", "remainder.plain", "remainder.scale", "n.canonical", "n.plain", "i",
               "v", "w", "f", "t", "compactExponent", "source.canonical"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs() -> str:
    rng = random.Random(713)
    rows = []
    for _ in range(600):
        precision = rng.randint(1, 250)
        digits = "".join(str(rng.randrange(10)) for _ in range(precision))
        scale = rng.randint(-65, 65)
        text = ("-" if rng.randrange(2) else "") + digits + "e" + str(-scale)
        rows.append("\t".join([text, str(rng.choice([1, 2, 7, 10, 100, 1_000_000])),
                               str(rng.randrange(10)) if rng.randrange(3) == 0 else "-", str(rng.randrange(10))]))
    for text in ["0E+3", "0.00", "1.00", "1e-1024", "1e1024", "-0e-1024",
                 "10000000000000000000000.0001000", "-1.2500"]:
        for exponent in [0, 2, 6, 64]:
            rows.append("\t".join([text, "7", "-", str(exponent)]))
    return "\n".join(rows) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--java-home", required=True, type=Path, help="JDK matching Reference/reference-runtime-lock.json")
    parser.add_argument("--swiftc", type=Path, help="compiler path; defaults to xcrun swiftc on macOS or PATH")
    parser.add_argument("--output-directory", type=Path, help="artifact directory; defaults to a new writable temporary directory")
    parser.add_argument("--report", type=Path, help="JSON report path; defaults to output-directory/report.json")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = (args.output_directory or Path(tempfile.mkdtemp(prefix="lokalized-numeric-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report_path = (args.report or output / "report.json").resolve()
    report = {"formatVersion": 1, "verified": False, "scope": "exact decimal arithmetic and plural operand derivation",
              "negativeScaleRemainder": "normalized to scale zero explicitly in both implementations",
              "notVerified": ["binary floating-point conversion", "plural category/range data", "minimum compiler and OS runtimes"],
              "startedAtUnix": time.time(), "host": platform.platform(), "outputDirectory": str(output), "commands": []}

    def run(command: list[str], stdin: str | None = None) -> str:
        start = time.monotonic()
        result = subprocess.run(command, input=stdin, text=True, capture_output=True)
        report["commands"].append({"argv": command, "returnCode": result.returncode,
                                   "elapsedSeconds": time.monotonic() - start,
                                   "stderr": result.stderr[:8192], "stdoutSha256": hashlib.sha256(result.stdout.encode()).hexdigest()})
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {command[0]}\n{result.stderr[:8192]}")
        return result.stdout

    try:
        lock_path = repo / "Reference/reference-runtime-lock.json"
        lock = json.loads(lock_path.read_text())
        release = args.java_home.resolve() / "release"
        if digest(release) != lock["jdk"]["releaseFileSha256"]:
            raise RuntimeError("JDK release identity does not match the pinned oracle; no comparison was run")
        java = args.java_home.resolve() / "bin/java"
        javac = args.java_home.resolve() / "bin/javac"
        swiftc = args.swiftc
        if swiftc is None:
            found = run(["xcrun", "--find", "swiftc"]).strip() if platform.system() == "Darwin" else shutil.which("swiftc")
            if not found:
                raise RuntimeError("swiftc is unavailable")
            swiftc = Path(found)
        # The Apple swiftc symlink selects driver mode through argv[0]. Resolving
        # it to swift-frontend changes the command's meaning.
        swiftc = swiftc.absolute()
        report["compilerVersion"] = run([str(swiftc), "--version"]).strip()
        report["javacVersion"] = run([str(javac), "-version"]).strip()
        java_identity = subprocess.run([str(java), "-version"], capture_output=True, text=True, check=True)
        report["javaVersion"] = (java_identity.stdout + java_identity.stderr).strip()
        source_paths = sorted((repo / "Sources/Lokalized").rglob("*.swift"))
        source_hashes = {str(path.relative_to(repo)): digest(path) for path in source_paths}
        report["sourceHashes"] = source_hashes
        report["inputProvenance"] = {"scriptSha256": digest(Path(__file__)), "runtimeLockSha256": digest(lock_path),
                                     "jdkReleaseSha256": digest(release), "swiftcSha256": digest(swiftc),
                                     "javaSha256": digest(java), "javacSha256": digest(javac), "randomSeed": 713}
        cases = inputs()
        cases_path = output / "cases.tsv"
        cases_path.write_text(cases)
        swift_path = output / "NumericProbe.swift"
        swift_path.write_text(SWIFT_CONSUMER)
        java_path = output / "DecimalOracle.java"
        java_path.write_text(JAVA_ORACLE)
        module_cache = output / "module-cache"
        module_cache.mkdir(exist_ok=True)
        library = output / ("libLokalized.dylib" if platform.system() == "Darwin" else "libLokalized.so")
        module = output / "Lokalized.swiftmodule"
        consumer = output / "numeric-probe"
        common = [str(swiftc), "-swift-version", "6", "-module-cache-path", str(module_cache)]
        if platform.system() == "Darwin":
            sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip()
            target = platform.machine() + "-apple-macosx12.0"
            common += ["-sdk", sdk, "-target", target]
            report["sdk"] = {"path": sdk, "version": run(["xcrun", "--sdk", "macosx", "--show-sdk-version"]).strip()}
            report["compileTarget"] = target
        run(common + ["-package-name", "lokalized_swift", "-emit-library", "-emit-module", "-module-name", "Lokalized",
                      *map(str, source_paths), "-o", str(library), "-emit-module-path", str(module)])
        run(common + ["-I", str(output), "-L", str(output), "-lLokalized", "-Xlinker", "-rpath", "-Xlinker", str(output),
                      str(swift_path), "-o", str(consumer)])
        run([str(javac), str(java_path)])
        swift_observations = run([str(consumer)], cases)
        java_observations = run([str(java), "-cp", str(output), "DecimalOracle"], cases)
        (output / "swift-observations.tsv").write_text(swift_observations)
        (output / "java-observations.tsv").write_text(java_observations)
        authored = cases.splitlines()
        actual = swift_observations.splitlines()
        expected = java_observations.splitlines()
        if len(actual) != len(expected) or len(actual) != len(authored):
            raise RuntimeError("Observation row count differs from authored inputs")
        differences = []
        for index, (case, observed, oracle) in enumerate(zip(authored, actual, expected)):
            if observed == oracle:
                continue
            left, right = observed.split("\t"), oracle.split("\t")
            differences.append({"row": index + 1, "input": case, "swift": observed, "java": oracle,
                                "fields": [FIELD_NAMES[i] if i < len(FIELD_NAMES) else str(i)
                                           for i in range(max(len(left), len(right)))
                                           if (left[i] if i < len(left) else None) != (right[i] if i < len(right) else None)]})
        report["cases"] = len(authored)
        report["accepted"] = sum(not value.startswith("ERROR\t") for value in expected)
        report["roundingRefusals"] = sum(value == "ERROR\tRounding necessary" for value in expected)
        report["differences"] = differences
        report["artifactHashes"] = {path.name: digest(path) for path in [cases_path, swift_path, java_path, library,
                                                                       module, consumer, output / "DecimalOracle.class",
                                                                       output / "swift-observations.tsv", output / "java-observations.tsv"]}
        current_sources = sorted((repo / "Sources/Lokalized").rglob("*.swift"))
        if source_paths != current_sources or source_hashes != {str(path.relative_to(repo)): digest(path) for path in current_sources}:
            raise RuntimeError("Library sources changed during verification; rerun on stable sources")
        if differences:
            raise RuntimeError(f"{len(differences)} exact numeric comparison(s) differed")
        report["verified"] = True
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    report["completedAtUnix"] = time.time()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"verified": report["verified"], "cases": report.get("cases"), "report": str(report_path),
                      "error": report.get("error")}, sort_keys=True))
    return 0 if report["verified"] else 1


if __name__ == "__main__":
    sys.exit(main())
