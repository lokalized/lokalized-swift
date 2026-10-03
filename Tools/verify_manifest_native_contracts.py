#!/usr/bin/env python3
"""Qualify shared manifest adaptations against current compiler/runtime receipts.

Saved-report checks are offline. Raw JS/native observations stay unchanged and
no compiler refusal is counted as runtime agreement.
"""
import argparse
import contextlib
import copy
import io
import json
from pathlib import Path
import re

from ManifestContracts import archive, native_report as raw, native_policy as policy
import sync_manifest_contracts as sync
import verify_manifest_types as types

ROOT = Path(__file__).resolve().parents[1]


def fields(value, names, label):
    policy.require(type(value) is dict and set(value) == set(names.split()), 'Unexpected '+label+' fields')


def zero(value):
    return type(value) is int and value == 0


def compiler_check(report, profile):
    fields(report, 'formatVersion scope compiler target sdk hostOS sourceFiles sourceManifestSHA256 moduleCompilation positive consumers runtimeControls sourceInputsRevalidated passed', 'compiler receipt')
    policy.require(report['formatVersion'] == 1 and report['scope'] == 'swift-manifest-native-consumers'
        and report['passed'] is True and report['sourceInputsRevalidated'] is True, 'Compiler receipt failed or changed during execution')
    match = re.search(r'Swift version (\d+)\.(\d+)\b', report['compiler'])
    policy.require(match and tuple(map(int, match.groups())) >= (6,2), 'Unsupported compiler evidence')
    policy.require(report['target'] in ['arm64-apple-macosx12.0','x86_64-apple-macosx12.0']
        and all(type(report[k]) is str and report[k] for k in ['sdk','hostOS']), 'Missing target/SDK/host')
    sources = types.source_manifest(ROOT)
    policy.require(report['sourceFiles'] == sources and report['sourceManifestSHA256'] == policy.sha(policy.canonical(sources)), 'Stale/incomplete production source receipt')
    module = report['moduleCompilation']; fields(module, 'exitCode diagnostics', 'module')
    policy.require(zero(module['exitCode']) and type(module['diagnostics']) is str, 'Library compilation failed')
    positive = report['positive']; fields(positive, 'source sourceSHA256 exitCode diagnostics', 'positive consumer')
    policy.require(positive['source'] == types.POSITIVE and positive['sourceSHA256'] == policy.sha(types.POSITIVE.encode())
        and zero(positive['exitCode']) and type(positive['diagnostics']) is str, 'Changed/failed positive consumer')
    consumers = report['consumers']
    policy.require(type(consumers) is list and [c['id'] for c in consumers] == [c['id'] for c in profile['nativeAdaptations']], 'Compiler consumer inventory differs')
    for observed, required in zip(consumers, profile['nativeAdaptations']):
        fields(observed, 'id source sourceSHA256 expectation exitCode diagnostics passed', 'native consumer')
        policy.require(all(observed[k] == required[k] for k in ['id','source','sourceSHA256','expectation'])
            and type(observed['diagnostics']) is str and observed['passed'] is True, 'Consumer source/expectation altered')
        if required['expectation'] == 'accepted':
            policy.require(zero(observed['exitCode']), 'Native default consumer did not compile')
        else:
            policy.require(type(observed['exitCode']) is int and observed['exitCode'] != 0
                and types.diagnostics_match(observed['diagnostics'], required['diagnosticFamily'], required['diagnosticToken']), 'Consumer did not fail for intended type/argument/scalar reason: '+required['id'])
    runtime = report['runtimeControls']
    fields(runtime, 'sourcePath source sourceSHA256 compilationExitCode compilationDiagnostics executionExitCode stdout stderr observed passed', 'runtime controls')
    source = (ROOT/'Tools/Fixtures/ManifestNativeControls.swift').read_text()
    policy.require(runtime['sourcePath'] == 'Tools/Fixtures/ManifestNativeControls.swift' and runtime['source'] == source
        and runtime['sourceSHA256'] == policy.sha(source.encode()), 'Runtime control source changed')
    policy.require(zero(runtime['compilationExitCode']) and zero(runtime['executionExitCode']) and runtime['passed'] is True
        and all(type(runtime[k]) is str for k in ['stdout','stderr','compilationDiagnostics']), 'Runtime controls failed')
    policy.require(raw.read_json(runtime['stdout']) == runtime['observed'] == {'passed': policy.RUNTIME_IDS}, 'Missing/changed adjacent runtime observations')


def deployment_check(deployment, compiler, runtime):
    policy.require(deployment['status'] == 'passed' and deployment['compiler'] == compiler['compiler'], 'Deployment failed or compiler differs')
    sources = {str(p.relative_to(ROOT)): policy.sha(p.read_bytes()) for p in sorted((ROOT/'Sources').rglob('*.swift'))}
    policy.require(deployment['sourceSha256'] == sources, 'Manifest execution not bound to current library/support sources')
    roots = [Path(p).parent for p in deployment['inputSha256'] if p.endswith('/Package.swift')]
    policy.require(len(roots) == 1, 'Missing deployment package identity')
    inputs = {str(Path(p).relative_to(roots[0])): pin for p,pin in deployment['inputSha256'].items()}
    needed = {'Package.swift', 'Tools/verify_deployment.py', 'Tools/verify_manifest_contract_report.py',
        'Reference/manifest-contract-vectors.json', 'Reference/manifest-contract-lock.json'}
    from sync_manifest_normalization import read_pinned as normalization_snapshot
    needed |= set(normalization_snapshot(ROOT)) | {"Tools/sync_manifest_normalization.py"}
    needed |= {p for p in sync.read_pinned(ROOT) if p.startswith('Tools/ManifestContracts/')}
    policy.require(needed <= set(inputs), 'Runtime proof omits manifest verifier inputs')
    for relative,pin in inputs.items():
        policy.require(policy.sha((ROOT/relative).read_bytes()) == pin, 'Runtime qualification input changed: '+relative)
    triples = ['arm64-apple-macosx12.0','x86_64-apple-macosx12.0','arm64-apple-ios15.0','arm64-apple-ios15.0-simulator']
    policy.require([t['triple'] for t in deployment['targets']] == triples
        and all(t['status'] == 'compiled-imported-linked-inspected' and len(t['binaries']) == 4 for t in deployment['targets']), 'Deployment target/binary inventory differs')
    host = next(t for t in deployment['targets'] if t['triple'] == compiler['target'])
    policy.require(host['runtimeExecution']['status'] == 'passed-on-host'
        and host['runtimeExecution']['manifestContract'] == runtime, 'Manifest receipt differs from source-bound host execution')
    executions = [c for c in deployment['commands'] if c['label'] == 'Run native macOS manifest contract qualification on host']
    policy.require(len(executions) == 1 and zero(executions[0]['exitCode'])
        and raw.read_json(executions[0]['stdout']) == runtime, 'Missing/altered host manifest execution log')
    compiles = [c for c in deployment['commands'] if c['label'].startswith('Compile and link ')]
    policy.require(len(compiles) == 8 and all(zero(c['exitCode']) for c in compiles), 'Missing/failed source compilation logs')


def snapshot():
    paths = sorted((ROOT/'Sources').rglob('*.swift'))
    paths += [ROOT/relative for relative in sync.read_pinned(ROOT)]
    from sync_manifest_normalization import read_pinned as normalization_snapshot
    paths += [ROOT/relative for relative in normalization_snapshot(ROOT)]
    paths += [ROOT/"Tools/sync_manifest_normalization.py"]
    paths += [ROOT/p for p in ['Package.swift','Tools/verify_manifest_native_contracts.py','Tools/verify_manifest_types.py',
        'Tools/Fixtures/ManifestNativeControls.swift','Tools/sync_manifest_contracts.py','Tools/verify_deployment.py',
        'Tools/verify_manifest_contract_report.py']]
    return [{'path': str(p.relative_to(ROOT)), 'sha256': policy.sha(p.read_bytes())} for p in paths]


def validated(evidence):
    profile = policy.read(ROOT/'Reference/swift-manifest-v1.json')
    cases = policy.read(ROOT/'Reference/manifest-contract-vectors.json')['cases']
    policy.check_profile(profile, cases)
    compiler_check(evidence['compiler'], profile)
    deployment_check(evidence['deployment'], evidence['compiler'], evidence['runtime'])
    # The caller checks the raw report with the shared narrow comparison checker.
    runtime=evidence['runtime']
    policy.require(runtime.get("behaviorProfileID") == "manifest-normalization-v1.1" and runtime.get("behaviorProfileVersion") == "1.1.0", "Current manifest behavior profile missing")
    coverage=policy.coverage(profile, cases, runtime)
    coverage.update({k:runtime[k] for k in ["behaviorProfileID","behaviorProfileVersion","behaviorProfileSHA256","archiveCorrectionIDs","historicalAgreementIDs"]})
    return coverage


def qualify(paths):
    sync.read_pinned(ROOT)
    archive.configure(ROOT/'Reference')
    with contextlib.redirect_stdout(io.StringIO()):
        archive.check()
    before = snapshot()
    from verify_manifest_contract_report import report_check as active_report_check
    raw_result = active_report_check(paths['runtime'], ROOT/'Reference')
    evidence = {k: policy.read(p, 32*1024*1024 if k == 'deployment' else 8*1024*1024) for k,p in paths.items()}
    coverage = validated(evidence)
    policy.require(snapshot() == before, 'Qualification inputs changed')
    return {'formatVersion': 1, 'scope': 'swift-manifest-native-contract-coverage',
        'status': 'covered-under-native-contracts-not-certified', 'releaseParity': False,
        'coverage': coverage, 'rawComparison': raw_result, 'runtimePassedAdded': [],
        'qualificationInputs': before, 'qualificationInputsSHA256': policy.sha(policy.canonical(before)),
        'inputReports': {k:policy.sha(p.read_bytes()) for k,p in paths.items()},
        'compiler': evidence['compiler']['compiler'], 'target': evidence['compiler']['target'],
        'sdk': evidence['compiler']['sdk'], 'hostOS': evidence['compiler']['hostOS'],
        'sourceInputsRevalidated': True, 'externalPackageDependenciesAdded': 0,
        'productionAPIsChanged': False, 'httpLoading': False,
        'runtimeScope': 'current macOS host evidence only', 'limits': policy.LIMITS}


def check_report(actual, expected):
    policy.require(policy.canonical(actual) == policy.canonical(expected), 'Native manifest coverage receipt is stale or altered')


def negative_controls(expected, paths):
    rejected = []
    changes = [
        ('invented-release-parity', lambda d:d.update(releaseParity=True)),
        ('boundary-counted-as-runtime', lambda d:d['runtimePassedAdded'].append(d['coverage']['nativeRepresentationMapped'][0])),
        ('omitted-mapping', lambda d:d['coverage']['nativeRepresentationMapped'].pop()),
        ('duplicated-runtime-case', lambda d:d['coverage']['runtimePassed'].append(d['coverage']['runtimePassed'][0])),
        ('omitted-original-channel', lambda d:next(iter(d['coverage']['unreplayedChannelsByID'].values())).pop()),
        ('invented-minimum-os', lambda d:d.update(runtimeScope='iOS 15 and macOS 12 executed')),
        ('changed-input-report', lambda d:d['inputReports'].update(compiler='0'*64)),
        ('unknown-field', lambda d:d.update(approved=True)),
    ]
    for name,mutate in changes:
        changed = copy.deepcopy(expected); mutate(changed)
        try: check_report(changed, expected)
        except ValueError: rejected.append(name)
        else: raise ValueError('Altered coverage passed: '+name)
    evidence = {k:policy.read(p,32*1024*1024) for k,p in paths.items()}
    changes = [
        ('stale-source', lambda d:d['compiler']['sourceFiles'][0].update(sha256='0'*64)),
        ('negative-consumer-accepted', lambda d:d['compiler']['consumers'][0].update(exitCode=0)),
        ('unrelated-compiler-error', lambda d:d['compiler']['consumers'][0].update(diagnostics="error: cannot find 'String' in scope")),
        ('changed-consumer-source', lambda d:d['compiler']['consumers'][0].update(source='import Lokalized\n')),
        ('accepted-default-refused', lambda d:next(c for c in d['compiler']['consumers'] if c['expectation']=='accepted').update(exitCode=1)),
        ('missing-consumer', lambda d:d['compiler']['consumers'].pop()),
        ('source-changed-during-run', lambda d:d['compiler'].update(sourceInputsRevalidated=False)),
        ('runtime-control-failed', lambda d:d['compiler']['runtimeControls'].update(executionExitCode=1)),
        ('unicode-repair-control-omitted', lambda d:d['compiler']['runtimeControls']['observed']['passed'].remove('unicode-decoder-high-repairs')),
        ('runtime-control-source-changed', lambda d:d['compiler']['runtimeControls'].update(source='print("passed")')),
        ('deployment-failed', lambda d:d['deployment'].update(status='failed')),
        ('deployment-source-changed', lambda d:d['deployment']['sourceSha256'].update({'Sources/Lokalized/API/CatalogIdentity.swift':'0'*64})),
        ('host-observation-changed', lambda d:next(t for t in d['deployment']['targets'] if 'runtimeExecution' in t)['runtimeExecution']['manifestContract']['runtimePassed'].pop()),
        ('execution-logs-omitted', lambda d:d['deployment'].update(commands=[])),
        ('runtime-pass-omitted', lambda d:d['runtime']['runtimePassed'].pop()),
    ]
    for name,mutate in changes:
        changed = copy.deepcopy(evidence); mutate(changed)
        try: validated(changed)
        except (ValueError,KeyError,TypeError): rejected.append(name)
        else: raise ValueError('Altered evidence passed: '+name)
    return rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--type-report',type=Path,required=True)
    parser.add_argument('--runtime-report',type=Path,required=True)
    parser.add_argument('--deployment-report',type=Path,required=True)
    parser.add_argument('--report',type=Path)
    parser.add_argument('--report-check',type=Path)
    parser.add_argument('--negative-controls',action='store_true')
    args = parser.parse_args()
    paths = {'compiler':args.type_report,'runtime':args.runtime_report,'deployment':args.deployment_report}
    result = qualify(paths)
    if args.report_check: check_report(policy.read(args.report_check),result)
    rejected = negative_controls(result,paths) if args.negative_controls else []
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':result['status'],'runtimeCases':len(result['coverage']['runtimePassed']),
        'nativeAdaptations':len(result['coverage']['nativeRepresentationMapped']),
        'releaseParity':False,'rejectedNegativeControls':rejected}))


if __name__ == '__main__':
    main()
