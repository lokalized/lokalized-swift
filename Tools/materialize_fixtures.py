#!/usr/bin/env python3
"""Archive declaration-preserving fixture bytes from the pinned spec commit.

--refresh requires an explicit source workspace and verifies materialization
against local Node JSON.stringify. --check uses Python stdlib, archived sources,
and the frozen corpus only. No expected observations are generated or executed.
"""
import argparse
import base64
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC_COMMIT = "2d9547700d88ad8b7bc73e4d2c0fe18bdffb68a4"
CORPUS_SHA = "1eb74caf8524c0a3b33dca99addb268c86b64eb8321fac03257474ddaa3c9753"
SOURCE_INDEX_SHA = "8a6ca78f18349bc436bcee0f04bc994cd0f406a194900fe7f24c1848adeba324"
RECIPE_SHA = "e4f0b207b32fb0c950943f09a0b8b695a98fd5cfef0728e72ac5919dea3479db"
MATERIALIZED_SHA = "8203dbeae22b862f7514c3fec2786a42782067f1f532b96aab9314b1d5aea146"
RECIPE_PATH = "tools/vector-oracle/build.mjs"
FIELDS = {"description", "fallbackLocale", "instanceLocale", "tiebreakers", "loadingOptions", "translationFailureHandler", "translationFallbackPolicy", "phoneticResolver", "localeSupplier", "localeMatchSupplier", "runtimeLimits", "bidiIsolation", "loadOnly", "refusesConstruction", "constructionOverrides", "files", "rawFiles", "rawFilesBase64", "pathShape", "entries"}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON member {key!r}")
        result[key] = value
    return result


def load(data, js_numbers=False):
    def bad_constant(value):
        raise ValueError(f"Non-JSON numeric constant {value}")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                      parse_int=float if js_numbers else int, parse_float=float,
                      parse_constant=bad_constant)


def encoded_json(value):
    return (json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def quote(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    # Well-formed JSON.stringify escapes lone UTF-16 surrogates. Valid escaped
    # pairs have already become a scalar in Python's JSON decoder.
    return "".join(f"\\u{ord(character):04x}" if 0xD800 <= ord(character) <= 0xDFFF else character for character in text)


def number(value):
    if not math.isfinite(value):
        return "null"  # JSON.stringify's nonfinite-number rule.
    if value == 0:
        return "0"
    negative = value < 0
    text = repr(abs(value))
    mantissa, separator, exponent = text.partition("e")
    position = (mantissa.index(".") if "." in mantissa else len(mantissa)) + (int(exponent) if separator else 0)
    digits = mantissa.replace(".", "")
    removed = len(digits) - len(digits.lstrip("0"))
    digits = digits.lstrip("0").rstrip("0")
    position -= removed
    if 0 < position <= 21:
        result = digits[:position] + ("0" * max(0, position - len(digits)))
        if position < len(digits):
            result += "." + digits[position:]
    elif -6 < position <= 0:
        result = "0." + "0" * (-position) + digits
    else:
        power = position - 1
        result = digits[0] + ("." + digits[1:] if len(digits) > 1 else "") + "e" + ("+" if power >= 0 else "") + str(power)
    return ("-" if negative else "") + result


def object_keys(value):
    numeric = []
    ordinary = []
    for key in value:
        if key.isascii() and key.isdigit() and str(int(key)) == key and int(key) < 4294967295:
            numeric.append(key)
        else:
            ordinary.append(key)
    return sorted(numeric, key=int) + ordinary


def stringify(value, depth=0):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return number(float(value))
    if isinstance(value, str):
        return quote(value)
    indentation = "  " * depth
    child_indent = indentation + "  "
    if isinstance(value, list):
        if not value:
            return "[]"
        rows = [child_indent + stringify(item, depth + 1) for item in value]
        return "[\n" + ",\n".join(rows) + "\n" + indentation + "]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = [child_indent + quote(key) + ": " + stringify(value[key], depth + 1) for key in object_keys(value)]
        return "{\n" + ",\n".join(rows) + "\n" + indentation + "}"
    raise ValueError("Unsupported authored JSON value")


def node_utf8(text):
    # Buffer.from(text, 'utf8') replaces lone surrogate code units with U+FFFD.
    return "".join("\ufffd" if 0xD800 <= ord(character) <= 0xDFFF else character for character in text).encode("utf-8")


def materialize(fixture):
    files = {}
    for name, value in fixture.get("files", {}).items():
        files[name] = (stringify(value) + "\n").encode("utf-8")
    for name, text in fixture.get("rawFiles", {}).items():
        if not isinstance(text, str):
            raise ValueError("rawFiles must carry text")
        files[name] = node_utf8(text)
    for name, text in fixture.get("rawFilesBase64", {}).items():
        files[name] = base64.b64decode(text, validate=True)
    # Child content is an ordinary file, while shape-only entries remain in the
    # archived corpus/authored input. No FIFO, symlink or directory is created.
    for name, entry in fixture.get("entries", {}).items():
        if entry["kind"] == "directory":
            for child, value in entry.get("files", {}).items():
                files[name + "/" + child] = (stringify(value) + "\n").encode("utf-8")
        elif entry["kind"] != "fifo":
            raise ValueError("Unknown fixture entry shape")
    return {name: {"bytesBase64": base64.b64encode(data).decode("ascii"), "byteCount": len(data), "sha256": sha(data)} for name, data in files.items()}


def normalized(fixture):
    defaults = {name: None for name in FIELDS}
    defaults.update({"files": {}, "rawFiles": {}, "rawFilesBase64": {}, "entries": {}, "loadOnly": False, "refusesConstruction": False, "pathShape": "directory", "instanceLocale": fixture["fallbackLocale"]})
    return {name: fixture.get(name) if fixture.get(name) is not None else defaults[name] for name in FIELDS}


def semantic(value):
    if value is None:
        return ("null",)
    if isinstance(value, bool):
        return ("bool", value)
    if isinstance(value, (int, float)):
        return ("number", float(value)) if math.isfinite(float(value)) else ("null",)
    if isinstance(value, str):
        return ("string", value.encode("utf-16-le", errors="surrogatepass"))
    if isinstance(value, list):
        return ("array", tuple(semantic(item) for item in value))
    if isinstance(value, dict):
        return ("object", tuple(sorted((key.encode("utf-16-le", errors="surrogatepass"), semantic(item)) for key, item in value.items())))
    raise ValueError("Unsupported semantic JSON value")


def decode_sources(source_rows):
    fixtures = {}
    index = []
    for row in source_rows:
        if set(row) != {"path", "byteCount", "sha256", "bytesBase64"}:
            raise ValueError("Unknown/missing authored source row fields")
        data = base64.b64decode(row["bytesBase64"], validate=True)
        if len(data) != row["byteCount"] or sha(data) != row["sha256"]:
            raise ValueError("Authored source byte/digest mismatch")
        path = row["path"]
        if not path.startswith("fixtures/") or not path.endswith(".json") or "/" in path[len("fixtures/"):]:
            raise ValueError("Invalid authored source path")
        fixture = load(data, js_numbers=True)
        identifier = path[len("fixtures/"):-len(".json")]
        if fixture.get("id") != identifier or identifier in fixtures or set(fixture) - (FIELDS | {"id"}):
            raise ValueError("Invalid fixture ID/shape or duplicate authored source")
        fixtures[identifier] = fixture
        index.append({key: row[key] for key in ["path", "byteCount", "sha256"]})
    if len(fixtures) != 586:
        raise ValueError("Authored fixture inventory changed")
    if sha(encoded_json(index)) != SOURCE_INDEX_SHA:
        raise ValueError("Authored source index pin mismatch")
    return fixtures, sha(encoded_json(index))


def artifact_for(rows, recipe):
    fixtures, source_pin = decode_sources(rows)
    if sha(recipe) != RECIPE_SHA:
        raise ValueError("Pinned oracle materialization recipe changed")
    return {"formatVersion": 1, "corpusSHA256": CORPUS_SHA,
        "source": {"repository": "lokalized-spec", "commit": SPEC_COMMIT, "authoredSourcesIndexSHA256": source_pin,
                   "authoredSources": rows, "recipe": {"path": RECIPE_PATH, "byteCount": len(recipe), "sha256": sha(recipe), "bytesBase64": base64.b64encode(recipe).decode("ascii")},
                   "materialization": "structured files: JSON.stringify(contents,null,2)+'\\n'; rawFiles UTF-8 overrides, then rawFilesBase64 byte overrides; directory-entry child files use the same structured recipe",
                   "scope": "ordinary declared file bytes only; absent/regular-file root path shapes and FIFO/directory entries remain corpus transport metadata; no filesystem entries are created"},
        "fixtures": {identifier: {"files": materialize(fixture)} for identifier, fixture in fixtures.items()}}


def check(reference):
    path = reference / "materialized-fixtures.json"
    raw = path.read_bytes()
    if sha(raw) != MATERIALIZED_SHA:
        raise ValueError("Materialized fixture archive whole-file pin mismatch")
    artifact = load(raw)
    rows = artifact["source"]["authoredSources"]
    recipe_record = artifact["source"]["recipe"]
    recipe = base64.b64decode(recipe_record["bytesBase64"], validate=True)
    expected = artifact_for(rows, recipe)
    if artifact != expected or raw != encoded_json(expected):
        raise ValueError("Materialized archive metadata/bytes/recipe differs from deterministic inputs")
    corpus_bytes = (reference / "behavioral-vectors.json").read_bytes()
    if sha(corpus_bytes) != CORPUS_SHA:
        raise ValueError("Frozen corpus pin mismatch")
    corpus = load(corpus_bytes, js_numbers=True)
    authored, _ = decode_sources(rows)
    if set(corpus["fixtures"]) != set(authored):
        raise ValueError("Missing/unknown corpus fixture IDs")
    for identifier, fixture in authored.items():
        if semantic(normalized(fixture)) != semantic(corpus["fixtures"][identifier]):
            raise ValueError(f"{identifier}: authored input differs from archived corpus semantic tree")
        # Every structured file (unless raw-overridden) is independently decoded
        # and compared to the corpus's structured file tree. Order is purposely
        # ignored here; exact string/key UTF-16 identities and numbers are retained.
        for name, value in fixture.get("files", {}).items():
            if name in fixture.get("rawFiles", {}) or name in fixture.get("rawFilesBase64", {}):
                continue
            materialized = artifact["fixtures"][identifier]["files"][name]
            data = base64.b64decode(materialized["bytesBase64"], validate=True)
            if semantic(load(data, js_numbers=True)) != semantic(corpus["fixtures"][identifier]["files"][name]):
                raise ValueError(f"{identifier}/{name}: materialized semantic tree differs")
    return artifact, sha(raw)


NODE_VERIFY = r'''import fs from 'node:fs';
const rows=JSON.parse(fs.readFileSync(0,'utf8'));const result={};
for(const row of rows){const f=JSON.parse(Buffer.from(row.bytesBase64,'base64').toString('utf8'));const files={};
for(const [tag,value] of Object.entries(f.files??{}))files[tag]=Buffer.from(JSON.stringify(value,null,2)+'\n').toString('base64');
for(const [tag,text] of Object.entries(f.rawFiles??{}))files[tag]=Buffer.from(text,'utf8').toString('base64');
for(const [tag,text] of Object.entries(f.rawFilesBase64??{}))files[tag]=Buffer.from(text,'base64').toString('base64');
for(const [name,entry]of Object.entries(f.entries??{}))if(entry.kind==='directory')for(const[tag,value]of Object.entries(entry.files??{}))files[name+'/'+tag]=Buffer.from(JSON.stringify(value,null,2)+'\n').toString('base64');
result[f.id]=files;}process.stdout.write(JSON.stringify(result));'''


def git(repository, *args):
    return subprocess.check_output(["git", "-C", str(repository), *args], stderr=subprocess.PIPE)


def refresh(source_root, reference, node):
    repository = source_root / "lokalized-spec"
    names = git(repository, "ls-tree", "--name-only", SPEC_COMMIT + ":fixtures").decode().splitlines()
    rows = []
    for name in names:
        if not name.endswith(".json"):
            raise ValueError("Unknown file in pinned fixture directory")
        path = "fixtures/" + name
        data = git(repository, "show", SPEC_COMMIT + ":" + path)
        rows.append({"path": path, "byteCount": len(data), "sha256": sha(data), "bytesBase64": base64.b64encode(data).decode("ascii")})
    recipe = git(repository, "show", SPEC_COMMIT + ":" + RECIPE_PATH)
    artifact = artifact_for(rows, recipe)
    result = subprocess.run([node, "--input-type=module", "-e", NODE_VERIFY], input=json.dumps(rows), capture_output=True, text=True)
    if result.returncode:
        raise ValueError("Native JSON.stringify verification failed: " + result.stderr)
    actual = load(result.stdout.encode("utf-8"))
    wanted = {identifier: {name: file["bytesBase64"] for name, file in fixture["files"].items()} for identifier, fixture in artifact["fixtures"].items()}
    if actual != wanted:
        moved = [identifier for identifier in wanted if actual.get(identifier) != wanted[identifier]]
        raise ValueError("Python serializer disagrees with JSON.stringify for fixtures: " + ", ".join(moved))
    data = encoded_json(artifact)
    if sha(data) != MATERIALIZED_SHA:
        raise ValueError("Refresh would replace the pinned archive with different bytes")
    reference.mkdir(parents=True, exist_ok=True)
    (reference / "materialized-fixtures.json").write_bytes(data)
    return subprocess.check_output([node, "--version"], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--refresh", action="store_true")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--reference", type=Path, default=ROOT / "Reference")
    parser.add_argument("--node", default="node", help="local Node executable for explicit refresh verification only")
    args = parser.parse_args()
    if args.refresh and args.source_root is None:
        parser.error("--refresh requires --source-root; no implicit sibling repository is used")
    if args.check and args.source_root is not None:
        parser.error("--check uses only the archived local inputs")
    node_version = refresh(args.source_root.resolve(), args.reference, args.node) if args.refresh else None
    artifact, digest = check(args.reference)
    print(json.dumps({"status": "verified", "fixtures": len(artifact["fixtures"]), "files": sum(len(f["files"]) for f in artifact["fixtures"].values()), "bytes": (args.reference / "materialized-fixtures.json").stat().st_size, "sha256": digest, "authoredSourcesIndexSHA256": artifact["source"]["authoredSourcesIndexSHA256"], "recipeSHA256": artifact["source"]["recipe"]["sha256"], "refreshNodeVersion": node_version}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print(f"Materialized fixture archive FAILED: {error}", file=sys.stderr)
        sys.exit(1)
