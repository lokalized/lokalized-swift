#!/usr/bin/env python3
"""Deterministic, development-only catalog differential; Python standard library only.

Freshly compile the frozen Java 3.1.0 sources and current Swift sources. No oracle
outputs are synthesized or checked into the runtime package. Requires an explicit
local Java repository, pinned JDK and two compile-time annotation jars; no fetches.
"""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from dataclasses import dataclass, replace
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import time

from verify_floating_point import random_words, verify_jdk

ROOT = Path(__file__).resolve().parent.parent
JAVA_COMMIT = "63b63e47c982f7a87873c52ac2289cc0392f3329"
JAVA_SOURCES_SHA256 = "db1f440a5641e419cf1f1a2d8fd89b2f6d7b63d65b9ee0316a0a7f83a76fa1e0"
SEED = 0x97E513CB4A826FD1
CLASS_MAPPING = {"com.lokalized.LocalizedStringLoadingException": "Lokalized.StringsParseError"}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":")).encode("ascii")


@dataclass(frozen=True)
class Case:
    id: str
    family: str
    data: bytes
    locale: str = "en"
    options: tuple[tuple[str, int], ...] = ()

    def wire(self) -> str:
        return "\t".join([self.id, self.locale, ",".join(f"{k}={v}" for k, v in self.options),
                          base64.b64encode(self.data).decode("ascii")]) + "\n"

    def receipt(self) -> dict:
        return {"id": self.id, "family": self.family, "locale": self.locale,
                "options": dict(self.options), "inputBase64": base64.b64encode(self.data).decode("ascii")}


def structural_positions(data: bytes) -> list[int]:
    """Only mutate outside strings: preserve escaped surrogate pairs and authored text."""
    inside = escaped = False
    positions = []
    for index, byte in enumerate(data):
        if inside:
            if escaped: escaped = False
            elif byte == 92: escaped = True
            elif byte == 34: inside = False
        elif byte == 34: inside = True
        elif byte in b"{}[]:,": positions.append(index)
    return positions


def generate(seed: int = SEED, count: int = 200) -> list[Case]:
    if not 0 < seed < 1 << 64 or not 8 <= count <= 1_000:
        raise ValueError("seed must be a nonzero UInt64 and count between 8 and 1000")
    cases: list[Case] = []
    words = random_words(seed)

    def add(family, data, locale="en", options=()):
        if isinstance(data, str): data = data.encode("utf-8")
        cases.append(Case(f"stress-{len(cases):05d}", family, data, locale, tuple(sorted(options))))

    texts = ["plain", "é", "e\u0301", "日本語", "😀", "line\nnext\t", 'quote" slash\\', "👩🏽‍💻", ""]
    for index in range(count):
        text = texts[next(words) % len(texts)]
        form = [{"value": "count", "translations": {"CARDINALITY_ONE": text}},
                {"range": {"start": "lo", "end": "hi"}, "translations": {"CARDINALITY_OTHER": text}},
                {"value": "gender", "translations": {"GENDER_MASCULINE": text, "GENDER_FEMININE": "f"}},
                {"value": "count", "translations": {"ORDINALITY_ONE": text}}][index % 4]
        template = {"translation": text, "alternatives": [{"count == 1": "one"}, {"count > 1": "many"}]}
        catalog = {"é": text, "e\u0301": {"translation": "{{n}} {{fragment}}", "commentary": text,
                    "placeholders": {"n": form, "fragment": template}},
                   "😀": {"alternatives": [{"count >= 0": {"translation": text,
                            "alternatives": [{"count == 2": "two"}]}}, {"count < 0": "negative"}]}}
        separators = [(" , ", " : "), (",", ":"), (",\n", ": "), (",\r\n", ": ")][index % 4]
        data = json.dumps(catalog, ensure_ascii=bool(index % 2), separators=separators).encode("utf-8")
        if index % 7 == 0: data = b"\xef\xbb\xbf" + data
        locale = ["en", "ru", "fr", "ar", "ja"][index % 5]
        add("valid-model", data, locale)
        positions = structural_positions(data)
        for _ in range(2):
            position = positions[next(words) % len(positions)]
            add("structural-delete", data[:position] + data[position + 1:], locale)
            add("structural-replace", data[:position] + b"?" + data[position + 1:], locale)
            add("structural-truncate", data[:position], locale)
        for delta in [-1, 0, 1]:
            add("byte-budget", data, locale, [("maximumInputBytes", len(data) + delta)])
            add("aggregate-budget", data, locale, [("maximumTotalInputBytes", len(data) + delta)])
        add("reader-budget-on-bytes", data, locale, [("maximumReaderCharacters", 1)])
        for limit in [0, 2, 8]:
            add("node-budget", data, locale, [("maximumTranslationNodes", limit)])
        add("warning-budget", data, locale, [("maximumWarnings", index % 3)])
        add("depth-budget", data, locale, [("maximumJsonNestingDepth", 1 + index % 8)])

    defects = [None, 7, False, [], {}, {"translation": None}, {"translation": []},
               {"commentary": 1, "translation": None}, {"unknown": 1, "translation": None},
               {"translation": "{{bad name}}", "alternatives": []},
               {"translation": "ok", "placeholders": None},
               {"translation": "ok", "placeholders": {"p": {"value": None, "translation": "x"}}},
               {"alternatives": []}, {"alternatives": [None]}, {"alternatives": [{}]},
               {"alternatives": [{"x ==": "bad"}]},
               {"alternatives": [{"x == 1": "a", "x == 2": "b"}]},
               {"translation": "{{p}}", "placeholders": {"p": {"translations": {"UNKNOWN": "x"}}}},
               {"translation": "{{p}}", "placeholders": {"p": {"range": {"start": 1}, "translations": {}}}}]
    warning = {"translation": "{{n}}", "placeholders": {"n": {"value": "count", "translations": {"CARDINALITY_ONE": "one"}}}}
    for first in defects:
        for second in defects:
            add("competing-schema-errors", canonical({"A": first, "B": second}), "ru")
        add("warning-before-error", canonical({"A": warning, "B": first}), "ru")
        add("warning-refusal-before-error", canonical({"A": warning, "B": first}), "ru", [("maximumWarnings", 0)])

    syntax = ["", " \t\r\n", "{}", "[]", "null", "true", "01", "+1", "1.", "1e+", "-", "nul",
              '{"a":"\\x"}', '{"a":"\\u12"}', '{"a":"\\u12g4"}', '{"a":"\\uD83D\\uDE00"}',
              '{"a":"\\u0065\\u0301"}', '{"a":"\\n\\t\\b\\r\\f\\/\\\\\\\""}',
              '{"a":1,}', '{"a":}', '{"a":"x"} false', '{"a":"x","\\u0061":"y"}',
              '{"a":{"unknown":1,"translation":"x","translation":"y"}}',
              '{"a":null,"b":{"translation":"x","translation":"y"}}',
              '{"a":{"alternatives":[{"x == 1":{"translation":"x","commentary":"x","commentary":"y"}}]}}']
    for text in syntax:
        for prefix in ["", "\ufeff", "\ufeff\ufeff", "\n", "\r\n", "\r"]:
            add("json-edge", prefix + text)
    # The byte door can express malformed escapes even though Swift String cannot
    # hold unpaired UTF-16. Compare actual Java refusals, not repaired strings.
    for escaped in [chr(unit) for unit in range(128) if unit not in [34, 47, 92, 98, 102, 110, 114, 116, 117]] + ["é", "😀"]:
        for prefix in ["", "\r\n"]:
            add("unsupported-escape", prefix + '{"😀":"\\' + escaped + '"}')
    for suffix in ['"}', '', 'x"}', '\\t"}', '\\x"}', '\\u0000"}', '\\uD800"}', '\\uDC00"}', '\\u12"}', '\n"}']:
        for surrogate in ["D800", "DBFF", "DC00", "DFFF"]:
            add("surrogate-escape", '{"a":"\\u' + surrogate + suffix)
    for unit in range(32):
        add("raw-string-control", '{"a":"' + chr(unit) + '"}')
    for bad in [b"\x80", b"\xc0\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xe2\x82", b"\xff"]:
        for surrounding in [b"", b'{"x":"', b'{"x":"ok"}\n']:
            add("invalid-utf8", surrounding + bad)
    for depth in [1, 2, 63, 64, 65, 127, 128, 129]:
        data = "[" * depth + "0" + "]" * depth
        for limit in [1, 64, 128]: add("depth-edge", data, options=[("maximumJsonNestingDepth", limit)])
    return cases


def run(command: list[str], *, data: bytes | None = None) -> bytes:
    result = subprocess.run(command, input=data, capture_output=True)
    if result.returncode:
        raise ValueError(f"command failed ({result.returncode}): {command[0]} ({len(command) - 1} arguments)\n{result.stderr.decode(errors='replace')}")
    return result.stdout


def observations(command: list[str], cases: list[Case]) -> list[dict]:
    return decode_observations(run(command, data="".join(c.wire() for c in cases).encode("ascii")), cases)


def decode_observations(data: bytes, cases: list[Case]) -> list[dict]:
    rows = [json.loads(line) for line in data.splitlines()]
    if len(rows) != len(cases): raise ValueError("missing or extra probe rows")
    for case, row in zip(cases, rows):
        if set(row) != {"id", "status", "class", "value", "warnings"} or row["id"] != case.id:
            raise ValueError("unknown/missing fields or reordered/duplicate probe IDs")
        if row["status"] not in {"returned", "threw"} or not isinstance(row["warnings"], list):
            raise ValueError("invalid observation shape")
        if any(not isinstance(warning, list) or any(type(unit) is not int or not 0 <= unit <= 65535 for unit in warning)
               for warning in row["warnings"]): raise ValueError("invalid warning UTF-16 units")
        if not isinstance(row["value"], list): raise ValueError("missing decoded contents or diagnostic units")
        if row["status"] == "returned" and row["class"] is not None: raise ValueError("returned row carries refusal class")
        if row["status"] == "threw" and (not isinstance(row["class"], str) or
                any(type(unit) is not int or not 0 <= unit <= 65535 for unit in row["value"])):
            raise ValueError("refusal lost class or diagnostic units")
    return rows


def differences(java: dict, swift: dict) -> list[str]:
    expected = dict(java)
    if java["status"] == "threw":
        if java["class"] not in CLASS_MAPPING: raise ValueError(f"unmapped Java refusal class: {java['class']}")
        expected["class"] = CLASS_MAPPING[java["class"]]
    return [field for field in expected if expected[field] != swift[field]]


def check_coverage(cases: list[Case], rows: list[dict]) -> dict:
    counts = Counter(row["status"] for row in rows)
    warnings = sum(bool(row["warnings"]) for row in rows)
    for case, row in zip(cases, rows):
        if case.family in {"valid-model", "reader-budget-on-bytes"} and row["status"] != "returned":
            raise ValueError(f"positive model family refused: {case.id}")
    if counts["returned"] < 16 or counts["threw"] < 100 or warnings < 8:
        raise ValueError("degenerate probe: insufficient accepted/refused/warning observations")
    if {r["class"] for r in rows if r["status"] == "threw"} != set(CLASS_MAPPING):
        raise ValueError("unmapped or stale Java refusal mapping")
    return {"outcomes": dict(counts), "rowsWithWarnings": warnings,
            "families": dict(sorted(Counter(c.family for c in cases).items()))}


def java_sources(repository: Path, scratch: Path) -> tuple[list[Path], dict]:
    prefix = "src/main/java/com/lokalized/"
    archive = run(["git", "-C", str(repository), "archive", JAVA_COMMIT, prefix])
    entries = []
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if member.isdir(): continue
            if not member.isfile() or not member.name.startswith(prefix): raise ValueError("unexpected Java archive member")
            name = member.name[len(prefix):]
            if "/" in name or not name.endswith(".java"): raise ValueError("unexpected Java source path")
            data = tar.extractfile(member).read()
            entries.append((name, data))
    pins = [{"path": name, "sha256": sha(data)} for name, data in sorted(entries)]
    if len(pins) != 62 or sha(canonical(pins)) != JAVA_SOURCES_SHA256:
        raise ValueError("fresh Java archive does not match the frozen 3.1.0 source aggregate")
    paths = []
    for name, data in sorted(entries):
        path = scratch / "java-source" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        paths.append(path)
    return paths, {"commit": JAVA_COMMIT, "files": len(pins), "sourceSHA256": JAVA_SOURCES_SHA256}


def minimize(case: Case, java: list[str], swift: list[str], fields: list[str], budget: int) -> tuple[Case, int]:
    """Bounded delta deletion; retain the same differing channel, never regenerate an expectation."""
    current = case
    probes = 0
    partitions = 2
    while len(current.data) > 1 and probes < budget:
        width = max(1, (len(current.data) + partitions - 1) // partitions)
        trials = [replace(current, data=current.data[:i] + current.data[i + width:])
                  for i in range(0, len(current.data), width)][:budget - probes]
        # Each batch needs unique source IDs; IDs also occur in parser diagnostics.
        trials = [replace(trial, id=f"minimize-{probes + i:05d}") for i, trial in enumerate(trials)]
        j = observations(java, trials)
        s = observations(swift, trials)
        probes += len(trials)
        winner = next((trial for trial, a, b in zip(trials, j, s) if differences(a, b) == fields), None)
        if winner is not None:
            current = winner
            partitions = max(2, partitions - 1)
        elif partitions >= len(current.data): break
        else: partitions = min(len(current.data), partitions * 2)
    return current, probes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-repository", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True)
    parser.add_argument("--jspecify-jar", type=Path, required=True)
    parser.add_argument("--jsr305-jar", type=Path, required=True)
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=SEED)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--minimization-probes", type=int, default=64)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if not 0 <= args.minimization_probes <= 256: parser.error("minimization probes must be between 0 and 256")
    started = time.monotonic_ns()
    cases = generate(args.seed, args.count)
    sources = sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))
    inputs = sources + [Path(__file__), ROOT / "Tools/ParserStressProbe.swift", ROOT / "Tools/ParserStressOracle.java",
                       ROOT / "Tools/verify_floating_point.py", ROOT / "Reference/baseline.json",
                       args.jspecify_jar.resolve(), args.jsr305_jar.resolve()]
    pins = {str(path.resolve()): sha(path.read_bytes()) for path in inputs}
    report = {"formatVersion": 1, "status": "running", "scope": "Data catalog parse: decoded models, main refusal class/message, ordered warning messages",
              "unexamined": ["error causes", "Swift error path/line/column properties", "warning metadata", "String/Reader doors", "locale ingress", "expression evaluation"],
              "seed": hex(args.seed), "generatedCatalogs": args.count, "cases": len(cases),
              "inputSHA256": sha("".join(c.wire() for c in cases).encode("ascii")), "inputs": pins,
              "jdk": verify_jdk(args.java_home), "commands": []}
    with tempfile.TemporaryDirectory(prefix="lokalized-parser-stress-") as temporary:
        scratch = Path(temporary)
        java_paths, report["javaSources"] = java_sources(args.java_repository, scratch)
        classes = scratch / "classes"
        classes.mkdir()
        command = [str(args.java_home / "bin/javac"), "--release", "9", "-proc:none", "-cp",
                   str(args.jspecify_jar) + ":" + str(args.jsr305_jar), "-d", str(classes),
                   *map(str, java_paths), str(ROOT / "Tools/ParserStressOracle.java")]
        report["commands"].append(command)
        run(command)
        executable = scratch / "swift-probe"
        command = [args.swiftc, "-swift-version", "6", "-parse-as-library", "-module-name", "Lokalized",
                   "-package-name", "lokalized_swift", "-module-cache-path", str(scratch / "module-cache"),
                   *map(str, sources), str(ROOT / "Tools/ParserStressProbe.swift"), "-o", str(executable)]
        report["commands"].append(command)
        run(command)
        report["swiftCompiler"] = run([args.swiftc, "--version"]).decode()
        java = [str(args.java_home / "bin/java"), "-cp", str(classes), "com.lokalized.ParserStressOracle"]
        swift = [str(executable)]
        report["commands"].extend([java, swift])
        actual_java, actual_swift = observations(java, cases), observations(swift, cases)
        report["coverage"] = check_coverage(cases, actual_java)
        mismatches = [(case, a, b, differences(a, b)) for case, a, b in zip(cases, actual_java, actual_swift) if differences(a, b)]
        report["differenceFamilies"] = dict(Counter(case.family for case, _, _, _ in mismatches))
        report["differences"] = [{**case.receipt(), "fields": fields, "java": a, "swift": b}
                                 for case, a, b, fields in mismatches[:1000]]
        report["differenceCount"] = len(mismatches)
        report["minimized"] = []
        if mismatches and args.minimization_probes:
            case, _, _, fields = mismatches[0]
            minimal, probes = minimize(case, java, swift, fields, args.minimization_probes)
            report["minimized"].append({**minimal.receipt(), "originalID": case.id, "probes": probes,
                                       "java": observations(java, [minimal])[0], "swift": observations(swift, [minimal])[0]})
        if pins != {str(path.resolve()): sha(path.read_bytes()) for path in inputs}:
            raise ValueError("probe inputs changed during execution")
        report["observationsSHA256"] = {"java": sha(canonical(actual_java)), "swift": sha(canonical(actual_swift))}
        report["status"] = "failed" if mismatches else "passed"
    report["elapsedNanoseconds"] = time.monotonic_ns() - started
    report["temporaryDirectoryRemoved"] = not scratch.exists()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "cases": len(cases), "differences": len(mismatches), "report": str(args.report)}))
    if mismatches: raise SystemExit(1)


if __name__ == "__main__":
    main()
