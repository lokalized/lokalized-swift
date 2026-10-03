#!/usr/bin/env python3
"""Qualify shared native decisions against current validated Swift evidence.

Never changes the frozen runtime audit or counts a native boundary as replay.
Normal checks consume saved compiler/host evidence and need only stdlib Python.
"""
import argparse
import copy
import json
from pathlib import Path

from NativeAdaptations import contract
from reference_baseline import check as baseline_check
from sync_native_contracts import read_pinned
from verify_package import audit_check, runtime_adapter_check
import verify_native_representations as native
import verify_loader_dispositions as loaders

ROOT = Path(__file__).resolve().parents[1]
LABELS = ['audit', 'types', 'runtimeAdapter', 'nativeTypes', 'loaders', 'deployment']


def snapshot():
    paths = sorted((ROOT/'Sources').rglob('*.swift'))
    paths += [ROOT/p for p in ['Package.swift', 'Tools/verify_native_contracts.py', 'Tools/sync_native_contracts.py',
        'Tools/reference_baseline.py', 'Tools/verify_package.py', 'Tools/verify_native_representations.py',
        'Tools/verify_callback_types.py', 'Tools/Fixtures/NativeTypeControls.swift', 'Tools/verify_loader_dispositions.py']]
    paths += [ROOT/'Tools/verify_deployment.py']
    paths += [ROOT/p for p in read_pinned(ROOT)]
    return [{'path': str(p.relative_to(ROOT)), 'sha256': contract.sha(p.read_bytes())} for p in paths]


def deployment_check(evidence):
    report = evidence['deployment']
    fields = 'commands compiler compilerTrack consumerSourceSha256 coverage finishedAtUTC host inputSha256 languageMode minimumCompilerExecuted minimumOSRuntimeExecution outputDirectory packageName referenceDirectory runtimeDependencies sdks sourceSha256 startedAtUTC status targets'.split()
    contract.require(set(report) == set(fields) and report['languageMode'] == '6', 'Deployment proof fields/language mode changed')
    contract.require(report['status'] == 'passed', 'Deployment/runtime qualification failed')
    sources = {str(p.relative_to(ROOT)): contract.sha(p.read_bytes()) for p in sorted((ROOT/'Sources').rglob('*.swift'))}
    contract.require(report['sourceSha256'] == sources, 'Runtime audit is not bound to current library/support sources')
    packages = [Path(p) for p in report['inputSha256'] if p.endswith('/Package.swift')]
    contract.require(len(packages) == 1, 'Deployment proof lacks package input identity')
    original_root = packages[0].parent
    inputs = {str(Path(p).relative_to(original_root)): pin for p, pin in report['inputSha256'].items()}
    contract.require({'Package.swift', 'Tools/verify_deployment.py', 'Reference/behavioral-vectors.json', 'Reference/baseline.json'} <= set(inputs),
                     'Runtime proof omits required qualification inputs')
    for relative, pin in inputs.items():
        contract.require(contract.sha((ROOT/relative).read_bytes()) == pin, 'Runtime qualification input changed: ' + relative)
    triples = ['arm64-apple-macosx12.0', 'x86_64-apple-macosx12.0', 'arm64-apple-ios15.0', 'arm64-apple-ios15.0-simulator']
    contract.require([t['triple'] for t in report['targets']] == triples
                     and all(t['status'] == 'compiled-imported-linked-inspected' and len(t['binaries']) == 4 for t in report['targets']), 'Deployment target/binary inventory changed')
    host = next(t for t in report['targets'] if t['triple'] == evidence['types']['target'])
    runtime = host['runtimeExecution']
    contract.require(runtime['status'] == 'passed-on-host' and runtime['wholeRuntimeAudit'] == evidence['audit'],
                     'Original runtime audit differs from current-source host execution')
    executions = [c for c in report['commands'] if c['label'] == 'Run native macOS whole-runtime corpus audit on host']
    contract.require(len(executions) == 1 and executions[0]['exitCode'] == 1
                     and json.loads(executions[0]['stdout'], object_pairs_hook=contract.unique) == evidence['audit'],
                     'Runtime audit execution output is missing or different')
    compiles = [c for c in report['commands'] if c['label'].startswith('Compile and link ')]
    contract.require(len(compiles) == 8 and all(c['exitCode'] == 0 for c in compiles), 'Missing/failed source module compilations')


def validated_coverage(evidence):
    deployment_check(evidence)
    native.compiler_check(evidence['types'])
    # The original adapter and loader inventories are checked before their
    # records become input to shared coverage accounting.
    expected = native.dossier(evidence['types'], evidence['runtimeAdapter'])
    native.check_dossier(evidence['nativeTypes'], expected)
    loader_expected = loaders.dossier(evidence['loaders']['evidence'])
    loaders.check_report(evidence['loaders'], loader_expected)
    profile = contract.read(ROOT/'Reference/swift-native-v1.json')
    corpus = contract.read_corpus(ROOT/'Reference/behavioral-vectors.json')
    return contract.coverage(profile, corpus, evidence['audit'], evidence['nativeTypes'], evidence['loaders'])


def qualify(paths):
    read_pinned(ROOT)
    baseline_check(ROOT/'Reference')
    frozen = snapshot()
    audit_check(paths['audit'], ROOT/'Reference')
    runtime_adapter_check(paths['runtimeAdapter'], ROOT/'Reference')
    evidence = read_evidence(paths)
    coverage = validated_coverage(evidence)
    contract.require(snapshot() == frozen, 'Qualification inputs changed during verification')
    return {'formatVersion': 1, 'scope': 'swift-native-contract-coverage', 'status': 'covered-under-native-contracts-not-certified',
        'releaseParity': False, 'runtimePassedAdded': [], 'coverage': coverage, 'sourceInputsRevalidated': True,
        'qualificationInputs': frozen, 'qualificationInputsSHA256': contract.sha(contract.canonical(frozen)),
        'inputReports': {label: contract.sha(path.read_bytes()) for label, path in paths.items()},
        'compiler': evidence['types']['compiler'], 'sdk': evidence['types']['sdk'], 'target': evidence['types']['target'],
        'hostOS': evidence['types']['hostOS'], 'runtimeScope': 'current macOS host evidence only',
        'externalPackageDependenciesAdded': 0, 'productionAPIsChanged': False, 'httpLoading': False,
        'limits': contract.LIMITS}


def check_report(actual, expected):
    contract.require(contract.canonical(actual) == contract.canonical(expected), 'Native contract coverage report is altered or stale')


def read_evidence(paths):
    # Deployment retains the independently checked 56,513-ID URL inventory.
    return {label: contract.read(path, maximum_bytes=32*1024*1024 if label == 'deployment' else 8*1024*1024)
            for label, path in paths.items()}


def negative_controls(expected, paths):
    rejected = []
    def report(name, mutate):
        value = copy.deepcopy(expected)
        mutate(value)
        try:
            check_report(value, expected)
        except (ValueError, KeyError, TypeError):
            rejected.append(name)
        else:
            raise ValueError('Altered coverage report passed: ' + name)
    for name, mutate in [
        ('invented-release-parity', lambda d: d.update(releaseParity=True)),
        ('native-adaptation-as-runtime-pass', lambda d: d['runtimePassedAdded'].append(d['coverage']['caseIDSets']['requiredPortableNativeAdaptations'][0])),
        ('omitted-required-case', lambda d: d['coverage']['caseIDSets']['requiredPortableNativeAdaptations'].pop()),
        ('duplicated-runtime-case', lambda d: d['coverage']['caseIDSets']['requiredPortableRuntimePassed'].append(d['coverage']['caseIDSets']['requiredPortableRuntimePassed'][0])),
        ('jvm-carrier-as-native-mapping', lambda d: d['coverage']['caseIDSets']['informationalNativeAdaptations'].append(d['coverage']['caseIDSets']['informationalPlatformSpecific'][0])),
        ('omitted-unreplayed-channel', lambda d: d['coverage']['records'][0]['notReplayedObservationChannels'].pop()),
        ('changed-profile-identity', lambda d: d['coverage'].update(profileSHA256='0'*64)),
        ('stale-source', lambda d: d['qualificationInputs'][0].update(sha256='0'*64)),
        ('altered-input-report', lambda d: d['inputReports'].update(types='0'*64)),
        ('invented-minimum-os-execution', lambda d: d.update(runtimeScope='macOS 12 and iOS 15 executed')),
        ('missing-limits', lambda d: d.update(limits=[])),
        ('unknown-report-field', lambda d: d.update(approved=True)),
    ]:
        report(name, mutate)
    evidence = read_evidence(paths)
    for name, mutate in [
        ('compiler-negative-accepted', lambda d: d['types']['negative'][0].update(exitCode=0)),
        ('unrelated-compiler-error', lambda d: d['types']['negative'][0].update(diagnostics="error: cannot find 'Phonetic' in scope")),
        ('changed-compiler-source', lambda d: d['types']['sourceFiles'][0].update(sha256='0'*64)),
        ('failed-native-control', lambda d: d['types']['runtimeControls'].update(executionExitCode=1)),
        ('missing-native-guard', lambda d: d['nativeTypes']['cases'][0].update(guards=[])),
        ('changed-input-fingerprint', lambda d: d['nativeTypes']['cases'][0].update(inputSha256='0'*64)),
        ('missing-loader-control', lambda d: d['loaders']['evidence']['nativeBoundaryReport']['passed'].pop()),
        ('changed-filename-rule', lambda d: next(r for r in d['loaders']['records'] if r['operation']=='load')['filenameEvidence'].update(nativeFilename='unrelated')),
        ('changed-reference-observation', lambda d: d['loaders']['records'][0].update(referenceObservationSHA256='0'*64)),
        ('required-runtime-pass-omitted', lambda d: d['audit']['runtimePassed'].pop()),
        ('original-audit-mapping-invented', lambda d: d['audit']['nativeRepresentationMapped'].append(d['nativeTypes']['cases'][0]['id'])),
        ('stale-runtime-source-binding', lambda d: d['deployment']['sourceSha256'].update({'Sources/Lokalized/Matching/MatcherElection.swift':'0'*64})),
        ('failed-deployment', lambda d: d['deployment'].update(status='failed')),
        ('runtime-proof-omitted', lambda d: next(t for t in d['deployment']['targets'] if t['triple'] == d['types']['target']).pop('runtimeExecution')),
        ('runtime-execution-log-omitted', lambda d: d['deployment'].update(commands=[])),
    ]:
        value = copy.deepcopy(evidence)
        mutate(value)
        try:
            validated_coverage(value)
        except (ValueError, KeyError, TypeError, RuntimeError):
            rejected.append(name)
        else:
            raise ValueError('Altered native proof passed: ' + name)
    return rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ['audit-report', 'type-report', 'runtime-adapter-report', 'native-type-report', 'loader-dispositions-report', 'deployment-report']:
        parser.add_argument('--'+option, type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--report-check', type=Path)
    parser.add_argument('--negative-controls', action='store_true')
    args = parser.parse_args()
    paths = dict(zip(LABELS, [args.audit_report, args.type_report, args.runtime_adapter_report,
        args.native_type_report, args.loader_dispositions_report, args.deployment_report]))
    try:
        result = qualify(paths)
        if args.report_check:
            check_report(contract.read(args.report_check), result)
        rejected = negative_controls(result, paths) if args.negative_controls else []
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, sort_keys=True, indent=2)+'\n')
        print(json.dumps({'status': result['status'], 'strictRuntimeAgreement': result['coverage']['strictRuntimeAgreement'],
            'requiredPortableCovered': result['coverage']['requiredPortableCovered'], 'nativeAdaptationsQualified': 25,
            'informationalPlatformSpecific': 159, 'releaseParity': False, 'rejectedControls': rejected}))
        return 0
    except (ValueError, KeyError, TypeError, OSError, RuntimeError) as error:
        print(json.dumps({'status': 'error', 'error': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
