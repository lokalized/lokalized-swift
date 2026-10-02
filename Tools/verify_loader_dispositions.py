#!/usr/bin/env python3
"""Qualify native loader boundaries and account for all pending donor carriers.

Uses Python's standard library. --qualify compiles current sources in isolation
and executes actual loader/Bundle controls. Ordinary receipt checks are offline.
No JVM observation becomes a runtime pass or a ratified mapping.
"""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

from reference_baseline import check as baseline_check
from verify_package import loader_check

ROOT = Path(__file__).resolve().parents[1]
CONTROL_IDS = sorted("""explicit-bundle-context canonical-origins-and-exact-keys bundle-missing-exact-directory
bundle-empty-directory bundle-file-not-directory bundle-literal-path-validation bundle-has-no-jvm-reserved-namespace
explicit-mapping-bypasses-filename-rules explicit-lproj-remains-literal mapping-repeated-resource-charges-bytes
mapping-no-discovery-charge mapping-file-cap-before-validation-and-io mapping-directory-refused
mapping-rendered-collision-before-io bundle-discovery-nonrecursive warning-error-identity-and-reentry
directory-invalid-filename-byte-order directory-file-cap-byte-order directory-extensionless-before-json
discovery-overflow-before-selected-file-fault""".split())
LIMITS = [
    "159 informational JVM inputs have explicit native carrier dispositions; their classloader observations are not replayed.",
    "Five directory observations differ only in authored filename attribution; all original/native observations remain separate.",
    "Named native controls qualify adjacent Bundle/resource-map behavior, not per-case classloader/JAR equivalence.",
    "No shared native mapping, corpus runtime pass or release parity is ratified by this report.",
    "Host macOS execution does not establish minimum Swift 6.2, old-OS/iOS/Intel runtime or hosted CI coverage."]


def canonical(value): return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
def sha(value): return hashlib.sha256(value).hexdigest()
def require(value, message):
    if not value: raise ValueError(message)


def unique(items):
    result = {}
    for key, value in items:
        require(key not in result, f"Duplicate JSON member {key}"); result[key] = value
    return result


def read(path): return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def snapshot():
    paths = sorted((ROOT / 'Sources').rglob('*.swift')) + [ROOT / 'Tools/verify_loader_dispositions.py']
    return [{"path": str(p.relative_to(ROOT)), "sha256": sha(p.read_bytes())} for p in paths]


def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    require(result.returncode == 0, f"{args[0]} failed ({result.returncode}): {result.stderr}")
    return result


def qualify():
    require(platform.system() == 'Darwin', 'Native loader qualification needs Apple SDKs')
    sources = snapshot()
    compiler = run(['xcrun', '--find', 'swiftc']).stdout.strip()
    sdk = run(['xcrun', '--sdk', 'macosx', '--show-sdk-path']).stdout.strip()
    architecture = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
    target = architecture + '-apple-macosx12.0'
    steps = []
    with tempfile.TemporaryDirectory(prefix='lokalized-loader-dispositions-', dir='/private/tmp') as temp:
        scratch = Path(temp)
        for row in sources:
            if not row['path'].startswith('Sources/'): continue
            data = (ROOT / row['path']).read_bytes()
            require(sha(data) == row['sha256'], 'Source changed before compilation')
            path = scratch / row['path']; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        flags = ['-swift-version', '6', '-target', target, '-sdk', sdk,
            '-module-cache-path', str(scratch/'module-cache'), '-package-name', 'lokalized_swift']
        for name, dependencies in [('Lokalized', []), ('LokalizedConformanceSupport', ['Lokalized'])]:
            files = [str(p) for p in sorted((scratch/'Sources'/name).rglob('*.swift'))]
            arguments = [compiler, *flags, '-parse-as-library', '-emit-library', '-emit-module', '-module-name', name,
                '-emit-module-path', str(scratch/(name+'.swiftmodule')), '-I', str(scratch), '-L', str(scratch),
                *[arg for dep in dependencies for arg in ['-l'+dep]], *files, '-o', str(scratch/('lib'+name+'.dylib'))]
            result = run(arguments)
            steps.append({'module': name, 'exitCode': result.returncode, 'diagnostics': result.stdout+result.stderr})
        executable = scratch/'LokalizedConformance'
        result = run([compiler, *flags, '-I', str(scratch), '-L', str(scratch), '-lLokalized', '-lLokalizedConformanceSupport',
            '-Xlinker', '-rpath', '-Xlinker', str(scratch), str(scratch/'Sources/LokalizedConformance/main.swift'), '-o', str(executable)])
        steps.append({'module': 'LokalizedConformance', 'exitCode': result.returncode, 'diagnostics': result.stdout+result.stderr})
        boundaries = run([str(executable), '--loader-boundaries'])
        loader = run([str(executable), '--loader', '--reference', str(ROOT/'Reference')])
        loader_report = json.loads(loader.stdout, object_pairs_hook=unique)
        boundary_report = json.loads(boundaries.stdout, object_pairs_hook=unique)
        loader_path = scratch/'loader.json'; loader_path.write_text(loader.stdout)
        loader_check(loader_path, ROOT/'Reference')
    require(snapshot() == sources, 'Source changed during native execution')
    baseline_check(ROOT/'Reference')
    return {'sourceFiles': sources, 'sourceManifestSHA256': sha(canonical(sources)), 'sourceInputsRevalidated': True,
        'compiler': run([compiler, '--version']).stdout.strip(), 'sdk': sdk, 'target': target, 'hostOS': platform.platform(),
        'compilation': steps, 'loaderExecutionExitCode': loader.returncode, 'boundaryExecutionExitCode': boundaries.returncode,
        'loaderReport': loader_report, 'nativeBoundaryReport': boundary_report}


def check_evidence(evidence):
    require(set(evidence) == set('sourceFiles sourceManifestSHA256 sourceInputsRevalidated compiler sdk target hostOS compilation loaderExecutionExitCode boundaryExecutionExitCode loaderReport nativeBoundaryReport'.split()), 'Unknown/missing native evidence field')
    require(evidence['sourceFiles'] == snapshot() and evidence['sourceManifestSHA256'] == sha(canonical(snapshot()))
        and evidence['sourceInputsRevalidated'] is True, 'Stale or changed source receipt')
    require(evidence['target'] in ('arm64-apple-macosx12.0', 'x86_64-apple-macosx12.0')
        and all(isinstance(evidence[k], str) and evidence[k] for k in ['compiler', 'sdk', 'hostOS']), 'Missing compiler/SDK/host evidence')
    require([step.get('module') for step in evidence['compilation']] == ['Lokalized', 'LokalizedConformanceSupport', 'LokalizedConformance'], 'Incomplete compilation inventory')
    require(all(set(step) == {'module', 'exitCode', 'diagnostics'} and type(step['exitCode']) is int and step['exitCode'] == 0
        and isinstance(step['diagnostics'], str) for step in evidence['compilation']), 'Compilation failed')
    require(all(type(evidence[k]) is int and evidence[k] == 0 for k in ['loaderExecutionExitCode', 'boundaryExecutionExitCode']), 'Native execution failed')
    report = evidence['nativeBoundaryReport']
    require(set(report) == {'scope', 'status', 'passed', 'observations'} and report['scope'] == 'native-local-loader-boundaries'
        and report['status'] == 'passed' and report['passed'] == CONTROL_IDS, 'Missing/duplicated/failed native boundary controls')
    require(set(report['observations']) == set(CONTROL_IDS) and all(isinstance(s, str) and s for s in report['observations'].values()), 'Missing native control observations')
    with tempfile.TemporaryDirectory(prefix='lokalized-loader-receipt-', dir='/private/tmp') as temp:
        p = Path(temp)/'loader.json'; p.write_text(json.dumps(evidence['loaderReport']))
        loader_check(p, ROOT/'Reference')


def filename_evidence(row, fixture, category, observation):
    require(row['operation'] == 'load' and row['input'] == {} and fixture['pathShape'] == 'directory', 'Wrong native ordering input shape')
    require(set(observation) == {'id','nativeObservationJSON','referenceObservationJSON','difference'}, 'Unknown observation field')
    native, reference = json.loads(observation['nativeObservationJSON'], object_pairs_hook=unique), json.loads(observation['referenceObservationJSON'], object_pairs_hook=unique)
    require(reference == row['expected'] and observation['difference'] == 'String code units differ at $.load.failureMessage', 'Changed reference observation/difference')
    require(set(native) == {'load'} and set(native['load']) == set(reference['load']), 'Changed native channels')
    fields = ['locales','keysByLocale','failed','failureType','warnings']
    require(all(native['load'][key] == reference['load'][key] for key in fields) and native['load']['failed'] is True, 'Non-filename observation differs')
    root = '<fixtures>/' + row['fixture'] + '/'
    names = sorted(set(fixture['files']) | set(fixture['rawFiles']) | set(fixture['rawFilesBase64']), key=lambda x: x.encode('utf8'))
    cap = (fixture['loadingOptions'] or {}).get('maximumLocalizedStringsFiles', 256)
    if category == 'native-competing-invalid-json-filenames':
        candidates = sorted(fixture['rawFiles'], key=lambda x: x.encode('utf8'))
        require(candidates == ['notes.json','zz.json'], 'Unreviewed competing invalid filename shape')
        selected = candidates[0]
        def message(name): return f"File '{name}' ends with .json but is not named with a valid IETF BCP 47 language tag. Use names like 'en', 'en.json', or 'en-US.json'"
        controls = ['directory-invalid-filename-byte-order','discovery-overflow-before-selected-file-fault']
    elif category == 'native-aggregate-file-cap-diagnostic-order':
        require(not fixture['rawFiles'] and not fixture['rawFilesBase64'] and len(names) > cap and type(cap) is int and cap > 0, 'Unreviewed file cap shape')
        candidates, selected = names, names[cap]
        def message(name): return root + name + f': localized strings load exceeds the aggregate localized strings file limit of {cap}'
        controls = ['directory-file-cap-byte-order','mapping-file-cap-before-validation-and-io']
    elif category == 'native-extensionless-json-alias-diagnostic-order':
        require(names == ['en','en.json'], 'Unreviewed extensionless/JSON alias shape')
        candidates, selected = names, names[1]
        def message(name): return f"Duplicate localized strings file for locale 'en' found at '{root+name}'"
        controls = ['directory-extensionless-before-json','discovery-overflow-before-selected-file-fault']
    else: raise ValueError('Unknown native filename category')
    require(native['load']['failureMessage'] == message(selected), 'Native diagnostic does not follow authored unsigned UTF-8 ordering')
    donor_names = [name for name in candidates if reference['load']['failureMessage'] == message(name)]
    require(len(donor_names) == 1 and donor_names[0] != selected, 'Reference differs beyond its authored filename attribution')
    return {'nativeFilename': selected, 'referenceFilename': donor_names[0], 'authoredCandidatesInByteOrder': candidates,
        'nativeObservation': native, 'referenceObservation': reference, 'equalChannels': fields,
        'differentChannels': ['failureMessage.filename'], 'nativeControls': controls}


def dossier(evidence):
    check_evidence(evidence)
    corpus = read(ROOT/'Reference/behavioral-vectors.json')
    rows = {row['id']: row for row in corpus['cases']}
    adaptations = {row['id']: row for row in evidence['loaderReport']['adaptationObservations']}
    materialized = read(ROOT/'Reference/materialized-fixtures.json')
    records = []
    for pending in evidence['loaderReport']['pendingCarriers']:
        row = rows[pending['id']]; fixture = corpus['fixtures'][row['fixture']]
        require(row['partition'] == 'informationalIds', 'A required portable case cannot be excluded as a local carrier')
        category = pending['category']
        record = {'id': row['id'], 'operation': row['operation'], 'partition': row['partition'], 'category': category,
            'inputSHA256': sha(canonical({'operation':row['operation'],'input':row['input'],'fixture':fixture})),
            'referenceObservationSHA256': sha(canonical(row['expected'])), 'guardEvidence': pending['evidence']}
        if row['operation'] == 'load':
            record.update(disposition='evidence-ready-unratified', nativeAPI='loadFromDirectory',
                filenameEvidence=filename_evidence(row, fixture, category, adaptations[row['id']]),
                notReplayedObservationChannels=[], rationale='Native complete bounded discovery then unsigned UTF-8 sorting determines which authored filename is attributed. Whole messages and observations remain separate; no shared mapping is counted.')
        else:
            require(row['operation'] in ['loadClasspath','loadClasspathResources'], 'Unknown carrier operation')
            expected_category = 'jvm-classpath-discovery' if row['operation']=='loadClasspath' else 'jvm-classpath-resource-resolution'
            require(category == expected_category and set(row['input']) <= ({'package'} if row['operation']=='loadClasspath' else {'resources'}), 'Carrier guard does not match authored input')
            controls = ['explicit-bundle-context','canonical-origins-and-exact-keys']
            if row['operation']=='loadClasspath':
                controls += ['bundle-missing-exact-directory','bundle-empty-directory','bundle-file-not-directory','bundle-literal-path-validation',
                    'bundle-has-no-jvm-reserved-namespace','bundle-discovery-nonrecursive','directory-invalid-filename-byte-order']
                native_api = 'loadFromBundle(directory:)'
                rationale = 'Caller-selected Apple Bundle directory replaces JVM package/root/JAR discovery. Literal Bundle path grammar, strict filename refusal and native discovery charges are explicit adaptations; classloader search and JAR overlay/warning behavior are not implemented.'
            else:
                require(isinstance(row['input'].get('resources'), dict), 'Explicit resource input must retain its authored map')
                controls += ['explicit-mapping-bypasses-filename-rules','explicit-lproj-remains-literal','mapping-repeated-resource-charges-bytes',
                    'mapping-no-discovery-charge','mapping-file-cap-before-validation-and-io','mapping-directory-refused',
                    'mapping-rendered-collision-before-io','warning-error-identity-and-reentry']
                native_api = 'loadFromResources / loadFromBundle(resourcePathsByLocale:)'
                rationale = 'Caller-resolved local URLs or exact Bundle-relative paths replace classloader names. Typed locale keys, literal path validation, regular-file refusal and canonical provenance preserve native obligations without replaying classloader normalization, root lookup, directory listings or donor map-key collapse.'
            record.update(disposition='platform-specific-informational',nativeAPI=native_api,nativeControls=sorted(controls),rationale=rationale,
                requestedCarrier={'fixtureID':row['fixture'],'input':row['input'],'loadingOptions':fixture['loadingOptions'],
                    'authoredFilenames':sorted(set(fixture['files'])|set(fixture['rawFiles'])|set(fixture['rawFilesBase64']),key=lambda x:x.encode('utf8'))},
                notReplayedObservationChannels=['load.'+key for key in sorted(row['expected']['load'])])
        records.append(record)
    ids = [row['id'] for row in records]
    require(len(ids)==164 and ids==sorted(set(ids)), 'Pending local disposition inventory changed')
    require(Counter(r['operation'] for r in records)=={'load':5,'loadClasspath':90,'loadClasspathResources':69}, 'Changed carrier populations')
    return {'formatVersion':1,'scope':'native-local-loader-dispositions','status':'qualified-not-certified',
        'releaseParity':False,'nativeMappingsRatified':False,'runtimePassedAdded':[],'nativeRepresentationMapped':[],
        'pendingIDs':ids,'pendingIDsSHA256':sha(''.join(i+'\n' for i in ids).encode()),'records':records,
        'materializedFixtureArchiveSHA256':sha(canonical(materialized)), 'evidence':evidence,'limits':LIMITS}


def check_report(actual, expected): require(canonical(actual)==canonical(expected), 'Loader dossier is altered, incomplete or stale')


def negative_controls(expected):
    rejected=[]
    def edit(name, mutate, evidence=False):
        value=copy.deepcopy(expected['evidence'] if evidence else expected);mutate(value)
        try:
            if evidence: dossier(value)
            else: check_report(value,expected)
        except (ValueError,RuntimeError,KeyError,TypeError): rejected.append(name)
        else: raise ValueError('Altered loader evidence passed: '+name)
    for name, mutate in [
        ('missing-case',lambda d:d['records'].pop()),('duplicated-case',lambda d:d['records'].append(d['records'][0])),
        ('invented-runtime-pass',lambda d:d['runtimePassedAdded'].append(d['pendingIDs'][0])),
        ('invented-ratification',lambda d:d.update(nativeMappingsRatified=True)),('invented-release-parity',lambda d:d.update(releaseParity=True)),
        ('changed-input-fingerprint',lambda d:d['records'][0].update(inputSHA256='0'*64)),
        ('changed-reference-fingerprint',lambda d:d['records'][0].update(referenceObservationSHA256='0'*64)),
        ('wrong-native-carrier',lambda d:d['records'][0].update(nativeAPI='loadClasspath')),
        ('omitted-unreplayed-channel',lambda d:next(r for r in d['records'] if r['operation']=='loadClasspath')['notReplayedObservationChannels'].pop()),
        ('unknown-field',lambda d:d.update(trusted=True)),('omitted-limits',lambda d:d.update(limits=[])),
    ]:edit(name,mutate)
    for name, mutate in [
        ('stale-library-source',lambda d:d['sourceFiles'][0].update(sha256='0'*64)),
        ('source-changed-during-run',lambda d:d.update(sourceInputsRevalidated=False)),
        ('compilation-failed',lambda d:d['compilation'][0].update(exitCode=1)),
        ('execution-failed',lambda d:d.update(boundaryExecutionExitCode=1)),
        ('missing-control',lambda d:d['nativeBoundaryReport']['passed'].pop()),
        ('duplicate-control',lambda d:d['nativeBoundaryReport']['passed'].append(CONTROL_IDS[0])),
        ('missing-control-observation',lambda d:d['nativeBoundaryReport']['observations'].pop(CONTROL_IDS[0])),
        ('unknown-evidence-field',lambda d:d.update(trusted=True)),
    ]:edit(name,mutate,True)
    for name, change in [('unrelated-native-message',lambda load:load.update(failureMessage='some refusal')),
                         ('wrong-authored-native-filename',lambda load:load.update(failureMessage=load['failureMessage'].replace('notes.json','zz.json'))),
                         ('changed-warning-channel',lambda load:load.update(warnings=[{'unexpected':True}]))]:
        def mutate(d,change=change):
            obs=next(o for o in d['loaderReport']['adaptationObservations'] if o['id']=='classpath-filenames.warn.two-invalid-json-filesystem')
            value=json.loads(obs['nativeObservationJSON']);change(value['load']);obs['nativeObservationJSON']=json.dumps(value)
        edit(name,mutate,True)
    for name, identifier, old, new in [
        ('file-cap-wrong-filename', 'loading-limits.files.one-rejects-a-second-file', '/fr:', '/en:'),
        ('file-cap-wrong-limit', 'loading-limits.files.one-rejects-a-second-file', 'limit of 1', 'limit of 2'),
        ('duplicate-wrong-filename', 'manifest-loads.load.two-filename-spellings-of-one-locale-collide', '/en.json', '/en'),
    ]:
        def mutate(d, identifier=identifier, old=old, new=new):
            obs=next(o for o in d['loaderReport']['adaptationObservations'] if o['id']==identifier)
            value=json.loads(obs['nativeObservationJSON'])
            require(old in value['load']['failureMessage'], 'Negative control does not alter its intended boundary')
            value['load']['failureMessage']=value['load']['failureMessage'].replace(old,new)
            obs['nativeObservationJSON']=json.dumps(value)
        edit(name,mutate,True)
    return rejected


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--qualify',action='store_true');mode.add_argument('--report-check',type=Path)
    parser.add_argument('--report',type=Path);parser.add_argument('--negative-controls',action='store_true');args=parser.parse_args()
    try:
        baseline_check(ROOT/'Reference')
        if args.qualify: expected=dossier(qualify())
        else:
            actual=read(args.report_check);expected=dossier(actual['evidence']);check_report(actual,expected)
        rejected=negative_controls(expected) if args.negative_controls else []
        if args.report:
            args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(expected,ensure_ascii=False,sort_keys=True,indent=2)+'\n')
        print(json.dumps({'status':expected['status'],'casesWithDispositions':164,'informationalJVMCarriers':159,'nativeFilenameObservations':5,
            'nativeBoundaryControls':len(CONTROL_IDS),'runtimePassedAdded':0,'nativeMappingsRatified':False,'rejectedControls':rejected}))
        return 0
    except (ValueError,RuntimeError,KeyError,TypeError,OSError) as error:
        print(json.dumps({'status':'error','error':str(error)}));return 1


if __name__=='__main__':raise SystemExit(main())
