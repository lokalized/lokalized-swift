#!/usr/bin/env python3
"""Prepare/check per-case native type evidence without ratifying corpus mappings.

Python standard library only. Consumes real compiler/host execution evidence and
the actual runtime adapter's input/consultation guards. Original observations are
retained as obligations, never used to configure native execution. Reports add no
runtime passes or native mappings. Missing/stale/altered receipts fail closed.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

import verify_callback_types as types
from verify_package import runtime_adapter_check
from reference_baseline import check as baseline_check

ROOT = Path(__file__).resolve().parents[1]


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        if key in result: raise ValueError(f"Duplicate JSON member: {key}")
        result[key] = value
    return result


def read(path):
    return json.loads(path.read_text(), object_pairs_hook=pairs)


def require(condition, message):
    if not condition: raise ValueError(message)


def exact_fields(value, fields, label):
    require(isinstance(value, dict) and set(value) == set(fields.split()), f"Unexpected {label} fields")


def zero(value):
    return type(value) is int and value == 0


def compiler_check(report):
    exact_fields(report, "formatVersion qualification compiler target sdk hostOS sourceFiles positive negative passed sourceManifestSha256 moduleCompilation runtimeControls sourceInputsRevalidated", "compiler report")
    require(report["formatVersion"] == 2 and report["qualification"] == "native-public-nonoptional-contracts", "Wrong compiler qualification/version")
    require(report["passed"] is True and report["sourceInputsRevalidated"] is True, "Compiler evidence failed or inputs changed")
    version = re.search(r"Swift version (\d+)\.(\d+)\b", report["compiler"]) if isinstance(report["compiler"], str) else None
    require(version is not None and tuple(map(int, version.groups())) >= (6, 2), "Unexpected compiler version")
    require(report["target"] in ("arm64-apple-macosx12.0", "x86_64-apple-macosx12.0"), "Host controls need a declared macOS 12 target")
    require(all(isinstance(report[key], str) and report[key] for key in ("sdk", "hostOS")), "Missing SDK/host identity")
    sources = [{"path": str(p.relative_to(ROOT)), "sha256": digest(p.read_bytes()), "bytes": len(p.read_bytes())}
               for p in sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))]
    require(report["sourceFiles"] == sources and report["sourceManifestSha256"] == digest(canonical(sources)), "Stale/incomplete library source snapshot")
    module = report["moduleCompilation"]
    exact_fields(module, "exitCode diagnostics", "module compilation")
    require(zero(module["exitCode"]) and isinstance(module["diagnostics"], str), "Library compilation failed")
    positive = report["positive"]
    exact_fields(positive, "source sourceSha256 exitCode diagnostics", "positive consumer")
    require(positive["source"] == types.POSITIVE and positive["sourceSha256"] == digest(types.POSITIVE.encode())
            and zero(positive["exitCode"]) and isinstance(positive["diagnostics"], str), "Positive consumer is stale or failed")
    negatives = report["negative"]
    require(isinstance(negatives, list) and len(negatives) == len(types.NEGATIVE), "Missing/extra negative consumers")
    require([item.get("name") for item in negatives] == list(types.NEGATIVE), "Duplicate/reordered/unknown negative consumer")
    for item in negatives:
        exact_fields(item, "name source sourceSha256 requiredType exitCode diagnostics passed", "negative consumer")
        body, token = types.NEGATIVE[item["name"]]
        source = "import Lokalized\n" + body + "\n"
        require(item["source"] == source and item["sourceSha256"] == digest(source.encode()) and item["requiredType"] == token,
                "Changed negative consumer input/type")
        require(type(item["exitCode"]) is int and item["exitCode"] != 0 and item["passed"] is True
                and isinstance(item["diagnostics"], str) and types.intended_nil_refusal(item["diagnostics"], token),
                "Negative consumer did not fail for its intended nil/type reason")
    controls = report["runtimeControls"]
    exact_fields(controls, "sourcePath source sourceSha256 compilationExitCode compilationDiagnostics executionExitCode stdout stderr observed passed", "runtime controls")
    source = (ROOT / "Tools/Fixtures/NativeTypeControls.swift").read_text()
    require(controls["sourcePath"] == "Tools/Fixtures/NativeTypeControls.swift" and controls["source"] == source
            and controls["sourceSha256"] == digest(source.encode()), "Changed runtime control inputs")
    require(zero(controls["compilationExitCode"]) and zero(controls["executionExitCode"]) and controls["passed"] is True,
            "Runtime controls did not compile/execute")
    require(isinstance(controls["stdout"], str) and isinstance(controls["stderr"], str)
            and isinstance(controls["compilationDiagnostics"], str), "Invalid runtime diagnostics")
    require(json.loads(controls["stdout"], object_pairs_hook=pairs) == controls["observed"] == {"passed": types.RUNTIME_IDS},
            "Runtime controls omitted/replaced/changed checks")
    return report


def evidence_for(guards, fixture):
    negatives, controls = set(), set()
    for guard in guards:
        category, path = guard["category"], guard["inputPath"]
        if category == "callback-null-configuration":
            if "translationFailureHandler" in path:
                negatives.add("failure-handler-nil")
                controls.update(["handler-unconsulted-on-success", "handler-after-complete-walk"])
            elif "translationFallbackPolicy" in path:
                negatives.add("fallback-policy-nil")
                controls.update(["policy-unconsulted-on-single-candidate", "policy-before-handler-get", "policy-before-handler-getResult",
                    "policy-error-get", "policy-error-getResult", "policy-error-preserves-consultation-cause", "policy-receives-current-resolution-cause"])
            elif "phoneticResolver" in path:
                negatives.add("phonetic-resolver-nil")
                controls.update(["expression-resolver-error-retains-cause", "handler-retains-first-same-type-cause",
                    "result-retains-first-same-type-cause", "get-rethrows-first-cause-verbatim", "other-is-valid-phonetic-category"])
            else: raise ValueError(f"Unknown callback guard: {path}")
        elif category == "catalog-null-shape":
            source = fixture["constructionOverrides"]["catalogSource"]
            mapping = {"returnsNull": ["catalog-supplier-nil"], "nullCatalogValue": ["catalog-value-nil"],
                       "nullLocaleKey": ["catalog-key-nil"], "nullEntry": ["catalog-entry-nil", "catalog-entry-value-nil"]}
            require(source in mapping, "Unknown null catalog shape")
            negatives.update(mapping[source]); controls.update(["raw-null-catalog-refused", "raw-null-entry-refused"])
        elif category == "tiebreaker-null-shape":
            source = fixture["constructionOverrides"]["tiebreakerSource"]
            mapping = {"nullList": "tiebreaker-list-nil", "nullEntry": "tiebreaker-entry-nil", "nullLanguageCode": "tiebreaker-key-nil"}
            require(source in mapping, "Unknown null tiebreaker shape")
            negatives.add(mapping[source]); controls.add("nil-whole-tiebreaker-setting-is-valid")
        elif category == "placeholder-name-null":
            negatives.add("placeholder-key-nil")
            controls.update(["explicit-null-remains-runtime-refusal", "missing-binding-remains-runtime-refusal", "raw-null-placeholder-definition-refused"])
        elif category == "phonetic-unmapped-null-return":
            negatives.add("phonetic-resolver-nil")
            controls.update(["unmapped-resolver-can-throw-explicitly", "other-is-valid-phonetic-category"])
        else: raise ValueError(f"Unclassified native guard: {category}")
    require(negatives and controls, "Case lacks compiler/runtime evidence")
    require(negatives <= set(types.NEGATIVE) and controls <= set(types.RUNTIME_IDS), "Unknown evidence consumer/control")
    return sorted(negatives), sorted(controls)


def check_guards(guards, row, fixture):
    """Check the claimed unavailable shape against authored input, not expected output."""
    expected_paths = set()
    if row["input"].get("nullPlaceholderName") is True:
        expected_paths.add(("placeholder-name-null", "input.nullPlaceholderName"))
    overrides = fixture.get("constructionOverrides") or {}
    if overrides.get("catalogSource") in ("returnsNull", "nullCatalogValue", "nullLocaleKey", "nullEntry"):
        expected_paths.add(("catalog-null-shape", "fixture.constructionOverrides.catalogSource"))
    if overrides.get("tiebreakerSource") in ("nullList", "nullEntry", "nullLanguageCode"):
        expected_paths.add(("tiebreaker-null-shape", "fixture.constructionOverrides.tiebreakerSource"))
    for label, source in (("fixture", fixture), ("input", row["input"])):
        for name in ("translationFailureHandler", "translationFallbackPolicy", "phoneticResolver"):
            value = source.get(name)
            if isinstance(value, dict) and value.get("behavior") == "return-null":
                expected_paths.add(("callback-null-configuration", f"{label}.{name}.behavior"))
    actual_paths = [(guard["category"], guard["inputPath"]) for guard in guards]
    require(len(actual_paths) == len(set(actual_paths)), "Duplicated unavailable shape guard")
    consultations = [guard for guard in guards if guard["category"] == "phonetic-unmapped-null-return"]
    for guard in consultations:
        resolver = row["input"].get("phoneticResolver", fixture.get("phoneticResolver"))
        require(isinstance(resolver, dict), "Consultation guard has no configured resolver")
        pattern = r'Actual (by-term|by-locale) consultation has term=("(?:[^"\\]|\\.)*"), locale=("(?:[^"\\]|\\.)*"); no mapping/default exists and native Phonetic is nonoptional'
        match = re.fullmatch(pattern, guard["evidence"])
        require(match is not None and match[1] == resolver.get("behavior"), "Invalid actual consultation evidence")
        term, locale = json.loads(match[2]), json.loads(match[3])
        require(term in row["input"].get("placeholders", {}).values(), "Consulted term is absent from caller input")
        require(resolver.get("default") is None and (term if match[1] == "by-term" else locale) not in resolver.get("mapping", {}),
                "Claimed unmapped consultation has a mapping/default")
        require(guard["inputPath"] == "fixture.phoneticResolver.mapping/default", "Wrong consultation guard path")
        expected_paths.add((guard["category"], guard["inputPath"]))
    require(set(actual_paths) == expected_paths and expected_paths, "Runtime guard does not match the unavailable authored shape")


def dossier(type_report, runtime_report):
    compiler_check(type_report)
    # Retains the independent 1,432/20 adapter inventory and its complete comparisons.
    # Write no expected value into an input or native callback.
    corpus = read(ROOT / "Reference/behavioral-vectors.json")
    rows = {row["id"]: row for row in corpus["cases"]}
    cases = []
    for pending in runtime_report["pending"]:
        row = rows[pending["id"]]
        fixture = corpus["fixtures"][row["fixture"]]
        check_guards(pending["guards"], row, fixture)
        negatives, controls = evidence_for(pending["guards"], fixture)
        cases.append({"id": row["id"], "operation": row["operation"], "partition": row["partition"],
            "inputSha256": digest(canonical({"operation": row["operation"], "input": row["input"], "fixture": fixture})),
            "guards": pending["guards"], "negativeConsumers": negatives, "adjacentRuntimeControls": controls,
            "notReplayedObservationChannels": sorted(row["expected"]),
            "referenceObservationSha256": digest(canonical(row["expected"])),
            "disposition": "evidence-ready-unratified"})
    ids = [row["id"] for row in cases]
    require(ids == sorted(set(ids)) and len(ids) == 20, "Native evidence must account for all twenty cases")
    require(digest("".join(value + "\n" for value in ids).encode()) == "e19eacaf8f0773df2bdb0ca83e38a025fa8b964f20f2dfc188ec05e5fd83dd79", "Changed pending native ID set")
    return {"formatVersion": 1, "scope": "native-type-representation-evidence", "status": "evidence-ready-unratified",
        "nativeMappingsRatified": False, "releaseParity": False, "runtimePassedAdded": [], "nativeRepresentationMapped": [],
        "pendingIDs": ids, "pendingIDsSHA256": digest("".join(value + "\n" for value in ids).encode()),
        "compilerReportSHA256": digest(canonical(type_report)), "runtimeAdapterReportSHA256": digest(canonical(runtime_report)),
        "librarySourceManifestSHA256": type_report["sourceManifestSha256"], "negativeConsumers": list(types.NEGATIVE),
        "adjacentRuntimeControls": types.RUNTIME_IDS, "cases": cases,
        "limits": ["Compiler refusal is not replay of Java null diagnostics or callback traces.",
            "Adjacent runtime controls exercise representable inputs; all original observation channels remain unreplayed for these twenty cases.",
            "macOS host execution and emitted macOS 12 target do not establish old-OS, iOS or Intel runtime coverage.",
            "No JVM carrier, filename-order mapping or shared representation disposition is ratified by this report."]}


def check_dossier(actual, expected):
    require(canonical(actual) == canonical(expected), "Native representation evidence is altered, stale or incomplete")


def negative_controls(expected, compiler, runtime):
    rejected = []
    variants = []
    def changed(name, mutate):
        value = copy.deepcopy(expected); mutate(value); variants.append((name, value))
    changed("missing-case", lambda d: d["cases"].pop())
    changed("duplicated-case", lambda d: d["cases"].append(d["cases"][0]))
    changed("runtime-pass-inflation", lambda d: d["runtimePassedAdded"].append(d["pendingIDs"][0]))
    changed("ratification-claim", lambda d: d.update(nativeMappingsRatified=True))
    changed("release-parity-claim", lambda d: d.update(releaseParity=True))
    changed("wrong-negative-consumer", lambda d: d["cases"][0].update(negativeConsumers=["failure-handler-nil"]))
    changed("omitted-original-channel", lambda d: d["cases"][0]["notReplayedObservationChannels"].pop())
    changed("changed-input-fingerprint", lambda d: d["cases"][0].update(inputSha256="0" * 64))
    changed("changed-observation-fingerprint", lambda d: d["cases"][0].update(referenceObservationSha256="0" * 64))
    changed("missing-guard-evidence", lambda d: d["cases"][0].update(guards=[]))
    changed("missing-adjacent-control", lambda d: d["cases"][0].update(adjacentRuntimeControls=[]))
    changed("unknown-field", lambda d: d.update(trusted=True))
    for name, value in variants:
        try: check_dossier(value, expected)
        except ValueError: rejected.append(name)
        else: raise ValueError(f"Altered dossier passed: {name}")
    edits = [
        ("stale-library-source", lambda d: d["sourceFiles"][0].update(sha256="0" * 64)),
        ("successful-negative-consumer", lambda d: d["negative"][0].update(exitCode=0)),
        ("unrelated-compiler-error", lambda d: d["negative"][0].update(diagnostics="error: cannot find 'TranslationFailureResponse' in scope")),
        ("changed-negative-source", lambda d: d["negative"][0].update(source="import Lokalized\n")),
        ("omitted-negative-consumer", lambda d: d["negative"].pop()),
        ("duplicate-negative-consumer", lambda d: d["negative"].append(d["negative"][0])),
        ("missing-runtime-control", lambda d: d["runtimeControls"]["observed"]["passed"].pop()),
        ("failed-runtime-execution", lambda d: d["runtimeControls"].update(executionExitCode=1)),
        ("changed-runtime-source", lambda d: d["runtimeControls"].update(source="print(\"passed\")")),
        ("source-change-during-run", lambda d: d.update(sourceInputsRevalidated=False)),
    ]
    for name, mutate in edits:
        value = copy.deepcopy(compiler); mutate(value)
        try: compiler_check(value)
        except ValueError: rejected.append(name)
        else: raise ValueError(f"Altered compiler receipt passed: {name}")
    value = copy.deepcopy(runtime)
    value["pending"][0]["guards"][0]["inputPath"] = "input.translationFailureHandler.behavior"
    try: dossier(compiler, value)
    except ValueError: rejected.append("guard-unrelated-to-authored-input")
    else: raise ValueError("Guard unrelated to authored input passed")
    return rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type-report", type=Path, required=True)
    parser.add_argument("--runtime-adapter-report", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--report-check", type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    try:
        baseline_check(ROOT / "Reference")
        runtime_adapter_check(args.runtime_adapter_report, ROOT / "Reference")
        compiler, runtime = read(args.type_report), read(args.runtime_adapter_report)
        expected = dossier(compiler, runtime)
        if args.report_check: check_dossier(read(args.report_check), expected)
        controls = negative_controls(expected, compiler, runtime) if args.negative_controls else []
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(expected, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        print(json.dumps({"status": expected["status"], "pendingCasesWithEvidence": len(expected["cases"]),
            "negativeConsumers": len(types.NEGATIVE), "adjacentRuntimeControls": len(types.RUNTIME_IDS),
            "nativeMappingsRatified": False, "runtimePassedAdded": 0, "rejectedControls": controls}))
        return 0
    except (ValueError, RuntimeError, KeyError, TypeError, OSError) as error:
        print(json.dumps({"status": "error", "error": str(error)})); return 1


if __name__ == "__main__":
    raise SystemExit(main())
