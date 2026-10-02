#!/usr/bin/env python3
"""Account for each frozen reference API and qualify its native public presence.

Ordinary ledger/report checks use local artifacts and Python's standard library.
--qualify compiles current sources in isolation and asks Apple's symbol-graph
extractor for public declarations/conformances. This does not certify behavior,
overload equivalence, classloader adaptations or shared representation mappings.
"""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

import api_coverage_policy as policy
from api_inventory import check_inventory
from reference_baseline import check as baseline_check

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "Reference/swift-api-coverage.json"
POLICY = ROOT / "Tools/api_coverage_policy.py"
LIMITS = [
    "Public type/member-family presence and native conformances are qualified, not full overload or behavioral equivalence.",
    "Java debug rendering, enum lookup, builders, closures, local carriers and JS-specific delivery have explicit native dispositions.",
    "No shared corpus pass or native representation mapping is added by this inventory.",
    "Compilation at macOS 12 does not establish old-OS/iOS/Intel runtime execution or the minimum Swift compiler."]


def canonical(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
def sha(data): return hashlib.sha256(data).hexdigest()
def require(condition, message):
    if not condition: raise ValueError(message)


def unique_pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, f"Duplicate JSON member {key}")
        result[key] = value
    return result


def read(path): return json.loads(path.read_text(), object_pairs_hook=unique_pairs)


def expected_ledger():
    baseline = baseline_check(ROOT / "Reference")
    inventory = read(ROOT / "Reference/api-inventory.json")
    check_inventory(inventory, baseline)
    records = []
    def record(identifier, language, owner, declaration, kind, runtime, disposition):
        records.append({"id": identifier, "language": language, "referenceOwner": owner,
            "referenceDeclaration": declaration, "referenceKind": kind, "runtimeExport": runtime, **disposition})
    for entry in inventory["java"]["types"]:
        name = entry["name"]
        record("java:type:" + name, "java", name, entry["declaration"], "type", None, policy.java(name))
        for member in entry["members"]:
            record("java:member:" + name + ":" + member, "java", name, member, "member", None, policy.java(name, member))
    for entry in inventory["javascript"]["entries"]:
        for decl in entry["declarations"]:
            name = decl["name"]
            record("js:" + entry["entryPoint"] + ":" + name, "javascript", entry["entryPoint"], decl["declaration"], decl["kind"],
                   name in entry["runtimeSymbols"], policy.javascript(name))
    records.sort(key=lambda item: item["id"])
    require(len(records) == len({row["id"] for row in records}), "Duplicate reference API ID")
    require(len(records) == 747, "Reviewed reference API occurrence inventory changed")
    return {"formatVersion": 1, "scope": "reference-api-native-dispositions", "status": "accounted-not-certified",
        "apiInventorySHA256": inventory["inventorySha256"], "policySHA256": sha(POLICY.read_bytes()),
        "javaPublicTypes": len(inventory["java"]["types"]),
        "javaPublicMembers": sum(len(entry["members"]) for entry in inventory["java"]["types"]),
        "javascriptDeclarationOccurrences": sum(len(entry["declarations"]) for entry in inventory["javascript"]["entries"]),
        "javascriptRuntimeExportOccurrences": sum(len(entry["runtimeSymbols"]) for entry in inventory["javascript"]["entries"]),
        "dispositions": dict(sorted(Counter(row["disposition"] for row in records).items())),
        "recordsSHA256": sha(canonical(records)), "records": records}


def ledger_check(actual, expected):
    require(canonical(actual) == canonical(expected), "API ledger is altered, stale, incomplete or has an unreviewed disposition")


def source_snapshot():
    return [{"path": str(p.relative_to(ROOT)), "bytes": len(p.read_bytes()), "sha256": sha(p.read_bytes())}
            for p in sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))]


def normalize_graph(graph):
    symbols = sorted([{"id": s["identifier"]["precise"], "path": s["pathComponents"],
        "kind": s["kind"]["identifier"], "accessLevel": s["accessLevel"],
        "declaration": "".join(f["spelling"] for f in s.get("declarationFragments", []))} for s in graph["symbols"]], key=lambda s: s["id"])
    conformances = sorted([{key: relationship[key] for key in ("source", "target", "targetFallback") if key in relationship}
        for relationship in graph["relationships"] if relationship["kind"] == "conformsTo"], key=canonical)
    return {"moduleName": graph["module"]["name"], "symbols": symbols, "conformances": conformances}


def witnesses(ledger, graph):
    require(set(graph) == {"moduleName", "symbols", "conformances"} and graph["moduleName"] == "Lokalized", "Wrong graph module/fields")
    require(isinstance(graph["symbols"], list) and isinstance(graph["conformances"], list), "Invalid graph arrays")
    symbols = graph["symbols"]
    require(all(set(s) == {"id", "path", "kind", "accessLevel", "declaration"} and s["accessLevel"] == "public"
                and isinstance(s["id"], str) and isinstance(s["path"], list) and s["path"]
                and all(isinstance(p, str) for p in s["path"]) for s in symbols), "Graph contains unknown/nonpublic declarations")
    ids = [s["id"] for s in symbols]
    require(ids == sorted(set(ids)), "Graph symbol IDs must be sorted, unique and complete")
    owners = {}
    for symbol in symbols: owners.setdefault(tuple(symbol["path"]), []).append(symbol)
    result = []
    for row in ledger["records"]:
        owner = row["swiftOwner"]
        if owner is None:
            require(row["disposition"] == "platform-specific", "Only an explicit platform disposition may omit a native target")
            result.append({"id": row["id"], "status": "platform-specific", "publicSymbols": [], "conformances": []}); continue
        path = owner.split("/")
        owner_symbols = owners.get(tuple(path), [])
        require(owner_symbols, f"Native public type missing for {row['id']}: {owner}")
        member = row["swiftMemberFamily"]
        found = owner_symbols if member is None else [s for s in symbols if s["path"][:-1] == path and s["path"][-1].split("(", 1)[0] == member]
        require(found, f"Native public member family missing for {row['id']}: {owner}/{member}")
        conformances = []
        if row["requiredConformance"]:
            owner_ids = {s["id"] for s in owner_symbols}
            conformances = [r for r in graph["conformances"] if r["source"] in owner_ids and r.get("targetFallback") == row["requiredConformance"]]
            require(conformances, f"Required native conformance missing for {row['id']}: {row['requiredConformance']}")
        result.append({"id": row["id"], "status": "public-presence-qualified", "publicSymbols": found, "conformances": conformances})
    return result


def run(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True)
    require(result.returncode == 0, f"{arguments[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result


def qualify(ledger):
    require(platform.system() == "Darwin", "Apple SDK qualification needs macOS")
    compiler, extractor = shutil.which("swiftc"), run(["xcrun", "--find", "swift-symbolgraph-extract"]).stdout.strip()
    require(compiler, "Swift compiler unavailable")
    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).stdout.strip()
    target = platform.machine() + "-apple-macosx12.0"
    snapshot = source_snapshot()
    require(snapshot, "No library sources")
    with tempfile.TemporaryDirectory(prefix="lokalized-api-coverage-", dir="/private/tmp") as temp:
        scratch = Path(temp); paths = []
        for source in snapshot:
            path = scratch / source["path"]; path.parent.mkdir(parents=True, exist_ok=True)
            data = (ROOT / source["path"]).read_bytes()
            require(sha(data) == source["sha256"], "Library source changed before compile")
            path.write_bytes(data); paths.append(str(path))
        common = ["-target", target, "-sdk", sdk, "-module-cache-path", str(scratch / "module-cache")]
        module = run([compiler, "-swift-version", "6", *common, "-parse-as-library", "-emit-module", "-module-name", "Lokalized",
            "-package-name", "lokalized_swift", "-emit-module-path", str(scratch / "Lokalized.swiftmodule"), *paths])
        output = scratch / "graphs"; output.mkdir()
        extracted = run([extractor, *common, "-module-name", "Lokalized", "-I", str(scratch),
            "-minimum-access-level", "public", "-output-dir", str(output)])
        require(sorted(p.name for p in output.glob("*.json")) == ["Lokalized.symbols.json"], "Unexpected extraction graph inventory")
        graph = normalize_graph(read(output / "Lokalized.symbols.json"))
        observed = witnesses(ledger, graph)
    require(source_snapshot() == snapshot, "Library sources changed during qualification")
    require(sha(POLICY.read_bytes()) == ledger["policySHA256"], "Coverage policy changed during qualification")
    ledger_check(read(LEDGER), ledger)
    return {"formatVersion": 1, "scope": "native-public-api-presence", "status": "qualified-not-certified",
        "releaseParity": False, "behavioralParity": False, "ledgerSHA256": sha(canonical(ledger)),
        "compiler": run([compiler, "--version"]).stdout.strip(), "extractor": extractor, "target": target, "sdk": sdk,
        "hostOS": platform.platform(), "sourceFiles": snapshot, "sourceManifestSHA256": sha(canonical(snapshot)),
        "sourceInputsRevalidated": True, "moduleCompilationExitCode": module.returncode, "moduleDiagnostics": module.stdout + module.stderr,
        "extractionExitCode": extracted.returncode, "extractionDiagnostics": extracted.stdout + extracted.stderr,
        "publicGraphSHA256": sha(canonical(graph)), "publicGraph": graph,
        "witnessesSHA256": sha(canonical(observed)), "witnesses": observed,
        "limits": LIMITS}


def report_check(report, ledger):
    fields = "formatVersion scope status releaseParity behavioralParity ledgerSHA256 compiler extractor target sdk hostOS sourceFiles sourceManifestSHA256 sourceInputsRevalidated moduleCompilationExitCode moduleDiagnostics extractionExitCode extractionDiagnostics publicGraphSHA256 publicGraph witnessesSHA256 witnesses limits".split()
    require(isinstance(report, dict) and set(report) == set(fields), "Unexpected public API report fields")
    require(report["formatVersion"] == 1 and report["scope"] == "native-public-api-presence" and report["status"] == "qualified-not-certified", "Wrong API report qualification")
    require(report["releaseParity"] is False and report["behavioralParity"] is False, "API presence cannot certify release/behavioral parity")
    require(report["ledgerSHA256"] == sha(canonical(ledger)), "Stale native API ledger receipt")
    snapshot = source_snapshot()
    require(report["sourceFiles"] == snapshot and report["sourceManifestSHA256"] == sha(canonical(snapshot)) and report["sourceInputsRevalidated"] is True,
            "Stale/incomplete API compilation source receipt")
    require(all(type(report[name]) is int and report[name] == 0 for name in ("moduleCompilationExitCode", "extractionExitCode")), "Compilation/extraction did not succeed")
    require(report["target"] in ("arm64-apple-macosx12.0", "x86_64-apple-macosx12.0") and
            all(isinstance(report[key], str) and report[key] for key in ("compiler", "sdk", "extractor", "hostOS")), "Missing compiler/SDK/target evidence")
    graph = report["publicGraph"]
    require(report["publicGraphSHA256"] == sha(canonical(graph)), "Changed symbol graph receipt")
    actual = witnesses(ledger, graph)
    require(report["witnesses"] == actual and report["witnessesSHA256"] == sha(canonical(actual)), "Missing/altered reference API witness")
    require(report["limits"] == LIMITS, "Qualification limits are missing or altered")


def negative_controls(ledger, report):
    rejected = []
    def check(name, original, mutate, verify):
        value = copy.deepcopy(original); mutate(value)
        try: verify(value)
        except (ValueError, KeyError, TypeError): rejected.append(name)
        else: raise ValueError(f"Altered API evidence passed: {name}")
    for name, mutate in [
        ("missing-reference-member", lambda d: d["records"].pop()),
        ("duplicate-reference-member", lambda d: d["records"].append(d["records"][0])),
        ("changed-native-target", lambda d: d["records"][0].update(swiftOwner="NoSuchNativeType")),
        ("invented-platform-exclusion", lambda d: d["records"][0].update(disposition="platform-specific", swiftOwner=None)),
        ("changed-reference-signature", lambda d: d["records"][0].update(referenceDeclaration="public void other();")),
        ("unknown-ledger-field", lambda d: d.update(trusted=True)),
    ]: check(name, ledger, mutate, lambda d: ledger_check(d, ledger))
    for name, mutate in [
        ("missing-witness", lambda d: d["witnesses"].pop()),
        ("duplicate-witness", lambda d: d["witnesses"].append(d["witnesses"][0])),
        ("stale-source", lambda d: d["sourceFiles"][0].update(sha256="0" * 64)),
        ("compile-failed", lambda d: d.update(moduleCompilationExitCode=1)),
        ("extract-failed", lambda d: d.update(extractionExitCode=1)),
        ("fabricated-behavioral-parity", lambda d: d.update(behavioralParity=True)),
        ("fabricated-release-parity", lambda d: d.update(releaseParity=True)),
        ("source-change-during-compile", lambda d: d.update(sourceInputsRevalidated=False)),
        ("altered-graph", lambda d: d["publicGraph"]["symbols"][0].update(accessLevel="private")),
        ("omitted-limits", lambda d: d.update(limits=[])),
        ("altered-limits", lambda d: d["limits"].__setitem__(0, "All overloads and behaviors are certified.")),
    ]: check(name, report, mutate, lambda d: report_check(d, ledger))
    value = copy.deepcopy(report)
    value["publicGraph"]["symbols"] = [s for s in value["publicGraph"]["symbols"] if s["path"] != ["TranslationOptions", "forAcceptLanguage(_:using:)"]]
    value["publicGraphSHA256"] = sha(canonical(value["publicGraph"]))
    try: report_check(value, ledger)
    except ValueError: rejected.append("missing-real-member-with-rehashed-graph")
    else: raise ValueError("Missing required public header factory passed")
    return rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--refresh", action="store_true", help="explicitly rebuild reviewed supplemental ledger")
    modes.add_argument("--qualify", action="store_true", help="compile current sources and extract public API evidence")
    modes.add_argument("--report-check", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    try:
        expected = expected_ledger()
        if args.refresh: LEDGER.write_text(json.dumps(expected, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        ledger_check(read(LEDGER), expected)
        report = qualify(expected) if args.qualify else read(args.report_check) if args.report_check else None
        if report: report_check(report, expected)
        require(not args.report or report is not None, "--report needs --qualify or --report-check")
        require(not args.negative_controls or report is not None, "Report controls require actual public API evidence")
        controls = negative_controls(expected, report) if args.negative_controls else []
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        print(json.dumps({"status": "qualified-not-certified" if report else expected["status"],
            "javaPublicTypes": expected["javaPublicTypes"], "javaPublicMembers": expected["javaPublicMembers"],
            "javascriptDeclarationOccurrences": expected["javascriptDeclarationOccurrences"],
            "javascriptRuntimeExportOccurrences": expected["javascriptRuntimeExportOccurrences"],
            "referenceAPIRecords": len(expected["records"]), "dispositions": expected["dispositions"],
            "releaseParity": False, "rejectedControls": controls}))
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, TypeError) as error:
        print(json.dumps({"status": "error", "error": str(error)})); return 1


if __name__ == "__main__": raise SystemExit(main())
