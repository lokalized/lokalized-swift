#!/usr/bin/env python3
"""Sample an optimized public consumer of unmodified library sources on macOS.

Uses Apple's sample tool, installed SDKs and Python standard library only.
Sampled-loop timings are diagnostic observations, not benchmark or CI gates.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

from verify_package import package_check

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT/'Tools/Fixtures/LookupProfileConsumer.swift'


def sha(data): return hashlib.sha256(data).hexdigest()


def inputs():
    files = sorted(p for p in (ROOT/'Sources/Lokalized').rglob('*') if p.is_file())
    files += [ROOT/'Package.swift', HARNESS, Path(__file__).resolve()]
    return [{'path': str(p.relative_to(ROOT)), 'bytes': p.stat().st_size,
             'sha256': sha(p.read_bytes())} for p in files]


def invoke(args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args} failed ({result.returncode}): {result.stderr[-6000:]}')
    return result.stdout


def qualify(output):
    if platform.system() != 'Darwin': raise ValueError('Profiling requires macOS sample and Apple SDKs')
    frozen = inputs(); package = package_check('current')
    output.mkdir(parents=True, exist_ok=True)
    observations = []
    with tempfile.TemporaryDirectory(prefix='lokalized-lookup-profile-', dir='/private/tmp') as temp:
        scratch = Path(temp); copied = scratch/'Package'; copied.mkdir()
        for name in ['Package.swift', 'LICENSE']: shutil.copy2(ROOT/name, copied/name)
        shutil.copytree(ROOT/'Sources', copied/'Sources')
        consumer = scratch/'Consumer'; (consumer/'Sources/ProfileConsumer').mkdir(parents=True)
        (consumer/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LookupProfile", platforms: [.macOS(.v12)],
    dependencies: [.package(path: "../Package")], targets: [
      .executableTarget(name: "ProfileConsumer", dependencies: [.product(name: "Lokalized", package: "package")])],
    swiftLanguageModes: [.v6])
''')
        (consumer/'Sources/ProfileConsumer/main.swift').write_bytes(HARNESS.read_bytes())
        env = os.environ.copy(); env['CLANG_MODULE_CACHE_PATH'] = str(scratch/'sdk-cache')
        env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(scratch/'sdk-cache')
        args = ['swift', 'build', '--disable-sandbox', '--scratch-path', str(scratch/'Build'),
            '--cache-path', str(scratch/'spm-cache'), '--config-path', str(scratch/'spm-config'),
            '--security-path', str(scratch/'spm-security'), '-c', 'release', '--product', 'ProfileConsumer',
            '-Xswiftc', '-module-cache-path', '-Xswiftc', str(scratch/'sdk-cache')]
        invoke(args, consumer, env)
        binary = Path(invoke(args+['--show-bin-path'], consumer, env).strip())/'ProfileConsumer'
        for mode in ['plain', 'double-pi', 'double-max']:
            print('Sampling '+mode, flush=True)
            profile = (output/(mode+'.sample.txt')).resolve()
            child = subprocess.Popen([str(binary), mode], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                if child.stderr.readline() != 'ready\n':
                    raise ValueError('Consumer did not reach warmed lookup loop: '+mode)
                sampled = invoke(['/usr/bin/sample', str(child.pid), '2', '1', '-mayDie', '-file', str(profile)])
                stdout, stderr = child.communicate(timeout=15)
                if child.returncode or stderr: raise ValueError('Profile consumer failed: '+mode+' '+stderr)
                row = json.loads(stdout)
                if row['workload'] != mode or row['iterations'] <= 0 or row['durationNs'] < 5_000_000_000:
                    raise ValueError('Missing checked profiling loop')
                if row['checksum'] != row['iterations'] * (10 if mode == 'plain' else 5):
                    raise ValueError('Wrong profiling output checksum')
                trace = profile.read_text()
                if 'Call graph:' not in trace or 'DefaultStrings' not in trace:
                    raise ValueError('Sampling did not capture the library call graph')
                observations.append({'result': row, 'sampleFile': str(profile), 'sampleSHA256': sha(profile.read_bytes()),
                    'samplerStdout': sampled})
            finally:
                if child.poll() is None: child.kill(); child.wait()
        if inputs() != frozen: raise ValueError('Profile inputs changed during execution')
        report = {'scope': 'native-lookup-sampling', 'status': 'profiled-not-certified',
            'compiler': package['compiler'], 'hostOS': platform.platform(), 'sourceFiles': frozen,
            'sourceInputsRevalidated': True, 'externalPackageDependencies': 0,
            'binarySHA256': sha(binary.read_bytes()), 'observations': observations,
            'limits': ['Sampling observes optimized unmodified library sources; inlining and sampler overhead affect attribution.',
                'Timed loops are sampled diagnostics, not unsampled performance comparisons or latency gates.',
                'This host does not establish minimum compiler, other OS/architecture runtime or release parity.']}
    (output/'profile.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    print(json.dumps({'status': report['status'], 'workloads': len(observations), 'report': str(output/'profile.json')}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-directory', type=Path, required=True); args = parser.parse_args()
    try: qualify(args.output_directory); return 0
    except (RuntimeError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'status': 'error', 'error': str(error)})); return 1


if __name__ == '__main__': raise SystemExit(main())
