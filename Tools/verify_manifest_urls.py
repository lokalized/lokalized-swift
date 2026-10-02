#!/usr/bin/env python3
"""Development-only original manifest URL projection qualification.

--check needs Python stdlib and swiftc only; it compiles only the actual URL
resolver and compares it with the pinned Node URL archive. --refresh-goldens
explicitly requires Node, replaces the archive, and prints its SHA-256 for review.
No JavaScript engine, downloads, package dependency, or runtime archive is added
by this probe. Capability scopes come from authored inputs, never expected URLs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GOLDENS = ROOT / "Reference/manifest-url-goldens.json"
GOLDENS_SHA256 = "5aeef3e07d1a1f0464baf4f0748d6902cebe4a61964cb1398419d1eb89ddd6fd"
SWIFT = r'''import Foundation
@main enum Probe {
 static func main() throws {
  while let line = readLine() {
   let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
   var result: [String: String] = [:]
   if let feature = ManifestURL.unqualifiedFeature(reference: row["input"]!, relativeTo: row["base"]) {
    result["capability"] = feature.rawValue
   } else {
    do { result["url"] = try ManifestURL.resolve(row["input"]!, relativeTo: row["base"]) }
    catch let error as ManifestURL.Failure {
     guard error.kind == .invalidURL else { throw error }; result["error"] = "invalid"
    }
   }
   print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
  }
 }
}'''
NODE = r'''const fs=require('node:fs');
const rows=JSON.parse(fs.readFileSync(0,'utf8'));
process.stdout.write(JSON.stringify({version:process.version,results:rows.map(row=>{
try{return{url:new URL(row.input,row.base).href}}catch{return{error:'invalid'}}
})}));'''


def matrix():
    schemes = ["http:", "https:", "file:", "ftp:", "ws:", "wss:"]
    authorities = ["example.com", "EXAMPLE.Com:80", "user:pass@example.com:443", "u@p@EXAMPLE.com", "127.1", "2130706433", "0x7f.1", "0177.1", "09", "1.2.3.256", "256.1", "example.123", "example.0X", "[::1]", "[0:0:0:1:0:0:0:1]", "[::ffff:192.0.2.1]", "[::ffff:0192.0.2.1]", "[1::2::3]", "localhost", "EXAMPLE..COM", ".example.com", "example.com.", "%65xample.com", "%C3%28", "xn--caf-dma.fr", "é.com", "%00.com", "example%25.com", "user:@example.com"]
    paths = ["", "/", "/a/b", "/a/../b", "/a/%2e/%2E%2e/b", "/a//b/..", "/a/.", "/../", "/a%2fb", "/café?q=你好#é", "/a\\b", "/a;:%20@[]^|{}?q='\"<>`# x", "/a\u0600/b?x\u0600#y", "/a/\u0301?\u0301#\u0301", "/a%2E./b", "/C:/a", "/C|/a", "//a/b", "/??x##y"]
    rows = []
    for scheme in schemes:
        for authority in authorities:
            for path in paths:
                row = {"input": scheme + "//" + authority + path}
                capability = {"é.com": "unicodeDomain", "xn--caf-dma.fr": "punycodeDomain"}.get(authority)
                rows.append((row, capability))
    bases = ["https://EXAMPLE.com:443/a/b?q=x#f", "http://u:p@127.1:80/x/y/", "file:///C:/a/b", "file://server/a/b", "data:opaque?query#fragment"]
    refs = ["", "?", "#", "#\u0301", "?\u0301", "/\u0301", "../x", "../../../../x", "a", "./a", "../.", "..", "//host/x", "\\\\host\\x", "\\x", "https:foo", "http:foo", "file:foo", "file:///C|/x", "C:/x", "C|/x", "/C:/x", "/D|/x", "///x", "?q=é#f", "x?y#z", "\n\t x \r", " / x ", "# x", "a\u0600/b", "a\u0600?b\u0600#c", "//[::1]:443/a"]
    for base in bases:
        for reference in refs:
            rows.append(({"input": reference, "base": base}, None))
    for reference in ["data:hello world?x=y#z", "mailto:a@b", "http:example.com", " https://EXAMPLE.com:443 \n", "file:///C:", "file:///C|", "file:/C|/a", "file://C:/a", "file://C|/a", "http://0x100000000000000000000", "https://host:000000000000000000000000000000000000000443", "https://a?\u0301#\u0301", "https://a\u0600/b"]:
        rows.append(({"input": reference}, "unicodeDomain" if reference == "https://a\u0600/b" else None))
    return rows


def digest(data):
    return hashlib.sha256(data).hexdigest()


def report_check(report_path, reference_directory):
    """Validate an actual native CLI report's complete ID/capability partition.

    Returns the parsed report. Raises ValueError for any inventory, hash,
    count, failure or unknown-field mismatch; needs Python stdlib only.
    """
    archive_bytes = (Path(reference_directory) / "manifest-url-goldens.json").read_bytes()
    if digest(archive_bytes) != GOLDENS_SHA256:
        raise ValueError("Manifest URL archive digest differs")
    archive = json.loads(archive_bytes)
    def exact_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("Duplicate manifest URL report member")
            result[key] = value
        return result
    report = json.loads(Path(report_path).read_text(), object_pairs_hook=exact_object)
    required = {"status", "total", "qualified", "pendingNativeCapability", "failed", "runtimePassed", "qualifiedIDs",
                "qualifiedIDSetSHA256", "pendingNativeCapabilities", "archiveSHA256", "pendingIDSetSHA256", "failures"}
    if not isinstance(report, dict) or not required.issubset(report) or set(report) - required - {"sourceSHA256"}:
        raise ValueError("Manifest URL report field inventory differs")
    if any(type(report[field]) is not int for field in ["total", "qualified", "pendingNativeCapability", "failed", "runtimePassed"]):
        raise ValueError("Manifest URL report counters must be integers")
    qualified = [row["id"] for row in archive["rows"] if row["unqualifiedFeature"] is None]
    pending = [{"id": row["id"], "feature": row["unqualifiedFeature"]} for row in archive["rows"] if row["unqualifiedFeature"]]
    if len(set(qualified + [row["id"] for row in pending])) != len(archive["rows"]):
        raise ValueError("Manifest URL archive partition is not disjoint")
    expected = {"status": "passed", "total": 3479, "qualified": 3250, "pendingNativeCapability": 229, "failed": 0,
                "runtimePassed": 3250, "qualifiedIDs": qualified, "pendingNativeCapabilities": pending,
                "archiveSHA256": GOLDENS_SHA256, "failures": [],
                "qualifiedIDSetSHA256": digest("".join(x + "\n" for x in qualified).encode()),
                "pendingIDSetSHA256": digest("".join(x["id"] + "\n" for x in pending).encode())}
    for field, value in expected.items():
        if report[field] != value:
            raise ValueError("Manifest URL report differs at " + field)
    if "sourceSHA256" in report and report["sourceSHA256"] != digest((ROOT / "Sources/Lokalized/Loading/ManifestURL.swift").read_bytes()):
        raise ValueError("Manifest URL report source digest differs")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--refresh-goldens", action="store_true")
    parser.add_argument("--node", default=shutil.which("node"))
    parser.add_argument("--swiftc", default=shutil.which("swiftc"))
    args = parser.parse_args()
    rows = matrix()
    recipe_bytes = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode()
    if args.refresh_goldens:
        if not args.node:
            parser.error("--refresh-goldens requires an explicit available Node executable")
        run = subprocess.run([args.node, "-e", NODE], input=json.dumps([r for r, _ in rows]), text=True, capture_output=True, check=True)
        oracle = json.loads(run.stdout)
        archive = {"formatVersion": 1, "oracle": "Node built-in WHATWG URL", "nodeVersion": oracle["version"],
                   "nodeBinarySha256": digest(Path(args.node).resolve().read_bytes()), "recipeVersion": 1,
                   "recipeSha256": digest(recipe_bytes), "scope": "Special URLs with ASCII non-punycode hostnames; other schemes diagnostic-only",
                   "rows": [{"id": f"manifest-url-{i+1:04d}", "input": row, "unqualifiedFeature": capability,
                             "expected": expected} for i, ((row, capability), expected) in enumerate(zip(rows, oracle["results"]))]}
        GOLDENS.write_text(json.dumps(archive, ensure_ascii=False, indent=2) + "\n")
        print("Refreshed", GOLDENS, "SHA-256", digest(GOLDENS.read_bytes()))
        return
    data = GOLDENS.read_bytes()
    if digest(data) != GOLDENS_SHA256:
        raise SystemExit("Pinned manifest URL archive SHA-256 differs")
    archive = json.loads(data)
    if archive["formatVersion"] != 1 or archive["recipeVersion"] != 1 or archive["oracle"] != "Node built-in WHATWG URL" or archive["nodeVersion"] != "v26.5.0" or archive["nodeBinarySha256"] != "87026f4b570ee090c0e0b48e8c6586ede31952695aac2b0021cc67e44987d511":
        raise SystemExit("Pinned oracle/version provenance differs")
    ids = [r["id"] for r in archive["rows"]]
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        raise SystemExit("Pinned IDs are duplicated or unsorted")
    if archive["recipeSha256"] != digest(recipe_bytes) or len(archive["rows"]) != len(rows):
        raise SystemExit("Pinned input recipe differs; explicit oracle refresh required")
    for archived, (row, capability) in zip(archive["rows"], rows):
        if archived["input"] != row or archived["unqualifiedFeature"] != capability:
            raise SystemExit("Pinned input/capability record differs")
    if not args.swiftc:
        parser.error("--check requires swiftc")
    with tempfile.TemporaryDirectory(prefix="lokalized-manifest-urls-", dir="/private/tmp") as scratch:
        scratch = Path(scratch)
        (scratch / "Probe.swift").write_text(SWIFT)
        subprocess.run([args.swiftc, "-swift-version", "6", "-package-name", "lokalized_swift", "-module-name", "URLProbe",
                        "-parse-as-library", "-module-cache-path", str(scratch / "cache"),
                        str(ROOT / "Sources/Lokalized/Loading/ManifestURL.swift"), str(scratch / "Probe.swift"),
                        "-o", str(scratch / "probe")], check=True)
        run = subprocess.run([str(scratch / "probe")], input="\n".join(json.dumps(row) for row, _ in rows) + "\n", text=True, capture_output=True, check=True)
    actual = [json.loads(line) for line in run.stdout.splitlines()]
    if len(actual) != len(rows):
        raise SystemExit("Native URL probe observation count differs")
    failures, pending, qualified = [], [], []
    for archived, observed in zip(archive["rows"], actual):
        feature = archived["unqualifiedFeature"]
        expected = {"capability": feature} if feature else archived["expected"]
        if observed != expected:
            failures.append({"id": archived["id"], "input": archived["input"], "expected": expected, "actual": observed})
        if feature:
            pending.append({"id": archived["id"], "feature": feature})
        else:
            qualified.append(archived["id"])
    report = {"status": "failed" if failures else "passed", "total": len(actual), "qualified": len(actual) - len(pending),
              "pendingNativeCapability": len(pending), "failed": len(failures),
              "runtimePassed": sum(a == r["expected"] for r, a in zip(archive["rows"], actual) if r["unqualifiedFeature"] is None),
              "failures": [row["id"] for row in failures], "archiveSHA256": digest(data),
              "sourceSHA256": digest((ROOT / "Sources/Lokalized/Loading/ManifestURL.swift").read_bytes()),
              "qualifiedIDs": qualified, "qualifiedIDSetSHA256": digest("".join(x + "\n" for x in qualified).encode()),
              "pendingNativeCapabilities": pending,
              "pendingIDSetSHA256": digest("".join(x["id"] + "\n" for x in pending).encode())}
    print(json.dumps(report, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
