#!/usr/bin/env python3
"""Generate/check compact Swift plural bytecode from the frozen CLDR 48.2 export.

Python's standard library is the only development dependency. No live download,
locale API, or installed ICU version contributes to the generated result.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = "7ade4692762aac80144f915b62de19f29eb039ec3cf28c3f9f2c34b810cdc0e7"
FINGERPRINT = "9b4f24165b6dd1ee6dbb5f0822abc7bcde49c5b94d35903045826b45e1f30e68"
CATEGORIES = ("zero", "one", "two", "few", "many", "other")
OPERANDS = "nivwftce"


def condition_words(condition):
    """DNF: OR count; each AND count; operand, modulus, negate, interval count/pairs."""
    if not condition:
        return [0]  # Unconditional rule.
    words = []
    disjuncts = condition.split(" or ")
    words.append(len(disjuncts))
    for disjunct in disjuncts:
        conjuncts = disjunct.split(" and ")
        words.append(len(conjuncts))
        for relation in conjuncts:
            match = re.fullmatch(r"([nivwftce])(?: % ([0-9]+))? (=|!=) ([0-9.,]+)", relation)
            if not match:
                raise RuntimeError(f"Unrecognized pinned CLDR relation: {relation!r}")
            operand, modulus, operator, values = match.groups()
            modulus = int(modulus or 0)
            if modulus > 1_000_000:
                raise RuntimeError("Pinned modulus exceeds the audited small-divisor ceiling")
            pairs = []
            for value in values.split(","):
                bounds = value.split("..")
                if len(bounds) == 1:
                    bounds *= 2
                if len(bounds) != 2 or any(not re.fullmatch(r"[0-9]+", b) for b in bounds):
                    raise RuntimeError("Unknown CLDR interval representation")
                low, high = map(int, bounds)
                if low > high or high > 1_000_000:
                    raise RuntimeError("CLDR interval outside audited generated bounds")
                pairs.extend((low, high))
            words.extend((OPERANDS.index(operand), modulus, int(operator == "!="), len(pairs) // 2, *pairs))
    return words


def quoted(value):
    # All generated payloads are ASCII. JSON's ASCII quoted-string grammar is
    # also valid Swift here (no control characters or Unicode escapes admitted).
    if not re.fullmatch(r"[A-Za-z0-9 .+\-]*", value):
        raise RuntimeError("Unsafe generated Swift string")
    return json.dumps(value)


def generate(data):
    code, offsets, groups, claimed = [], {}, {}, {}
    for kind in ("cardinal", "ordinal"):
        rows, locales = [], set()
        for group in data[kind + "RuleGroups"]:
            if not group["locales"] or any(l in locales for l in group["locales"]):
                raise RuntimeError("Empty/duplicate plural locale group")
            locales.update(group["locales"])
            rules, categories = [], []
            for rule in group["rules"]:
                category = CATEGORIES.index(rule["count"])
                if category in categories:
                    raise RuntimeError("Duplicate category in rule group")
                categories.append(category)
                condition = rule["condition"]
                if condition not in offsets:
                    offsets[condition] = len(code)
                    code.extend(condition_words(condition))
                integer, decimal = rule["integerExample"], rule["decimalExample"]
                for value in integer["values"]:
                    if not re.fullmatch(r"[0-9]+", value) or int(value) > 2_147_483_647:
                        raise RuntimeError("Integer example exceeds Java's Int32 range")
                for value in decimal["values"]:
                    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", value):
                        raise RuntimeError("Unsupported decimal example syntax")
                if not isinstance(integer["infinite"], bool) or not isinstance(decimal["infinite"], bool):
                    raise RuntimeError("Example finiteness must be boolean")
                rules.append(dict(category=category, offset=offsets[condition], integer=integer, decimal=decimal))
            if categories != sorted(categories) or not rules or rules[-1]["category"] != 5 or group["rules"][-1]["condition"]:
                raise RuntimeError("Rules must be enum ordered and finish with unconditional OTHER")
            rows.append(dict(locales=group["locales"], rules=rules))
        groups[kind] = rows
        claimed[kind] = locales
    if "und" not in claimed["cardinal"] or "und" not in claimed["ordinal"]:
        raise RuntimeError("Missing undetermined plural group")
    ranges, locales = [], set()
    for group in data["cardinalRangeGroups"]:
        if not group["locales"] or any(l in locales for l in group["locales"]) or not set(group["locales"]) <= claimed["cardinal"]:
            raise RuntimeError("Range locale is duplicate or absent from cardinal support")
        locales.update(group["locales"])
        slots = [255] * 36
        for row in group["ranges"]:
            start, end, result = (CATEGORIES.index(row[k]) for k in ("start", "end", "result"))
            index = start * 6 + end
            if slots[index] != 255:
                raise RuntimeError("Duplicate cardinal range row")
            slots[index] = result
        ranges.append(dict(locales=group["locales"], slots=slots))
    payload = dict(bytecode=code, groups=groups, ranges=ranges)
    payload_sha = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    lines = [
        "// Generated by Tools/generate_plural_data.py; do not edit.",
        "// CLDR 48.2; Unicode data license: Reference/THIRD-PARTY-NOTICES.spec.md.",
        f"// Source SHA-256: {SOURCE_SHA256}",
        f"// Compiled payload SHA-256: {payload_sha}",
        "package enum PluralTables {",
        '    package static let cldrVersion = "48.2"',
        f'    package static let dataFingerprint = "{FINGERPRINT}"',
        f'    package static let sourceSha256 = "{SOURCE_SHA256}"',
        f'    package static let payloadSha256 = "{payload_sha}"',
        '    package static let generatorVersion = "1.0.0"',
        "    package static let bytecode: [UInt32] = [",
    ]
    for index in range(0, len(code), 24):
        lines.append("        " + ", ".join(map(str, code[index:index + 24])) + ",")
    lines.append("    ]")
    for kind in ("cardinal", "ordinal"):
        lines.append(f"    package static let {kind}Groups: [PluralRuleGroup] = [")
        for group in groups[kind]:
            lines.append("        .init(locales: " + quoted(" ".join(group["locales"])) + ", rules: [")
            for rule in group["rules"]:
                lines.append("            .init(category: %d, conditionOffset: %d, integerSamples: %s, integerInfinite: %s, decimalSamples: %s, decimalInfinite: %s)," % (
                    rule["category"], rule["offset"], quoted(" ".join(rule["integer"]["values"])), str(rule["integer"]["infinite"]).lower(),
                    quoted(" ".join(rule["decimal"]["values"])), str(rule["decimal"]["infinite"]).lower()))
            lines.append("        ]),")
        lines.append("    ]")
    lines.append("    package static let rangeGroups: [PluralRangeGroup] = [")
    for group in ranges:
        lines.append("        .init(locales: " + quoted(" ".join(group["locales"])) + ", results: [" + ", ".join(map(str, group["slots"])) + "]),")
    lines.extend(("    ]", "}", ""))
    return "\n".join(lines), dict(cldrVersion="48.2", sourceSha256=SOURCE_SHA256, payloadSha256=payload_sha,
                                    cardinalGroups=len(groups["cardinal"]), ordinalGroups=len(groups["ordinal"]),
                                    rangeGroups=len(ranges), conditionPrograms=len(offsets), bytecodeWords=len(code), bytecodeBytes=len(code) * 4,
                                    cardinalLocales=len(claimed["cardinal"]), ordinalDirectLocales=len(claimed["ordinal"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/Lokalized/Data/PluralTables.swift")
    args = parser.parse_args()
    raw = (args.reference / "cldr-plural-data.json").read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise RuntimeError("CLDR plural input differs from the frozen baseline")
    data = json.loads(raw)
    if data["formatVersion"] != 1 or data["cldrVersion"] != "48.2":
        raise RuntimeError("CLDR plural format/version differs")
    generated, report = generate(data)
    report["generatedSwiftBytes"] = len(generated.encode())
    if args.refresh:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(generated)
    elif args.output.read_text() != generated:
        raise RuntimeError("Generated plural table differs; use explicit --refresh")
    report["status"] = "refreshed" if args.refresh else "verified"
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"Plural generation refused: {error}", file=sys.stderr)
        sys.exit(1)
