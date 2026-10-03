#!/usr/bin/env python3
"""Execute current-source external manifest consumers and adjacent runtime controls.

Python stdlib only; uses an isolated temporary source/module snapshot. No JS
expected observation controls compiler or runtime execution.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

from ManifestContracts import native_policy as policy

ROOT = Path(__file__).resolve().parents[1]
POSITIVE = '''import Lokalized
let input = CatalogIdentityInputV1(catalogVersion: "v1", resolvedFallbackLocale: "en")
let identity = try LocalizedStringLoader.computeCatalogIdentity(input)
let explicit = CatalogIdentityInputV1(formatVersion: 1, catalogVersion: "v1", resolvedFallbackLocale: "en", localeToSha256: [:], tiebreakerLocalesByLanguageCode: [:])
let options = try LocalizedStringLoadingOptions(maximumLocalizedStringsFiles: 2)
func consume(_ manifest: StringsManifestV1) throws {
    _ = try LocalizedStringLoader.validateStringsManifest(manifest, loadingOptions: options)
    _ = try LocalizedStringLoader.chain(manifest, lookupLocale: "en")
    _ = try LocalizedStringLoader.fetchSet(manifest, lookupLocale: "en")
}
'''


def run(command):
    return subprocess.run(command, text=True, capture_output=True)


def diagnostics_match(text, family, token):
    errors = [line.split('error: ', 1)[1] for line in text.splitlines() if 'error: ' in line]
    if family == 'unicode':
        # The invalid token is removed during compiler recovery, which may then
        # report that the enclosing initializer is missing precisely that arg.
        return any('invalid unicode scalar' in line.lower() for line in errors) and all(
            'invalid unicode scalar' in line.lower() or re.fullmatch(
                r"missing argument for parameter (?:#1|'catalogVersion') in call", line) for line in errors)
    patterns = {
        'type': r"(?:'nil' (?:is not compatible|cannot initialize)|cannot convert value of type|cannot convert value of type .* to expected (?:element|argument) type)",
        'missing': r'missing argument for parameter',
        'argument': r'(?:extra argument|incorrect argument label)',
        'unicode': r'invalid unicode scalar',
    }
    return bool(errors) and all(re.search(patterns[family], line, re.IGNORECASE) and token.lower() in line.lower() for line in errors)


def source_manifest(root):
    return [{'path': str(p.relative_to(root)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(), 'bytes': p.stat().st_size}
        for p in sorted((root/'Sources/Lokalized').rglob('*.swift'))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--swiftc', default='swiftc')
    args = parser.parse_args()
    root = args.source_root.resolve()
    compiler = shutil.which(args.swiftc)
    if not compiler or platform.system() != 'Darwin':
        parser.error('Host Apple compiler required')
    sdk_result = run(['xcrun', '--sdk', 'macosx', '--show-sdk-path'])
    if sdk_result.returncode:
        raise ValueError(sdk_result.stderr)
    sdk = sdk_result.stdout.strip()
    target = platform.machine() + '-apple-macosx12.0'
    profile = policy.read(root/'Reference/swift-manifest-v1.json')
    cases = policy.read(root/'Reference/manifest-contract-vectors.json')['cases']
    policy.check_profile(profile, cases)
    sources = source_manifest(root)
    fixture_path = root/'Tools/Fixtures/ManifestNativeControls.swift'
    fixture = fixture_path.read_text()
    receipt = {'formatVersion': 1, 'scope': 'swift-manifest-native-consumers',
        'compiler': run([compiler, '--version']).stdout.strip(), 'target': target, 'sdk': sdk,
        'hostOS': platform.platform(), 'sourceFiles': sources,
        'sourceManifestSHA256': policy.sha(policy.canonical(sources)),
        'moduleCompilation': None, 'positive': None, 'consumers': [], 'runtimeControls': None,
        'sourceInputsRevalidated': False, 'passed': False}
    with tempfile.TemporaryDirectory(prefix='lokalized-manifest-types-', dir='/private/tmp') as temp:
        scratch = Path(temp)
        copied = []
        for entry in sources:
            path = scratch/entry['path']; path.parent.mkdir(parents=True, exist_ok=True)
            raw = (root/entry['path']).read_bytes()
            if policy.sha(raw) != entry['sha256']:
                raise ValueError('Source changed before snapshot: '+entry['path'])
            path.write_bytes(raw); copied.append(str(path))
        common = [compiler, '-swift-version', '6', '-target', target, '-sdk', sdk,
            '-module-cache-path', str(scratch/'module-cache')]
        built = run(common + ['-parse-as-library', '-emit-module', '-emit-library',
            '-o', str(scratch/'libLokalized.dylib'), '-module-name', 'Lokalized',
            '-package-name', 'lokalized_swift', '-emit-module-path', str(scratch/'Lokalized.swiftmodule')] + copied)
        receipt['moduleCompilation'] = {'exitCode': built.returncode, 'diagnostics': built.stdout+built.stderr}
        if built.returncode == 0:
            file = scratch/'Positive.swift'; file.write_text(POSITIVE)
            result = run(common+['-typecheck', '-I', str(scratch), str(file)])
            receipt['positive'] = {'source': POSITIVE, 'sourceSHA256': policy.sha(POSITIVE.encode()),
                'exitCode': result.returncode, 'diagnostics': result.stdout+result.stderr}
            for i, record in enumerate(profile['nativeAdaptations']):
                file = scratch/f'Consumer{i}.swift'; file.write_text(record['source'])
                result = run(common+['-typecheck', '-I', str(scratch), str(file)])
                diagnostic = result.stdout+result.stderr
                passed = result.returncode == 0 if record['expectation'] == 'accepted' else result.returncode != 0 and diagnostics_match(diagnostic, record['diagnosticFamily'], record['diagnosticToken'])
                receipt['consumers'].append({'id': record['id'], 'source': record['source'],
                    'sourceSHA256': record['sourceSHA256'], 'expectation': record['expectation'],
                    'exitCode': result.returncode, 'diagnostics': diagnostic, 'passed': passed})
            file = scratch/'Runtime.swift'; file.write_text(fixture)
            binary = scratch/'controls'
            built = run(common+['-I', str(scratch), '-L', str(scratch), '-lLokalized',
                '-Xlinker', '-rpath', '-Xlinker', str(scratch), str(file), '-o', str(binary)])
            result = run([str(binary)]) if built.returncode == 0 else None
            observed = None
            if result and result.returncode == 0:
                observed = json.loads(result.stdout)
            receipt['runtimeControls'] = {'sourcePath': 'Tools/Fixtures/ManifestNativeControls.swift',
                'source': fixture, 'sourceSHA256': policy.sha(fixture.encode()),
                'compilationExitCode': built.returncode, 'compilationDiagnostics': built.stdout+built.stderr,
                'executionExitCode': result.returncode if result else None,
                'stdout': result.stdout if result else '', 'stderr': result.stderr if result else '',
                'observed': observed, 'passed': built.returncode == 0 and result is not None
                    and result.returncode == 0 and observed == {'passed': policy.RUNTIME_IDS}}
            receipt['passed'] = receipt['positive']['exitCode'] == 0 and all(r['passed'] for r in receipt['consumers']) and receipt['runtimeControls']['passed']
        receipt['sourceInputsRevalidated'] = source_manifest(root) == sources and fixture_path.read_text() == fixture
        receipt['passed'] = receipt['passed'] and receipt['sourceInputsRevalidated']
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(receipt, indent=2, sort_keys=True)+'\n')
    print(json.dumps({'status': 'passed' if receipt['passed'] else 'failed', 'consumers': len(receipt['consumers']),
        'runtimeControls': len(policy.RUNTIME_IDS), 'report': str(args.report)}))
    if not receipt['passed']:
        print(receipt['moduleCompilation']['diagnostics'])
        for item in receipt['consumers']:
            if not item['passed']: print(item['id']+'\n'+item['diagnostics'])
        if receipt['runtimeControls'] and not receipt['runtimeControls']['passed']:
            print(json.dumps(receipt['runtimeControls'], indent=2))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
