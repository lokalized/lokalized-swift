#!/usr/bin/env python3
"""Fresh-source Java/Swift expression differential; local, deterministic, no downloads."""
from __future__ import annotations

import argparse
import base64
from collections import Counter
from dataclasses import dataclass
import json
from pathlib import Path
import re
import tempfile
import time

from verify_floating_point import random_words, verify_jdk
from verify_parser_stress import ROOT, canonical, java_sources, run, sha

SEED = 0xE7A6634C214812B9
CLASS_MAP = {
    "TranslationEvaluationError.expression": "com.lokalized.ExpressionEvaluationException",
    "TranslationEvaluationError.invalidArgument": "java.lang.IllegalArgumentException",
    "TranslationEvaluationError.invalidState": "java.lang.IllegalStateException",
    "ExpressionCompilationError": "com.lokalized.ExpressionEvaluationException",
    "NumericError.invalidArgument": "java.lang.IllegalArgumentException",
    "NumericError.invalidDecimal": "java.lang.NumberFormatException",
    "NumericError.roundingNecessary": "java.lang.ArithmeticException",
    "UnsupportedLocaleError": "com.lokalized.UnsupportedLocaleException",
}
JAVA_CLASSES = frozenset(CLASS_MAP.values())


@dataclass(frozen=True)
class Case:
    id: str
    family: str
    source: str
    contexts: tuple[dict[str, list[str]], ...] = ({},)
    locale: str = "en"
    limits: tuple[tuple[str, int], ...] = ()
    resolver: str = "return"

    def wire(self) -> str:
        return "\t".join((self.id, self.locale,
                          ",".join(f"{key}={value}" for key, value in self.limits),
                          base64.b64encode(self.source.encode()).decode("ascii"),
                          base64.b64encode(canonical(self.contexts)).decode("ascii"), self.resolver)) + "\n"


def forms() -> list[str]:
    text = (ROOT / "Sources/Lokalized/API/LanguageForm.swift").read_text()
    values = re.findall(r'case \w+ = "([A-Z_]+)"', text)
    values = [name for name in values if name.startswith(("CARDINALITY_", "ORDINALITY_", "GENDER_",
        "CASE_", "DEFINITENESS_", "CLASSIFIER_", "FORMALITY_", "CLUSIVITY_", "ANIMACY_", "PHONETIC_"))]
    if len(values) != 61 or len(set(values)) != 61: raise ValueError("language-form source inventory changed")
    return values


def generate(seed: int = SEED, count: int = 250) -> list[Case]:
    if not 0 < seed < 1 << 64 or not 32 <= count <= 2000: raise ValueError("invalid seed or count")
    words = random_words(seed)
    def choose(options): return options[next(words) % len(options)]
    cases: list[Case] = []

    def add(family: str, source: str, contexts=({},), locale="en", limits=(), resolver="return"):
        cases.append(Case(f"expression-{len(cases):05d}", family, source,
                          tuple(contexts), locale, tuple(sorted(limits)), resolver))

    numbers = ["-1", "0", "-0.00", "1", "1.0", "1e3", "0.0001", "18446744073709551615",
               "-9223372036854775808", "9" * 50, "1e-1000", "1e1000"]
    operators = ["<", ">", "==", "!=", "<=", ">="]
    locales = ["en", "ru", "fr", "ar", "ja", "mo-MD", "zz"]
    for index in range(count):
        left, right = choose(numbers), choose(numbers)
        operator, locale = choose(operators), locales[index % len(locales)]
        add("numeric-literal", f"{left} {operator} {right}", locale=locale)
        add("numeric-precedence", f"{left} {operator} {right} || x == 1 && y != -1",
            contexts=({"x": ["integer", "0"], "y": ["byte", "-1"]},
                      {"x": ["integer", "1"], "y": ["short", "2"]},
                      {"x": ["null", ""]}, {}), locale=locale)
        carrier = choose(["byte", "short", "integer", "long", "bigInteger", "decimal"])
        value = choose(["-1", "0", "1", "2", "100"])
        add("numeric-carrier", f"x {operator} {right}", contexts=(
            {"x": [carrier, value]}, {"x": ["text", value]}, {"x": ["boolean", "true"]},
            {"x": ["null", ""]}, {}), locale=locale)

    for name in forms():
        add("typed-form", f"x == {name}", contexts=({"x": ["form", name]},
            {"x": ["null", ""]}, {"x": ["text", "honor"]}, {}))
        add("form-order", f"x > {name}", contexts=({"x": ["form", name]},))

    grammar = ["", " ", "1", "x", "==", "1 = 1", "1 === 1", "1 < 2 < 3", "1 ==", "(1 == 1",
               "1 == 1)", "((1 == 1))", "1 == 1 &&", "&& 1 == 1", "1 == 1 || || 2 == 2",
               "1e1025 == 1", "1e1025\u00a0", "x == 1\u00a0", "é == 1", "e\u0301 == 1",
               "😀 == 1", "x == 1\n", "x == 1\f", "x == 1\u2003", "x == .1",
               "x == +1", "x == 1e+", "x == 0x1", "x == 1.0.0"]
    for source in grammar:
        add("grammar-edge", source, contexts=({"x": ["integer", "1"], "é": ["integer", "1"],
            "e\u0301": ["integer", "2"]},))
    add("unicode-distinct-keys", "é == 1 && e\u0301 == 2", contexts=(
        {"é": ["integer", "1"], "e\u0301": ["integer", "2"]},
        {"é": ["integer", "2"], "e\u0301": ["integer", "1"]},
        {"é": ["integer", "1"]}, {"e\u0301": ["integer", "2"]}))
    for index in range(count):
        base = choose(["x == 1", "1 < 2", "x == GENDER_FEMININE", "x == PHONETIC_VOWEL"])
        position = next(words) % (len(base) + 1)
        character = choose(["?", "=", "\n", "\u00a0", "😀", "(", ")", "&", "1", "e"])
        add("grammar-mutation", base[:position] + character + base[position:],
            contexts=({"x": ["integer", "1"]},))

    callbacks = ["term == PHONETIC_VOWEL", "PHONETIC_CONSONANT == term",
                 "term == PHONETIC_VOWEL && term != PHONETIC_CONSONANT",
                 "1 == 1 || term == PHONETIC_VOWEL", "1 == 0 && term == PHONETIC_VOWEL",
                 "term == other", "term < PHONETIC_VOWEL"]
    for source in callbacks:
        for mode in ["return", "throw"]:
            add("phonetic-callback", source, contexts=({"term": ["text", "honor"],
                "other": ["text", "e\u0301"]}, {"term": ["text", "cat"]},
                {"term": ["form", "PHONETIC_VOWEL"]}, {}), locale="fr-CA", resolver=mode)

    for index in range(count):
        category = choose(["CARDINALITY_ONE", "CARDINALITY_FEW", "CARDINALITY_MANY",
            "CARDINALITY_OTHER", "ORDINALITY_ONE", "ORDINALITY_TWO", "ORDINALITY_OTHER"])
        number = choose(["-1", "0", "1", "1.0", "2", "2.0", "21", "100"])
        add("plural-category", f"x == {category}", contexts=(
            {"x": ["decimal", number]}, {"x": ["integer", "2"]},
            {"x": ["floatBits", "3f800000"]}, {"x": ["form", category]}),
            locale=locales[index % len(locales)])

    for nesting in [31, 32, 33]:
        add("default-nesting-boundary", "(" * nesting + "1 == 1" + ")" * nesting)
    for terms in [64, 65, 66]:
        add("default-token-boundary", " || ".join(["1 == 1"] * terms))
    for length in [2047, 2048, 2049]:
        add("default-character-boundary", "1 == 1" + " " * (length - 6))

    boundaries = [("characters", 6, "1 == 1"), ("tokens", 2, "1 == 1"),
                  ("nesting", 0, "(1 == 1)"), ("precision", 1, "12 == 12"),
                  ("scale", 1, "1e2 == 100"), ("phonetic", 1, "term == PHONETIC_VOWEL")]
    for key, limit, source in boundaries:
        for delta in [-1, 0, 1]:
            actual = limit + delta
            if actual < (0 if key in {"nesting", "scale"} else 1): continue
            add("lowered-limit", source, contexts=({"term": ["text", "😀"]},),
                limits=((key, actual),))
    for bits in ["00000000", "3f800001", "7f800000", "7fc00001", "80000000"]:
        add("binary32-carrier", "x == 1", contexts=({"x": ["floatBits", bits]},))
    for bits in ["0000000000000000", "3ff0000000000001", "7ff0000000000000",
                 "7ff8000000000001", "8000000000000000"]:
        add("binary64-carrier", "x == 1", contexts=({"x": ["doubleBits", bits]},))
    return cases


def observations(command: list[str], cases: list[Case]) -> list[dict]:
    rows = [json.loads(line) for line in run(command, data="".join(case.wire() for case in cases).encode("ascii")).splitlines()]
    if len(rows) != len(cases): raise ValueError("missing or extra observations")
    for case, row in zip(cases, rows):
        if set(row) != {"id", "compile", "results"} or row["id"] != case.id: raise ValueError("invalid observation shape or order")
        if (row["compile"] is None) != (len(row["results"]) == len(case.contexts)):
            raise ValueError("compile phase/results mismatch")
        if row["compile"] is not None and row["results"]: raise ValueError("results after compile refusal")
        for result in row["results"]:
            if set(result) not in ({"value", "calls"}, {"error", "calls"}): raise ValueError("invalid evaluation observation")
            if "value" in result and type(result["value"]) is not bool: raise ValueError("nonboolean expression result")
    return rows


def normalize(row: dict) -> dict:
    result = json.loads(json.dumps(row))
    for chain in [result["compile"], *(item.get("error") for item in result["results"])]:
        if chain is None: continue
        if not isinstance(chain, list) or not chain: raise ValueError("empty error chain")
        for pair in chain:
            if not isinstance(pair, list) or len(pair) != 2 or not isinstance(pair[0], str):
                raise ValueError("invalid error chain")
            pair[0] = CLASS_MAP.get(pair[0], pair[0])
            if pair[0] not in JAVA_CLASSES:
                raise ValueError(f"unmapped refusal class {pair[0]}")
            if pair[1] is not None and (not isinstance(pair[1], list) or
                    any(type(unit) is not int or not 0 <= unit <= 65535 for unit in pair[1])):
                raise ValueError("invalid UTF-16 diagnostic")
    for observation in result["results"]:
        if not isinstance(observation["calls"], list): raise ValueError("missing resolver trace")
        for call in observation["calls"]:
            if not isinstance(call, list) or len(call) != 2 or any(
                not isinstance(field, list) or any(type(unit) is not int or not 0 <= unit <= 65535 for unit in field)
                for field in call): raise ValueError("invalid resolver trace")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-repository", required=True, type=Path)
    parser.add_argument("--java-home", required=True, type=Path)
    parser.add_argument("--jspecify-jar", required=True, type=Path)
    parser.add_argument("--jsr305-jar", required=True, type=Path)
    parser.add_argument("--swiftc", default="swiftc")
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=SEED)
    parser.add_argument("--count", type=int, default=250)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    started = time.monotonic_ns()
    cases = generate(args.seed, args.count)
    sources = sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))
    inputs = sources + [Path(__file__), ROOT / "Tools/ExpressionStressProbe.swift",
        ROOT / "Tools/ExpressionStressOracle.java", ROOT / "Tools/verify_parser_stress.py",
        ROOT / "Tools/verify_floating_point.py", args.jspecify_jar.resolve(), args.jsr305_jar.resolve()]
    pins = {str(path.resolve()): sha(path.read_bytes()) for path in inputs}
    report = {"formatVersion": 1, "status": "running", "scope": "compiled expressions, typed runtime outcomes, exact diagnostics/causes, phonetic callback order",
              "unexamined": ["whole-message wrapping", "generated alternatives", "custom Java Number types", "resolver object identity"],
              "seed": hex(args.seed), "generatedRounds": args.count, "cases": len(cases),
              "inputSHA256": sha("".join(case.wire() for case in cases).encode()), "inputs": pins,
              "jdk": verify_jdk(args.java_home), "commands": []}
    with tempfile.TemporaryDirectory(prefix="lokalized-expression-stress-") as temporary:
        scratch = Path(temporary)
        java_paths, report["javaSources"] = java_sources(args.java_repository, scratch)
        classes = scratch / "classes"
        classes.mkdir()
        command = [str(args.java_home / "bin/javac"), "--release", "9", "-proc:none", "-cp",
                   str(args.jspecify_jar) + ":" + str(args.jsr305_jar), "-d", str(classes),
                   *map(str, java_paths), str(ROOT / "Tools/ExpressionStressOracle.java")]
        report["commands"].append(command)
        run(command)
        executable = scratch / "swift-probe"
        command = [args.swiftc, "-swift-version", "6", "-parse-as-library", "-module-name", "Lokalized",
                   "-package-name", "lokalized_swift", "-module-cache-path", str(scratch / "module-cache"),
                   *map(str, sources), str(ROOT / "Tools/ExpressionStressProbe.swift"), "-o", str(executable)]
        report["commands"].append(command)
        run(command)
        report["swiftCompiler"] = run([args.swiftc, "--version"]).decode()
        java = [str(args.java_home / "bin/java"), "-cp", str(classes), "com.lokalized.ExpressionStressOracle"]
        swift = [str(executable)]
        report["commands"].extend([java, swift])
        actual_java, actual_swift = observations(java, cases), observations(swift, cases)
        normalized_swift = [normalize(row) for row in actual_swift]
        normalized_java = [normalize(row) for row in actual_java]
        mismatches = [(case, a, b) for case, a, b in zip(cases, normalized_java, normalized_swift) if a != b]
        report["coverage"] = {"families": dict(sorted(Counter(case.family for case in cases).items())),
            "compiled": sum(row["compile"] is None for row in actual_java),
            "compileRefusals": sum(row["compile"] is not None for row in actual_java),
            "returned": sum("value" in result for row in actual_java for result in row["results"]),
            "evaluationRefusals": sum("error" in result for row in actual_java for result in row["results"]),
            "callbackSites": sum(len(result["calls"]) for row in actual_java for result in row["results"])}
        if (report["coverage"]["compiled"] < 100 or report["coverage"]["compileRefusals"] < 50 or
                report["coverage"]["evaluationRefusals"] < 100 or report["coverage"]["callbackSites"] < 10):
            raise ValueError("degenerate expression stress coverage")
        report["differenceCount"] = len(mismatches)
        report["differenceFamilies"] = dict(Counter(case.family for case, _, _ in mismatches))
        report["differences"] = [{"case": case.__dict__, "java": a, "swift": b} for case, a, b in mismatches[:100]]
        report["observationsSHA256"] = {"java": sha(canonical(actual_java)), "swift": sha(canonical(actual_swift))}
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
