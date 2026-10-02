#!/usr/bin/env python3
"""Qualify actual Swift locale behavior against the pinned JDK and Java core.

Development only; --check requires Python stdlib and swiftc, with no JDK or
sibling checkout. --oracle and --refresh-goldens require the explicitly pinned
JDK and a Java Git checkout containing the frozen corpus commit. Compiles clean Java
LocaleUtils/CldrLocaleData/GeneratedCldrLocaleData/Diagnostics sources from that
commit in a temporary directory. Annotation declarations are compile-only.
No live download, dependency resolution, Java runtime library, or host locale
negotiation is added to the Swift product.

The probe covers every alias, likely-subtag row, parent row, validity language,
and RTL script plus distinct JDK projection edge cases. Observations include
base fields, Locale identity clues, strict syntax versus rebuildability, raw
CLDR canonicalization, projected CLDR canonicalization, likely triples, fallback
chains, validity, and direction. Behavioral corpus expected values are never
consumed; --check uses only the separately authored, pinned locale archive.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GOLDENS = ROOT / "Reference/locale-goldens.json"
GOLDENS_SHA256 = "40e876c0c61bdc4f9e0bbe51d95eb1462b503acecb97ace785f79b33f8be8e7d"
JAVA_FILES = ("LocaleUtils.java", "CldrLocaleData.java", "GeneratedCldrLocaleData.java", "Diagnostics.java")
FIELDS = ("tag", "language", "script", "region", "variant", "extensions", "javaIdentifier", "rebuildable",
          "fullSyntax", "strict", "catalogTag", "canonicalRaw", "canonicalProjected", "likelyRaw", "likelyProjected",
          "likelyLanguageScript", "fallback", "knownRaw", "undeterminedRaw", "privateRaw", "rtl")

SWIFT = r'''import Foundation
import Dispatch
import Lokalized
func encoded(_ text: String) -> String { Data(text.utf8).base64EncodedString() }
if CommandLine.arguments.contains("--metadata-cost") {
    let start = DispatchTime.now().uptimeNanoseconds
    let counts = [LocaleTables.languageAliases.count, LocaleTables.regionAliases.count, LocaleTables.scriptAliases.count,
                  LocaleTables.variantAliases.count, LocaleTables.likelySubtags.count, LocaleTables.parentLocales.count,
                  LocaleTables.validLanguages.count, LocaleTables.validRegions.count, LocaleTables.validScripts.count,
                  LocaleTables.validVariants.count, LocaleTables.rightToLeftScripts.count]
    print(String(DispatchTime.now().uptimeNanoseconds - start) + "\t" + String(counts.reduce(0, +)))
    exit(0)
}
for line in String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n") {
    let text = String(line), locale = LocaleTag.forLanguageTag(text)
    let full = JDKLocaleTag.parse(text).wellFormed
    let rebuildable = (try? JDKLocaleTag.requireWellFormed(locale, description: "Locale")) != nil
    let fields = [locale.tag, locale.language, locale.script, locale.region, locale.variants.joined(separator: "_"),
                  locale.extensions.keys.sorted().map { $0 + "-" + locale.extensions[$0]! }.joined(separator: "-"),
                  locale.javaIdentifier, String(rebuildable), String(full), String((try? LocaleTag(text)) != nil),
                  String(JDKLocaleTag.isCatalogLanguageTag(text)), CldrLocaleData.canonicalLanguageTag(text),
                  locale.cldrCanonicalTag, CldrLocaleData.likelySubtagFor(text) ?? "<nil>", locale.likelySubtag ?? "<nil>",
                  CldrLocaleData.languageScriptForLikelySubtag(text) ?? "<nil>", locale.fallbackLocaleTags.joined(separator: "|"),
                  String(CldrLocaleData.isKnownLanguageTag(text)), String(CldrLocaleData.hasUndeterminedLanguage(text)),
                  String(CldrLocaleData.isPrivateUseLanguageTag(text)), String(locale.isRightToLeft)]
    print(fields.map(encoded).joined(separator: "\t"))
}
'''

JAVA = r'''package com.lokalized;
import java.io.*;
import java.util.*;
import java.nio.charset.StandardCharsets;
public final class LocaleOracle {
    static String encoded(String text) { return Base64.getEncoder().encodeToString(text.getBytes(StandardCharsets.UTF_8)); }
    static boolean syntax(String tag) { try { new Locale.Builder().setLanguageTag(tag); return true; } catch(Exception e) { return false; } }
    static boolean rebuildable(Locale locale) { try { LocaleUtils.requireWellFormed(locale, "Locale"); return true; } catch(Exception e) { return false; } }
    static boolean catalog(String tag) {
        if (!tag.matches("[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*")) return false;
        Locale locale; try { locale = new Locale.Builder().setLanguageTag(tag).build(); } catch(Exception e) { return false; }
        String lower = tag.toLowerCase(Locale.ROOT);
        if (lower.startsWith("x-")) return true;
        boolean explicit = lower.equals("und") || lower.startsWith("und-");
        return (!locale.getLanguage().isEmpty() || explicit) && CldrLocaleData.isKnownLanguageTag(tag);
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String text;
        while ((text = reader.readLine()) != null) {
            Locale locale = Locale.forLanguageTag(text);
            StringBuilder extensions = new StringBuilder();
            for (char key: locale.getExtensionKeys()) { if (extensions.length() > 0) extensions.append('-'); extensions.append(key).append('-').append(locale.getExtension(key)); }
            StringBuilder fallback = new StringBuilder();
            for (Locale candidate: CldrLocaleData.fallbackLocalesFor(locale)) { if (fallback.length() > 0) fallback.append('|'); fallback.append(candidate.toLanguageTag()); }
            String script = locale.getScript();
            if (script.isEmpty()) { Optional<String> likely = CldrLocaleData.likelySubtagFor(locale); if (likely.isPresent()) script = Locale.forLanguageTag(likely.get()).getScript(); }
            String[] fields = {locale.toLanguageTag(), locale.getLanguage(), locale.getScript(), locale.getCountry(), locale.getVariant(),
                               extensions.toString(), locale.toString(), ""+rebuildable(locale), ""+syntax(text), ""+(syntax(text)&&rebuildable(locale)),
                               ""+catalog(text), CldrLocaleData.canonicalLanguageTag(text), CldrLocaleData.canonicalLanguageTag(locale.toLanguageTag()),
                               CldrLocaleData.likelySubtagFor(text).orElse("<nil>"), CldrLocaleData.likelySubtagFor(locale).orElse("<nil>"),
                               CldrLocaleData.languageScriptForLikelySubtag(text).orElse("<nil>"), fallback.toString(),
                               ""+CldrLocaleData.isKnownLanguageTag(text), ""+CldrLocaleData.hasUndeterminedLanguage(text),
                               ""+CldrLocaleData.isPrivateUseLanguageTag(text), ""+CldrLocaleData.isRightToLeftScript(script)};
            StringJoiner output = new StringJoiner("\t"); for(String value: fields) output.add(encoded(value));
            System.out.println(output);
        }
    }
}
'''

EDGE_CASES = ["!", "en-", "en-1-abc", "en_US", " en-US ", "und", "UND", "Und", "uND", "und-x-a", "UND-x-a", "zh-und",
              "en-a", "en-a-abc-a-def", "en-u-ca-x1-ca-x2", "en-u-nu-latn-ca-gregory", "en-u-zzz-aaa-zzz-ca-gregory",
              "en-b-def-a-abc-b-ghi", "en-u-ca-gregory-u-nu-latn", "en-US-POSIX", "en-US-posix",
              "en-US-x-lvariant-POSIX", "en-US-x-custom-lvariant-POSIX", "en-x-lvariant", "x-lvariant-POSIX", "x-lvariant-A-B",
              "ja-JP-x-lvariant-JP", "ja-JP-x-lvariant-jp", "ja-JP-u-ca-japanese-x-lvariant-JP", "ja-JP-a-ab-x-lvariant-JP",
              "th-TH-x-lvariant-TH", "th-TH-x-lvariant-th", "no-NO-x-lvariant-NY", "no-NO-x-lvariant-ny",
              "zh-cmn-Hans-CN", "en-abc-def-ghi-Cyrl-US-1996", "abcdefgh-abc", "iw-IL", "ji", "in", "en-Zzzz-ZZ",
              "en-AU", "en-150", "es-AR", "sr-Latn-RS", "zh-Hant-TW", "no-NO", "nb-NO", "mo-MD", "aa-Saaho-ER",
              "sh-fonipa", "sh-Cyrl-BA", "hy-SU", "ru-SU", "zz-Arab", "und-Arab", "x-private", "x-Other",
              "de-1901", "en-ab12", "en-zzzzzzzz", "i-Klingon"]
GRANDFATHERED = ["art-lojban", "cel-gaulish", "en-GB-oed", "i-ami", "i-bnn", "i-default", "i-enochian", "i-hak", "i-klingon",
                 "i-lux", "i-mingo", "i-navajo", "i-pwn", "i-tao", "i-tay", "i-tsu", "no-bok", "no-nyn", "sgn-BE-FR",
                 "sgn-BE-NL", "sgn-CH-DE", "zh-guoyu", "zh-hakka", "zh-min", "zh-min-nan", "zh-xiang"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def probe_inputs(data):
    rows = list(EDGE_CASES) + GRANDFATHERED + [x.upper() for x in GRANDFATHERED]
    rows += [row["from"] for row in data["aliases"]["language"]]
    rows += [row["from"] + "-x-custom" for row in data["aliases"]["language"]]
    rows += [language + "-" + row["from"] for row in data["aliases"]["region"] for language in ("en", "hy", "ru")]
    rows += ["en-" + row["from"] for row in data["aliases"]["script"]]
    rows += ["el-" + row["from"] for row in data["aliases"]["variant"]]
    rows += [row["from"] for row in data["likelySubtags"]]
    rows += [row["from"] for row in data["parentLocales"]]
    rows += data["validity"]["languages"]
    rows += ["en-" + script for script in data["validity"]["scripts"]]
    rows += ["en-" + script for script in data["rightToLeftScripts"]]
    return list(dict.fromkeys(rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="Compare actual Swift with pinned dev-only observations; no JDK or sibling checkout")
    mode.add_argument("--oracle", action="store_true", help="Compare actual Swift with clean pinned Java/JDK observations")
    mode.add_argument("--refresh-goldens", action="store_true", help="Regenerate the dev-only archive only after actual Java/Swift agree")
    parser.add_argument("--java-home", type=Path)
    parser.add_argument("--java-repository", type=Path, default=ROOT.parent / "lokalized-java")
    parser.add_argument("--output-directory", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    output = (args.output_directory or Path(tempfile.mkdtemp(prefix="lokalized-locale-oracle-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report_path = (args.report or output / "report.json").resolve()
    report = dict(formatVersion=1, verified=False, startedAtUnix=time.time(), commands=[], outputDirectory=str(output),
                  host=platform.platform(), scope="complete locale metadata and deterministic JDK/CLDR projection", notVerified=["minimum compiler or OS runtimes"])

    def run(command, stdin=None):
        start = time.monotonic()
        result = subprocess.run(list(map(str, command)), input=stdin, text=True, capture_output=True)
        report["commands"].append(dict(argv=list(map(str, command)), returnCode=result.returncode, elapsedSeconds=time.monotonic()-start,
                                       stderr=result.stderr[:8192], stdoutSha256=hashlib.sha256(result.stdout.encode()).hexdigest()))
        if result.returncode:
            raise RuntimeError(f"Command failed: {command[0]}\n{result.stderr[:8192]}")
        return result.stdout

    try:
        baseline = json.loads((ROOT / "Reference/baseline.json").read_text())
        runtime = json.loads((ROOT / "Reference/reference-runtime-lock.json").read_text())
        ref = baseline["javaCorpusReference"]["commit"]
        data_path = ROOT / "Reference/cldr-locale-data.json"
        data = json.loads(data_path.read_text())
        authored = probe_inputs(data)
        cases = "\n".join(authored)+"\n"
        archive = None
        java_source_hashes = {}
        if args.check:
            if digest(GOLDENS) != GOLDENS_SHA256:
                raise RuntimeError("Locale golden archive digest differs")
            archive = json.loads(GOLDENS.read_bytes())
            if (archive["inputs"] != authored or archive["fields"] != list(FIELDS)
                or archive["javaCorpusCommit"] != ref
                or archive["jdkReleaseSha256"] != runtime["jdk"]["releaseFileSha256"]
                or archive["localeSourceSha256"] != digest(data_path)
                or archive["oracleSourceSha256"] != hashlib.sha256(JAVA.encode()).hexdigest()):
                raise RuntimeError("Locale golden inventory or provenance differs")
            java_source_hashes = archive["javaSourceHashes"]
            report["goldenArchiveSha256"] = digest(GOLDENS)
        else:
            if args.java_home is None:
                raise RuntimeError("Explicit --java-home is required for --oracle/--refresh-goldens")
            release = args.java_home.resolve() / "release"
            if digest(release) != runtime["jdk"]["releaseFileSha256"]:
                raise RuntimeError("JDK release identity differs from the pinned runtime")
            if run(["git", "-C", args.java_repository, "rev-parse", ref]).strip() != ref:
                raise RuntimeError("Java corpus commit is unavailable")
            java_root = output / "java"
            java_root.mkdir(exist_ok=True)
            java_source_hashes = {}
            for name in JAVA_FILES:
                path = "src/main/java/com/lokalized/" + name
                text = run(["git", "-C", args.java_repository, "show", ref + ":" + path])
                target = java_root / "com/lokalized" / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                java_source_hashes[path] = digest(target)
            for name in ("NonNull", "Nullable"):
                target = java_root / "org/jspecify/annotations" / (name + ".java")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("package org.jspecify.annotations; import java.lang.annotation.*; @Target({ElementType.TYPE_USE,ElementType.TYPE_PARAMETER}) public @interface " + name + " {}\n")
            target = java_root / "javax/annotation/concurrent/ThreadSafe.java"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("package javax.annotation.concurrent; public @interface ThreadSafe {}\n")
            oracle = java_root / "com/lokalized/LocaleOracle.java"
            oracle.write_text(JAVA)
            java_classes = output / "java-classes"
            java_classes.mkdir(exist_ok=True)
            javac = args.java_home.resolve() / "bin/javac"
            java = args.java_home.resolve() / "bin/java"
            run([javac, "-d", java_classes, *sorted(java_root.rglob("*.java"))])
        swiftc = Path(run(["xcrun", "--find", "swiftc"]).strip()) if platform.system() == "Darwin" else Path(shutil.which("swiftc") or "")
        sdk_flags = []
        if platform.system() == "Darwin":
            sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip()
            sdk_flags = ["-sdk", sdk, "-target", platform.machine()+"-apple-macosx12.0"]
            report["sdk"] = sdk
        report["compilerVersion"] = run([swiftc, "--version"]).strip()
        if not args.check: report["javacVersion"] = run([javac, "-version"]).strip()
        sources = sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))
        source_hashes = {str(path.relative_to(ROOT)): digest(path) for path in sources}
        report["sourceHashes"] = source_hashes
        report["javaSourceHashes"] = java_source_hashes
        report["javaCorpusCommit"] = ref
        cache = output / "module-cache"
        cache.mkdir(exist_ok=True)
        library = output / "libLokalized.dylib"
        module = output / "Lokalized.swiftmodule"
        consumer_source = output / "LocaleProbe.swift"
        consumer_source.write_text(SWIFT)
        consumer = output / "locale-probe"
        common = [swiftc, "-O", "-swift-version", "6", "-package-name", "lokalized_swift", "-module-cache-path", cache, *sdk_flags]
        run(common + ["-emit-library", "-emit-module", "-module-name", "Lokalized", *sources, "-o", library, "-emit-module-path", module])
        run(common + ["-I", output, "-L", output, "-lLokalized", "-Xlinker", "-rpath", "-Xlinker", output, consumer_source, "-o", consumer])
        timing_rows = [run([consumer, "--metadata-cost"]).strip().split("\t") for _ in range(15)]
        if any(len(row) != 2 or row[1] != "18675" for row in timing_rows):
            raise RuntimeError("Incomplete cold-table timing traversal")
        nanoseconds = [int(row[0]) for row in timing_rows]
        report["coldTableInitialization"] = dict(scope="first access to all 11 maps/sets; 15 fresh processes; excludes launch; no allocation measurement",
                                                  nanoseconds=nanoseconds, medianMilliseconds=statistics.median(nanoseconds)/1_000_000,
                                                  minimumMilliseconds=min(nanoseconds)/1_000_000, maximumMilliseconds=max(nanoseconds)/1_000_000)
        cases_path = output / "cases.txt"
        cases_path.write_text(cases)
        actual_text = run([consumer], cases)
        oracle_text = "\n".join(archive["observations"])+"\n" if args.check else run([java, "-cp", java_classes, "com.lokalized.LocaleOracle"], cases)
        actual_path = output / "swift-observations.tsv"
        oracle_path = output / "java-observations.tsv"
        actual_path.write_text(actual_text); oracle_path.write_text(oracle_text)
        actual, expected = actual_text.splitlines(), oracle_text.splitlines()
        if len(actual) != len(expected) or len(actual) != len(authored):
            raise RuntimeError("Authored/observed row counts differ")
        differences = []
        for index, (tag, observed, oracle_row) in enumerate(zip(authored, actual, expected)):
            if observed == oracle_row:
                continue
            left = [base64.b64decode(x).decode() for x in observed.split("\t")]
            right = [base64.b64decode(x).decode() for x in oracle_row.split("\t")]
            differences.append(dict(row=index+1, input=tag, fields=[dict(name=FIELDS[i], swift=x, java=y) for i,(x,y) in enumerate(zip(left,right)) if x!=y]))
        report["cases"] = len(authored)
        report["differences"] = differences
        report["provenanceHashes"] = {str(path.relative_to(ROOT)): digest(path) for path in [ROOT / "Reference/baseline.json", ROOT / "Reference/reference-runtime-lock.json", data_path, Path(__file__)]}
        report["jdkReleaseSha256"] = runtime["jdk"]["releaseFileSha256"]
        report["mode"] = "goldens" if args.check else "oracle"
        report["artifactHashes"] = {path.name: digest(path) for path in [cases_path, consumer_source, library, module, consumer, actual_path, oracle_path]}
        current = sorted((ROOT / "Sources/Lokalized").rglob("*.swift"))
        if current != sources or source_hashes != {str(path.relative_to(ROOT)): digest(path) for path in current}:
            raise RuntimeError("Swift sources changed mid-probe; rerun on stable sources")
        if differences:
            raise RuntimeError(f"{len(differences)} locale observation row(s) differ")
        if not args.check:
            report["javaArtifactHashes"] = {str(path.relative_to(output)): digest(path) for path in sorted(java_root.rglob("*.java")) + sorted(java_classes.rglob("*.class"))}
        if args.refresh_goldens:
            archive = dict(formatVersion=1, inputs=authored, observations=expected, fields=list(FIELDS),
                           javaCorpusCommit=ref, jdkReleaseSha256=digest(release), javaSourceHashes=java_source_hashes,
                           localeSourceSha256=digest(data_path), oracleSourceSha256=hashlib.sha256(JAVA.encode()).hexdigest())
            GOLDENS.write_bytes((json.dumps(archive, separators=(",", ":"), ensure_ascii=True)+"\n").encode())
            report["refreshedGoldenSha256"] = digest(GOLDENS)
        report["verified"] = True
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    report["completedAtUnix"] = time.time()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True)+"\n")
    print(json.dumps(dict(verified=report["verified"], cases=report.get("cases"), report=str(report_path), error=report.get("error")), sort_keys=True))
    return 0 if report["verified"] else 1


if __name__ == "__main__":
    sys.exit(main())
