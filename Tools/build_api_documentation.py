#!/usr/bin/env python3
"""Build the public DocC reference with the selected Xcode's tools; no plugin dependencies.

Copyright 2026 Revetware LLC. Licensed under the Apache License, Version 2.0.
"""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?")


def run(command, env=None, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, env=env, text=True).strip()


def edition_for(release):
    if release is None:
        return "development"
    if not SEMVER.fullmatch(release):
        raise ValueError("--release requires a semantic version without a v prefix or build metadata")
    return release


INTERNAL_NOTES = re.compile(r"\b(?:BOOT-M\d+-\d+|M-R S\d+|amendment A\d+|TODO|FIXME)\b|\b\w+\.java:\d+|\b(?:test/\S+|conformance\.mjs|development conformance executable|entire shared corpus)\b", re.I)


def coverage_for(graphs):
    symbols = {}
    for graph in graphs:
        if graph["module"]["name"] != "Lokalized":
            raise ValueError("The public reference must contain only the Lokalized module")
        for symbol in graph["symbols"]:
            symbols[symbol["identifier"]["precise"]] = symbol
    if not symbols:
        raise ValueError("No public symbols were extracted")
    documented = lambda symbol: any(line.get("text", "").strip() for line in symbol.get("docComment", {}).get("lines", []))
    top = [symbol for symbol in symbols.values() if len(symbol["pathComponents"]) == 1]
    missing = sorted(symbol["names"]["title"] for symbol in top if not documented(symbol))
    if missing:
        raise ValueError(f"Public top-level declarations need documentation: {', '.join(missing)}")
    authored = [symbol for symbol in symbols.values()
                if "::SYNTHESIZED::" not in symbol["identifier"]["precise"]
                and "/Sources/Lokalized/" in symbol.get("location", {}).get("uri", "")]
    missing_authored = sorted("/".join(symbol["pathComponents"]) for symbol in authored if not documented(symbol))
    if missing_authored:
        raise ValueError(f"Authored public declarations need documentation: {', '.join(missing_authored)}")
    for symbol in symbols.values():
        prose = "\n".join(line.get("text", "") for line in symbol.get("docComment", {}).get("lines", []))
        if INTERNAL_NOTES.search(prose):
            raise ValueError(f"Internal maintenance notes in public documentation: {'/'.join(symbol['pathComponents'])}")
    return {"publicSymbols": len(symbols), "documentedSymbols": sum(documented(symbol) for symbol in symbols.values()),
            "topLevelDeclarations": len(top), "documentedTopLevelDeclarations": len(top),
            "authoredPublicSymbols": len(authored), "documentedAuthoredPublicSymbols": len(authored),
            "undocumentedMembers": sorted("/".join(symbol["pathComponents"]) for symbol in symbols.values() if not documented(symbol))}


def validate_release_source(release, dirty, tags):
    if release is None:
        return
    if dirty:
        raise ValueError("Release documentation requires a clean checkout of the release tag")
    if release not in tags and f"v{release}" not in tags:
        raise ValueError(f"HEAD has no {release} or v{release} release tag")


def symbol_graphs(directory):
    primary = directory / "Lokalized.symbols.json"
    if not primary.is_file():
        raise ValueError("The public Lokalized symbol graph was not emitted")
    # Do not publish the conformance executable, support module or test modules.
    return [primary] + sorted(directory.glob("Lokalized@*.symbols.json"))


def extract_symbol_graphs(output, env, root=ROOT):
    scratch = output / "build"
    directory = scratch / "symbolgraphs"
    # Emission happens during compilation. A fresh scratch directory ensures
    # incremental builds cannot skip it or leave symbols from older source.
    if scratch.exists():
        shutil.rmtree(scratch)
    directory.mkdir(parents=True)
    # SwiftPM 6.2's package-wide dump also tries to extract unbuilt synthesized
    # test modules. Emit graphs for the library target during its build instead.
    run(["xcrun", "swift", "build", "--disable-sandbox", "--scratch-path", str(scratch),
         "--cache-path", str(output / "package-cache"), "--config-path", str(output / "configuration"),
         "--security-path", str(output / "security"), "--manifest-cache", "local", "--target", "Lokalized",
         "-Xswiftc", "-emit-symbol-graph", "-Xswiftc", "-emit-symbol-graph-dir", "-Xswiftc", str(directory),
         "-Xswiftc", "-symbol-graph-minimum-access-level", "-Xswiftc", "public",
         "-Xswiftc", "-omit-extension-block-symbols"], env, cwd=root)
    return symbol_graphs(directory)


def public_declarations(graphs):
    """Compare signatures with the same compiler, without prose or source locations."""
    keys = ("kind", "pathComponents", "declarationFragments", "functionSignature", "accessLevel",
            "swiftGenerics", "swiftExtension", "availability", "isVirtual")
    return {symbol["identifier"]["precise"]: {key: symbol[key] for key in keys if key in symbol}
            for graph in graphs for symbol in graph["symbols"]}


def compare_documentation_inputs(current, baseline, tokenize):
    for name in ("Package.swift",):
        if (current / name).read_bytes() != (baseline / name).read_bytes():
            raise ValueError(f"Documentation corrections cannot change {name}")
    current_source, baseline_source = current / "Sources/Lokalized", baseline / "Sources/Lokalized"
    current_tokens, baseline_tokens = tokenize(current_source), tokenize(baseline_source)
    if current_tokens != baseline_tokens:
        changed = sorted(name for name in current_tokens.keys() | baseline_tokens.keys()
                         if current_tokens.get(name) != baseline_tokens.get(name))
        raise ValueError(f"Documentation corrections cannot change Swift code or its file inventory: {', '.join(changed)}")
    def resources(root):
        return {path.relative_to(root).as_posix(): path.read_bytes() for path in root.rglob("*")
                if path.is_file() and path.suffix != ".swift" and "Lokalized.docc" not in path.parts}
    if resources(current_source) != resources(baseline_source):
        raise ValueError("Documentation corrections cannot change library resources")


def validate_documentation_correction(release, reason, current_graphs, env):
    if not release or not reason.strip():
        raise ValueError("--correction-reason requires --release and a nonempty explanation")
    revisions = []
    for tag in (release, f"v{release}"):
        result = subprocess.run(["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"],
                                cwd=ROOT, text=True, capture_output=True)
        if result.returncode == 0:
            revisions.append(result.stdout.strip())
    if not revisions or len(set(revisions)) != 1:
        raise ValueError("Documentation correction requires an unambiguous matching release tag")
    revision = revisions[0]
    with tempfile.TemporaryDirectory(prefix="lokalized-doc-correction-") as temporary:
        scratch = Path(temporary)
        archive = scratch / "release.tar"
        archive.write_bytes(subprocess.check_output(["git", "archive", revision], cwd=ROOT))
        baseline = scratch / "release"
        baseline.mkdir()
        subprocess.run(["tar", "-xf", str(archive), "-C", str(baseline)], check=True)
        compiler = Path(run(["xcrun", "--find", "swiftc"]))
        host = compiler.parents[1] / "lib/swift/host"
        sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
        checker = scratch / "source-tokens"
        run([str(compiler), "-sdk", sdk, "-module-cache-path", str(scratch / "module-cache"),
             "-I", str(host), "-L", str(host), "-Xlinker", "-rpath", "-Xlinker", str(host),
             str(ROOT / "Tools/documentation_source_tokens.swift"), "-o", str(checker)], env)
        tokenize = lambda source: json.loads(run([str(checker), str(source)], env))
        compare_documentation_inputs(ROOT, baseline, tokenize)
        baseline_graphs = extract_symbol_graphs(scratch / "baseline-build", env, root=baseline)
        if public_declarations(current_graphs) != public_declarations([json.loads(path.read_text()) for path in baseline_graphs]):
            raise ValueError("Documentation corrections cannot change public Swift declarations")
    return {"releaseSourceRef": revision, "correctionReason": reason,
            "runtimeAndDeclarations": "unchanged"}


def input_fingerprint():
    paths = [ROOT / "Package.swift", Path(__file__).resolve(), ROOT / "Tools/documentation_source_tokens.swift"]
    paths += list((ROOT / "Sources/Lokalized").rglob("*.swift"))
    paths += list((ROOT / "Sources/Lokalized/Lokalized.docc").rglob("*.md"))
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(ROOT).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def write_landing(site):
    builds = sorted((json.loads(path.read_text()) for path in site.glob("*/reference-build.json")),
                    key=lambda build: build["edition"], reverse=True)
    items = "\n".join(f'<li><a href="{html.escape(build["edition"])}/{html.escape(build["entry"])}">'
                      f'{html.escape(build["label"])}</a>'
                      f'{" — unreleased source; APIs may change" if build["edition"] == "development" else ""}</li>' for build in builds)
    (site / "index.html").write_text(f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lokalized Swift API reference</title><style>body{{font:18px/1.6 system-ui,sans-serif;max-width:50rem;margin:4rem auto;padding:0 1.5rem;color:#172033}}a{{color:#0758ba}}li{{margin:.7rem 0}}</style></head>
<body><h1>Lokalized Swift API reference</h1><p>Types, methods, options, and callbacks for iOS and macOS applications.</p><ul>{items}</ul>
<p><a href="https://www.lokalized.com/?platform=swift">Guides and examples</a> · <a href="https://github.com/lokalized/lokalized-swift">Source repository</a></p></body></html>
''')


def build_documentation(output, release=None, correction_reason=None):
    edition = edition_for(release)
    source_ref = run(["git", "rev-parse", "HEAD"])
    dirty = bool(run(["git", "status", "--porcelain"]))
    if correction_reason is not None and (not release or not correction_reason.strip()):
        raise ValueError("--correction-reason requires --release and a nonempty explanation")
    if release and correction_reason is None:
        tags = run(["git", "tag", "--points-at", "HEAD"]).splitlines()
        validate_release_source(release, dirty, tags)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    fingerprint = input_fingerprint()
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(output / "clang-cache"),
               SWIFTPM_MODULECACHE_OVERRIDE=str(output / "swift-cache"))
    print("Extract public symbol graphs with the selected Swift compiler", flush=True)
    graphs = extract_symbol_graphs(output, env)
    loaded_graphs = [json.loads(path.read_text()) for path in graphs]
    coverage = coverage_for(loaded_graphs)
    correction = validate_documentation_correction(release, correction_reason, loaded_graphs, env) if correction_reason is not None else None
    selected_graphs = output / "symbolgraphs"
    shutil.rmtree(selected_graphs, ignore_errors=True)
    selected_graphs.mkdir()
    for path in graphs:
        shutil.copy2(path, selected_graphs / path.name)
    catalog = output / "Lokalized.docc"
    shutil.rmtree(catalog, ignore_errors=True)
    shutil.copytree(ROOT / "Sources/Lokalized/Lokalized.docc", catalog)
    label = f"Version {release}" if release else "Development"
    note = f"## Reference edition\n\n{label}."
    note += "\n\n" if release else " This reference describes unreleased source; APIs may change.\n\n"
    root_page = catalog / "Lokalized.md"
    root_page.write_text(root_page.read_text().replace("## Topics", note + "## Topics", 1))
    site = output / "site"
    site.mkdir(parents=True, exist_ok=True)
    destination = site / edition
    shutil.rmtree(destination, ignore_errors=True)
    command = ["xcrun", "docc", "convert", str(catalog), "--additional-symbol-graph-dir", str(selected_graphs),
               "--output-path", str(destination), "--fallback-display-name", "Lokalized",
               "--fallback-bundle-identifier", "com.lokalized.swift", "--fallback-default-module-kind", "Library",
               "--default-code-listing-language", "swift", "--hosting-base-path", edition,
               "--transform-for-static-hosting", "--warnings-as-errors"]
    if not dirty:
        command += ["--checkout-path", str(ROOT), "--source-service", "github", "--source-service-base-url",
                    f"https://github.com/lokalized/lokalized-swift/blob/{source_ref}"]
    print("Compile DocC and resolve all symbol links", flush=True)
    run(command, env)
    entry = "documentation/lokalized/index.html"
    if not (destination / entry).is_file():
        raise ValueError("DocC produced no statically hosted module page")
    if fingerprint != input_fingerprint():
        raise ValueError("Documentation inputs changed during the build")
    (destination / "coverage.json").write_text(json.dumps(coverage, indent=2) + "\n")
    report = {"status": "passed", "generator": "DocC from the selected Xcode", "compiler": run(["xcrun", "swift", "--version"], env),
              "edition": edition, "label": label, "sourceRef": source_ref, "dirty": dirty, "sourceSha256": fingerprint,
              "entry": "documentation/lokalized/", **{key: value for key, value in coverage.items() if key != "undocumentedMembers"},
              "output": str(destination)}
    if correction:
        report["documentationCorrection"] = correction
    (destination / "reference-build.json").write_text(json.dumps(report, indent=2) + "\n")
    write_landing(site)
    print(json.dumps(report, indent=2))
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", help="Build a versioned reference from a clean matching release tag")
    parser.add_argument("--output", type=Path, default=ROOT / ".build/api-documentation")
    parser.add_argument("--correction-reason", help="Correct release prose after verifying unchanged code, resources, and public declarations")
    args = parser.parse_args()
    build_documentation(args.output, args.release, args.correction_reason)
