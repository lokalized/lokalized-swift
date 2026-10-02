#!/usr/bin/env python3
"""Frozen public API census. Check needs only Python; refresh needs Java/Node, never npm.

Java is compiled from clean source in an isolated temporary directory, then inspected
with javap -public -constants. Java package-private helpers are not public API.
JS runtime names come from actual package entry modules; type names resolve only
their declaration exports, rather than inventorying every internal .d.ts file.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(args, cwd=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout.strip()


def snapshot(repo, files):
    if run(["git", "status", "--porcelain"], repo):
        raise RuntimeError(f"Refusing a dirty reference checkout: {repo}")
    records = [{"path": p.relative_to(repo).as_posix(), "sha256": sha(p.read_bytes())}
               for p in sorted(files)]
    return {"commit": run(["git", "rev-parse", "HEAD"], repo),
            "files": records, "sourceSha256": sha(canonical(records))}


def strip_comments(text):
    # Preserve string literals and newlines; offsets remain usable as source locations.
    output, i = [], 0
    while i < len(text):
        if text[i] in "\"'`":
            quote, start = text[i], i
            i += 1
            while i < len(text):
                if text[i] == "\\":
                    i += 2
                elif text[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
            output.append(text[start:i])
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise RuntimeError("Unterminated declaration comment")
            end += 2
            output.append("".join("\n" if c == "\n" else " " for c in text[i:end]))
            i = end
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = len(text) if end < 0 else end
            output.append(" " * (end - i))
            i = end
        else:
            output.append(text[i])
            i += 1
    return "".join(output)


def declaration_end(text, start, kind):
    depth, quote, escaped = 0, None, False
    saw_brace = False
    for i in range(start, len(text)):
        c = text[i]
        if quote:
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == quote:
                quote = None
            continue
        if c in "\"'`":
            quote = c
        elif c in "{([":
            depth += 1
            saw_brace = saw_brace or c == "{"
        elif c in "})]":
            depth -= 1
            if kind in ("class", "interface", "enum") and saw_brace and c == "}" and depth == 0:
                return i + 1
        elif c == ";" and depth == 0:
            return i + 1
    raise RuntimeError(f"Cannot identify end of {kind} declaration")


def declaration_path(file, module):
    target = (file.parent / module).resolve()
    if target.suffix == ".js":
        target = target.with_suffix(".d.ts")
    if not target.is_file():
        raise RuntimeError(f"Missing re-export declaration: {target}")
    return target


def named_list(body):
    for item in body.split(","):
        parts = item.strip().split()
        if not parts:
            continue
        if parts[0] == "type":
            parts = parts[1:]
        yield parts[0], parts[-1]


def declaration_exports(file, repo, cache):
    if file in cache:
        return cache[file]
    text = strip_comments(file.read_text())
    exports = {}
    cache[file] = exports
    # Direct declarations can contain rich callable/result/member shapes.
    pattern = r"^export\s+(?:declare\s+)?(type|class|interface|enum|function|const|let|var)\s+([A-Za-z_$][\w$]*)"
    for match in re.finditer(pattern, text, re.M):
        kind, name = match.groups()
        end = declaration_end(text, match.start(), kind)
        exports[name] = {"name": name, "kind": kind,
                         "declarationSource": file.relative_to(repo).as_posix(),
                         "line": text.count("\n", 0, match.start()) + 1,
                         "declaration": re.sub(r"\s+", " ", text[match.start():end]).strip()}
    imported = {}
    for match in re.finditer(r"^import\s*\{([^}]+)\}\s*from\s*[\"']([^\"']+)[\"']\s*;", text, re.M):
        origin = declaration_exports(declaration_path(file, match[2]), repo, cache)
        for original, local in named_list(match[1]):
            if original in origin:
                imported[local] = origin[original]
    for match in re.finditer(r"^export\s*(?:type\s+)?\{([^}]+)\}(?:\s*from\s*[\"']([^\"']+)[\"'])?\s*;", text, re.M):
        origin = declaration_exports(declaration_path(file, match[2]), repo, cache) if match[2] else {**imported, **exports}
        for original, exposed in named_list(match[1]):
            if original not in origin:
                raise RuntimeError(f"Unresolved public declaration {original} in {file}")
            exports[exposed] = {**origin[original], "name": exposed}
    for match in re.finditer(r"^export\s*\*\s*from\s*[\"']([^\"']+)[\"']\s*;", text, re.M):
        exports.update(declaration_exports(declaration_path(file, match[1]), repo, cache))
    return exports


def javascript_inventory(repo, node):
    package = json.loads((repo / "package.json").read_text())
    entries = [(name, value) for name, value in package["exports"].items()
               if isinstance(value, dict) and "import" in value and "types" in value]
    paths = [str((repo / value["import"]).resolve()) for _, value in entries]
    program = """import { pathToFileURL } from 'node:url';
const result=[];
for (const path of process.argv.slice(1)) result.push(Object.keys(await import(pathToFileURL(path).href)).sort());
console.log(JSON.stringify(result));"""
    runtime = json.loads(run([node, "--input-type=module", "-e", program, *paths], repo))
    cache, result = {}, []
    for (name, value), symbols in zip(entries, runtime):
        exported = declaration_exports((repo / value["types"]).resolve(), repo, cache)
        missing = set(symbols) - set(exported)
        if missing:
            raise RuntimeError(f"Runtime symbols without a public declaration at {name}: {sorted(missing)}")
        result.append({"entryPoint": name, "runtimeSource": value["import"],
                       "declarationEntry": value["types"], "runtimeSymbols": symbols,
                       "declarations": [exported[n] for n in sorted(exported)]})
    files = [repo / "package.json", *repo.glob("src/**/*.js"), *repo.glob("types/**/*.d.ts")]
    return {**snapshot(repo, files), "version": package["version"], "entries": result}


def java_inventory(repo, java_home, annotation_classpath):
    ns = {"m": "http://maven.apache.org/POM/4.0.0"}
    pom = ET.parse(repo / "pom.xml").getroot()
    sources = sorted(repo.glob("src/main/java/**/*.java"))
    public_tops = set()
    for source in sources:
        text = strip_comments(source.read_text())
        if re.search(r"^public\s+(?:(?:final|abstract|sealed|non-sealed)\s+)*(?:class|interface|enum)\s+" + re.escape(source.stem) + r"\b", text, re.M):
            public_tops.add(source.stem)
    javac = str(Path(java_home) / "bin/javac") if java_home else shutil.which("javac")
    javap = str(Path(java_home) / "bin/javap") if java_home else shutil.which("javap")
    if not javac or not javap:
        raise RuntimeError("Refresh requires a JDK; pass --java-home")
    compiler = subprocess.run([javac, "-version"], capture_output=True, text=True)
    compiler_version = (compiler.stdout + compiler.stderr).strip()
    if compiler.returncode or not re.search(r"\bjavac 21[.\s]", compiler_version):
        raise RuntimeError(f"Refresh pins Java 21; pass --java-home (found {compiler_version})")
    deps = []
    if annotation_classpath:
        jars = [Path(p).resolve() for p in annotation_classpath.split(os.pathsep)]
    else:
        jars = []
        for dependency in pom.findall("m:dependencies/m:dependency", ns):
            if dependency.findtext("m:scope", namespaces=ns) != "provided":
                continue
            group = dependency.findtext("m:groupId", namespaces=ns)
            artifact = dependency.findtext("m:artifactId", namespaces=ns)
            version = dependency.findtext("m:version", namespaces=ns)
            jars.append(Path.home() / ".m2/repository" / group.replace(".", "/") / artifact / version / f"{artifact}-{version}.jar")
    for jar in jars:
        if not jar.is_file():
            raise RuntimeError(f"Missing compile-only annotation JAR: {jar}; pass --annotation-classpath")
        deps.append({"name": jar.name, "sha256": sha(jar.read_bytes()), "role": "compile-only annotation"})
    with tempfile.TemporaryDirectory(prefix="lokalized-api-") as temporary:
        run([javac, "--release", "9", "-encoding", "UTF-8", "-classpath", os.pathsep.join(map(str, jars)),
             "-d", temporary, *map(str, sources)], repo)
        names = sorted("com.lokalized." + p.stem for p in (Path(temporary) / "com/lokalized").glob("*.class")
                       if p.stem.split("$")[0] in public_tops)
        output = run([javap, "-public", "-constants", "-classpath", temporary, *names], repo)
    types = []
    for block in re.split(r'^Compiled from "[^\"]+"\s*\n', output, flags=re.M):
        lines = [line.strip() for line in block.strip().splitlines() if line.strip()]
        if not lines or not lines[0].startswith("public "):
            continue
        match = re.search(r"\b(?:class|interface|enum)\s+(com\.lokalized\.[\w$]+)", lines[0])
        if not match:
            raise RuntimeError(f"Cannot parse javap public declaration: {lines[0]}")
        types.append({"name": match[1], "declaration": lines[0].removesuffix(" {"),
                      "members": [line for line in lines[1:] if line != "}"]})
    if not types or not any(t["name"] == "com.lokalized.Strings$Builder" for t in types):
        raise RuntimeError("Empty or incomplete Java public API inventory")
    return {**snapshot(repo, [repo / "pom.xml", *sources]),
            "version": pom.findtext("m:version", namespaces=ns),
            "method": "fresh isolated javac --release 9; javap -public -constants; only externally public enclosing types",
            "compiler": compiler_version, "compileOnlyInputs": deps, "types": types}


def check_inventory(inventory, baseline=None):
    expected = inventory.get("inventorySha256")
    body = {k: v for k, v in inventory.items() if k != "inventorySha256"}
    if expected != sha(canonical(body)):
        raise RuntimeError("API inventory content digest mismatch")
    if inventory.get("formatVersion") != 1:
        raise RuntimeError("Unsupported API inventory format")
    if baseline:
        references = baseline["sourceRepositories"]
        for language, repository in (("java", "lokalized-java"), ("javascript", "lokalized-js")):
            for field in ("commit", "version"):
                if inventory[language][field] != references[repository][field]:
                    raise RuntimeError(f"{repository} API {field} differs from frozen reference baseline")
    java_names = {t["name"] for t in inventory["java"]["types"]}
    required = {"com.lokalized.Strings", "com.lokalized.Strings$Builder", "com.lokalized.PluralOperands",
                "com.lokalized.TranslationRuntimeLimits", "com.lokalized.TranslationFallbackObserver"}
    if not required <= java_names or "com.lokalized.DefaultStrings" in java_names:
        raise RuntimeError("Java inventory missing public capabilities or exposing internal DefaultStrings")
    js_entries = {entry["entryPoint"]: entry for entry in inventory["javascript"]["entries"]}
    if set(js_entries) != {".", "./core", "./parse", "./load", "./ssr", "./negotiate", "./node", "./data/ordinal", "./data/ranges"}:
        raise RuntimeError("JS exported entry-point set differs from baseline")
    for entry in js_entries.values():
        if not set(entry["runtimeSymbols"]) <= {d["name"] for d in entry["declarations"]}:
            raise RuntimeError("JS exported value lacks a declaration")
    return {"status": "verified", "inventorySha256": expected, "javaPublicTypes": len(java_names),
            "javascriptEntryPoints": len(js_entries),
            "javascriptExportOccurrences": sum(len(e["runtimeSymbols"]) for e in js_entries.values()),
            "coverage": "reference API census; not Swift implementation or behavioral parity"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="verify frozen inventory offline; no Java/Node/siblings")
    mode.add_argument("--refresh", action="store_true", help="regenerate from clean source references")
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    parser.add_argument("--source-root", type=Path, default=ROOT.parent)
    parser.add_argument("--java-home", default=os.environ.get("LOKALIZED_JAVA_HOME") or os.environ.get("JAVA_HOME"))
    parser.add_argument("--annotation-classpath")
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
    output = args.reference / "api-inventory.json"
    baseline = json.loads((args.reference / "baseline.json").read_text())
    if args.refresh:
        inventory = {"formatVersion": 1, "status": "reference-inventory",
                     "java": java_inventory(args.source_root / "lokalized-java", args.java_home, args.annotation_classpath),
                     "javascript": javascript_inventory(args.source_root / "lokalized-js", args.node)}
        inventory["inventorySha256"] = sha(canonical(inventory))
        check_inventory(inventory, baseline)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(check_inventory(json.loads(output.read_text()), baseline), sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"API inventory refused: {error}", file=sys.stderr)
        sys.exit(1)
