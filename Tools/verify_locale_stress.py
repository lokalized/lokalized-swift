#!/usr/bin/env python3
"""Generated JDK/CLDR locale-input differential using frozen Java and current Swift."""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import tempfile
import time

from verify_floating_point import random_words, verify_jdk
from verify_locales import EDGE_CASES, FIELDS, GRANDFATHERED
from verify_parser_stress import ROOT, canonical, java_sources, run, sha

SEED = 0x4CA1E5D7B0912683


@dataclass(frozen=True)
class Case:
    id: str
    family: str
    text: str

    def wire(self) -> str:
        return self.id + "\t" + base64.b64encode(self.text.encode("utf-8")).decode("ascii") + "\n"


def generate(seed: int = SEED, count: int = 300) -> list[Case]:
    if not 0 < seed < 1 << 64 or not 32 <= count <= 2000: raise ValueError("invalid seed or count")
    words = random_words(seed)
    def choose(options): return options[next(words) % len(options)]
    cases: list[Case] = []
    def add(family: str, text: str):
        if len(text.encode("utf-16-le")) > 1024: raise ValueError("unbounded generated input")
        cases.append(Case(f"locale-stress-{len(cases):05d}", family, text))

    for text in EDGE_CASES + GRANDFATHERED + [name.upper() for name in GRANDFATHERED]:
        add("fixed-reference-edge", text)
    for text in ["", "-", "--", "en\nUS", "en\rUS", "en\tUS", "en\u0000US", "en-😀", "é", "e\u0301",
                 "en-US-\u00e9", "en-US-\u212a", "x-\u00e9", "a", "ab", "abcdefgh", "abcdefghi", "en-12345678", "en-123456789",
                 "ji-\u0301u", "in-Katn-fonipa-x", "en-ßabc", "en-ßé", "en-١٢٣"]:
        add("fixed-control-edge", text)

    languages = ["en", "fr", "ru", "sr", "zh", "ja", "th", "no", "mo", "iw", "ji", "in", "und", "x", "zz", "a", "abc", "abcdefgh"]
    scripts = ["Latn", "Cyrl", "Hans", "Hant", "Arab", "Zzzz", "Aaaa", "1234", "Katn"]
    regions = ["US", "GB", "CA", "CN", "TW", "RS", "MD", "419", "ZZ", "001", "U", "1234"]
    variants = ["posix", "1901", "1996", "fonipa", "abcde", "abcd", "ab12", "1234", "123", "JP", "NY"]
    tails = ["u-ca-gregory", "u-nu-latn-ca-japanese", "u-abc-aaa-ca-gregory", "a-abc",
             "a-abc-b-def", "x-private", "x-lvariant-JP", "x-custom-lvariant-POSIX", "u", "x", "a-abc-a-def"]
    mutations = ["?", "_", "\u00a0", "😀", "\u0301", "-", "=", "\n", "\u0000"]
    for _ in range(count):
        parts = [choose(languages)]
        if next(words) % 2 == 0: parts.append(choose(scripts))
        if next(words) % 2 == 0: parts.append(choose(regions))
        if next(words) % 2 == 0: parts.append(choose(variants))
        if next(words) % 2 == 0: parts.append(choose(tails))
        source = "-".join(parts)
        add("composed-tag", source)
        position = next(words) % (len(source) + 1)
        add("inserted-code-point", source[:position] + choose(mutations) + source[position:])
        if source:
            position = next(words) % len(source)
            add("deleted-code-point", source[:position] + source[position + 1:])
        add("case-variant", source.upper() if next(words) % 2 else source.swapcase())
        add("duplicate-extension", source + "-u-ca-gregory-u-nu-latn")
        add("private-variant", source + "-x-custom-lvariant-POSIX")
    return cases


def observations(command: list[str], cases: list[Case]) -> list[dict]:
    output = run(command, data="".join(case.wire() for case in cases).encode("ascii"))
    rows = [json.loads(line) for line in output.splitlines()]
    if len(rows) != len(cases): raise ValueError("missing or extra locale observation")
    for case, row in zip(cases, rows):
        if set(row) != {"id", "values"} or row["id"] != case.id: raise ValueError("invalid row shape, order, or identity")
        if not isinstance(row["values"], list) or len(row["values"]) != len(FIELDS): raise ValueError("invalid locale field inventory")
        for value in row["values"]:
            if not isinstance(value, list) or any(type(unit) is not int or not 0 <= unit <= 65535 for unit in value):
                raise ValueError("invalid UTF-16 locale field")
    return rows


def differences(case: Case, java: dict, swift: dict) -> dict | None:
    fields = [{"field": name, "java": left, "swift": right} for name, left, right in zip(FIELDS, java["values"], swift["values"])
              if left != right]
    return {"case": case.__dict__, "fields": fields} if fields else None


def coverage(cases: list[Case], rows: list[dict]) -> dict:
    if len(FIELDS) != 21 or len(cases) != len(rows): raise ValueError("locale field inventory changed")
    strict = Counter("".join(chr(unit) for unit in row["values"][9]) for row in rows)
    projected = Counter("".join(chr(unit) for unit in row["values"][0]) for row in rows)
    if strict["true"] < 50 or strict["false"] < 50 or len(projected) < 50:
        raise ValueError("degenerate accepted/refused/projection coverage")
    if set(strict) != {"true", "false"}: raise ValueError("invalid strict locale observation")
    return {"families": dict(sorted(Counter(case.family for case in cases).items())),
            "strictAccepted": strict["true"], "strictRefused": strict["false"],
            "distinctProjectedTags": len(projected)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-repository", required=True, type=Path)
    parser.add_argument("--java-home", required=True, type=Path)
    parser.add_argument("--jspecify-jar", required=True, type=Path)
    parser.add_argument("--jsr305-jar", required=True, type=Path)
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=SEED)
    parser.add_argument("--count", type=int, default=300)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    started = time.monotonic_ns()
    cases = generate(args.seed, args.count)
    sources = sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))
    inputs = sources + [Path(__file__), ROOT / "Tools/LocaleStressOracle.java", ROOT / "Tools/LocaleStressProbe.swift",
        ROOT / "Tools/verify_parser_stress.py", ROOT / "Tools/verify_locales.py", ROOT / "Tools/verify_floating_point.py",
        args.jspecify_jar.resolve(), args.jsr305_jar.resolve()]
    pins = {str(path.resolve()): sha(path.read_bytes()) for path in inputs}
    report = {"formatVersion": 1, "status": "running", "scope": list(FIELDS),
              "unexamined": ["strict-constructor diagnostic chains", "language-range parser", "locale matcher election", "non-scalar Java strings"],
              "seed": hex(args.seed), "generatedRounds": args.count, "cases": len(cases),
              "inputSHA256": sha("".join(case.wire() for case in cases).encode("ascii")),
              "inputs": pins, "jdk": verify_jdk(args.java_home), "commands": []}
    with tempfile.TemporaryDirectory(prefix="lokalized-locale-stress-") as temporary:
        scratch = Path(temporary)
        java_paths, report["javaSources"] = java_sources(args.java_repository, scratch)
        classes = scratch / "classes"
        classes.mkdir()
        command = [str(args.java_home / "bin/javac"), "--release", "9", "-proc:none", "-cp",
            str(args.jspecify_jar) + ":" + str(args.jsr305_jar), "-d", str(classes),
            *map(str, java_paths), str(ROOT / "Tools/LocaleStressOracle.java")]
        report["commands"].append(command)
        run(command)
        executable = scratch / "swift-probe"
        command = [args.swiftc, "-swift-version", "6", "-parse-as-library", "-module-name", "Lokalized",
            "-package-name", "lokalized_swift", "-module-cache-path", str(scratch / "module-cache"),
            *map(str, sources), str(ROOT / "Tools/LocaleStressProbe.swift"), "-o", str(executable)]
        report["commands"].append(command)
        run(command)
        report["swiftCompiler"] = run([args.swiftc, "--version"]).decode()
        java = [str(args.java_home / "bin/java"), "-cp", str(classes), "com.lokalized.LocaleStressOracle"]
        swift = [str(executable)]
        report["commands"].extend([java, swift])
        observed_java, observed_swift = observations(java, cases), observations(swift, cases)
        report["coverage"] = coverage(cases, observed_java)
        mismatches = [diff for case, a, b in zip(cases, observed_java, observed_swift)
                      if (diff := differences(case, a, b)) is not None]
        report["differenceCount"] = len(mismatches)
        report["differenceFamilies"] = dict(Counter(diff["case"]["family"] for diff in mismatches))
        report["differences"] = mismatches[:100]
        report["observationsSHA256"] = {"java": sha(canonical(observed_java)), "swift": sha(canonical(observed_swift))}
        if pins != {str(path.resolve()): sha(path.read_bytes()) for path in inputs}:
            raise ValueError("probe inputs changed during execution")
        report["status"] = "passed" if not mismatches else "failed"
    report["elapsedNanoseconds"] = time.monotonic_ns() - started
    report["temporaryDirectoryRemoved"] = not scratch.exists()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=True) + "\n")
    print(json.dumps({"status": report["status"], "cases": len(cases), "differences": len(mismatches), "report": str(args.report)}))
    if mismatches: raise SystemExit(1)


if __name__ == "__main__": main()
