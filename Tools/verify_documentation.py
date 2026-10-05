#!/usr/bin/env python3
"""Compile and execute the consumer programs authored in Markdown.

Python stdlib and the selected Apple Swift toolchain only. The sole edit to
each consumer manifest substitutes the documented remote dependency with a
fresh local snapshot. Code, resources and expected output come from the docs.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DOCUMENTS = (("README.md", "quickstart", "QuickStart", ()),
             ("Documentation/USAGE.md", "catalogs", "Catalogs", ("en", "fr")))
REMOTE = '.package(url: "https://github.com/lokalized/lokalized-swift", from: "1.0.0")'
BLOCK = re.compile(r'<!-- lokalized-example: ([a-z]+) ([a-z-]+) -->\n```([a-z]+)\n(.*?)\n```', re.DOTALL)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def extract(text, identity, locales):
    blocks = list(BLOCK.finditer(text))
    if text.count("<!-- lokalized-example:") != len(blocks):
        raise ValueError("Malformed documentation example marker or fence")
    roles = {"manifest": "swift", "source": "swift", "output": "text"}
    roles.update({"catalog-" + locale: "json" for locale in locales})
    values = {role: [] for role in roles}
    for block in blocks:
        name, role, language, body = block.groups()
        if name != identity or role not in roles or language != roles[role]:
            raise ValueError("Unexpected documentation example identity, role or language")
        values[role].append(body + "\n")
    if not values["source"] or any(len(value) != 1 for role, value in values.items() if role != "source"):
        raise ValueError("Missing or duplicated manifest, catalog, source or output")
    manifest = values["manifest"][0]
    if manifest.count(REMOTE) != 1:
        raise ValueError("Documented dependency differs; review its local substitution")
    return {"manifest": manifest.replace(REMOTE, '.package(path: "../lokalized-swift")'),
            "source": "\n".join(values["source"]), "sourceBlocks": len(values["source"]),
            "output": values["output"][0],
            "catalogs": {locale: values["catalog-" + locale][0] for locale in locales}}


def inputs():
    paths = [ROOT / "Package.swift", Path(__file__).resolve(), ROOT / "Documentation/DEVELOPMENT.md"]
    paths += [ROOT / document for document, *_ in DOCUMENTS]
    for directory in ("Sources", "Tests"):
        paths += [p for p in (ROOT / directory).rglob("*") if p.is_file()
                  and not any(part in (".build", "__pycache__", ".DS_Store") for part in p.relative_to(ROOT).parts)]
    return {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in sorted(paths)}


def invoke(report, command, cwd, environment):
    print(" ".join(command[:3]), file=sys.stderr, flush=True)
    result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True)
    stdout = result.stdout.decode("utf-8")
    stderr = result.stderr.decode("utf-8", errors="replace")
    report["commands"].append({"arguments": command, "cwd": str(cwd),
                               "exitCode": result.returncode, "stdout": stdout, "stderr": stderr})
    if result.returncode:
        raise RuntimeError(f"Documentation command failed ({result.returncode}): {command}\n{stderr[-6000:]}")
    return stdout


def qualify(args, report):
    before = inputs()
    report["inputSha256"] = before
    examples = [(document, name, target, extract((ROOT / document).read_text(), name, locales))
                for document, name, target, locales in DOCUMENTS]
    with tempfile.TemporaryDirectory(prefix="lokalized-documentation-", dir="/private/tmp") as temporary:
        scratch = Path(temporary)
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(scratch / "clang-cache")
        compiler = invoke(report, ["swift", "--version"], ROOT, environment).strip()
        report["compiler"] = compiler
        version = re.search(r"Swift version (\d+)\.(\d+)", compiler)
        if not version or tuple(map(int, version.groups())) < (6, 2):
            raise ValueError("Documentation requires Swift 6.2 or later")
        report["minimumCompilerExecuted"] = tuple(map(int, version.groups())) == (6, 2)
        if args.compiler_track == "minimum" and not report["minimumCompilerExecuted"]:
            raise ValueError("Minimum compiler track must execute Swift 6.2")
        snapshot = scratch / "lokalized-swift"
        snapshot.mkdir()
        shutil.copy2(ROOT / "Package.swift", snapshot / "Package.swift")
        for directory in ("Sources", "Tests"):
            shutil.copytree(ROOT / directory, snapshot / directory,
                            ignore=shutil.ignore_patterns(".build", "__pycache__", ".DS_Store"))
        common = ["--disable-sandbox", "--cache-path", str(scratch / "cache"),
                  "--config-path", str(scratch / "config"), "--security-path", str(scratch / "security")]
        library = json.loads(invoke(report, ["swift", "package", *common, "dump-package"], snapshot, environment))
        if library["dependencies"] or any(t.get("pluginUsages") for t in library["targets"]):
            raise ValueError("Library must retain zero external dependencies and plugins")
        for document, name, target, example in examples:
            consumer = scratch / name
            source_directory = consumer / "Sources" / target
            source_directory.mkdir(parents=True)
            (consumer / "Package.swift").write_text(example["manifest"])
            (source_directory / "main.swift").write_text(example["source"])
            for locale, text in example["catalogs"].items():
                resource = source_directory / "Lokalized" / ("en" if locale == "en" else "fr.json")
                resource.parent.mkdir(exist_ok=True)
                resource.write_text(text, encoding="utf-8")
            build = common + ["--scratch-path", str(scratch / (name + "-build"))]
            manifest = json.loads(invoke(report, ["swift", "package", *build, "dump-package"], consumer, environment))
            dependencies = manifest["dependencies"]
            if (len(dependencies) != 1 or set(dependencies[0]) != {"fileSystem"}
                    or len(dependencies[0]["fileSystem"]) != 1
                    or Path(dependencies[0]["fileSystem"][0]["path"]).resolve() != snapshot):
                raise ValueError("Documentation consumer must depend only on the local source snapshot")
            invoke(report, ["swift", "build", *build, "--product", target], consumer, environment)
            binary_directory = invoke(report, ["swift", "build", *build, "--show-bin-path"], consumer, environment).strip()
            binary = Path(binary_directory) / target
            actual = invoke(report, [str(binary)], consumer, environment)
            if actual != example["output"]:
                raise ValueError(f"Documented output differs for {name}: expected {example['output']!r}, got {actual!r}")
            report["examples"].append({"id": name, "document": document, "target": target,
                                       "sourceBlocks": example["sourceBlocks"], "output": actual,
                                       "binarySha256": sha(binary.read_bytes()),
                                       "catalogSha256": {locale: sha(text.encode("utf-8")) for locale, text in example["catalogs"].items()},
                                       "status": "compiled-and-executed"})
        if any((snapshot / name).exists() for name in ("Reference", "Tools")):
            raise ValueError("Development inputs must be absent from the source snapshot")
        if before != inputs():
            raise ValueError("Documentation or source inputs changed during verification")
    report["status"] = "passed"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler-track", choices=("minimum", "current"), default="current")
    parser.add_argument("--report", type=Path, default=ROOT / ".build/reports/documentation.json")
    args = parser.parse_args()
    report = {"status": "running", "compilerTrack": args.compiler_track,
              "startedAtUTC": datetime.now(timezone.utc).isoformat(), "commands": [], "examples": [],
              "scope": "Markdown consumer examples on the selected host; no iOS or minimum-OS runtime claim",
              "dependencySubstitution": {"documented": REMOTE, "executed": '.package(path: "../lokalized-swift")'},
              "referenceArtifactsRequiredToBuild": False, "externalPackageDependencies": 0}
    try:
        qualify(args, report)
    except (OSError, ValueError, RuntimeError) as error:
        report.update(status="failed", error=str(error))
    report["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "examples": len(report["examples"]), "report": str(args.report)}))
    if report["status"] != "passed":
        print(report["error"], file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
