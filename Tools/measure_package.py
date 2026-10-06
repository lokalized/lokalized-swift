#!/usr/bin/env python3
"""Measure source-only optimized SwiftPM consumers and public runtime workloads.

Deterministic source/data byte caps are portable. Binary caps are qualified only
for a measured compiler/SDK/architecture profile. Timings and memory are reported,
never pass/fail performance thresholds. Uses Python's standard library only.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

from verify_package import binary_check, package_check

ROOT = Path(__file__).resolve().parents[1]
BUDGETS = ROOT/'Reference/package-size-budgets.json'
HARNESS = ROOT/'Tools/Fixtures/PerformanceConsumer.swift'
WORKLOADS = {'cold-start':(1,10), 'catalog-1000':(1,1000), 'catalog-10000':(1,10000),
    'lookup-plain':(20000,200000), 'lookup-fallback':(10000,100000), 'plural-integer':(10000,30000),
    'plural-double':(2000,10000), 'plural-double-pi':(2000,10000), 'plural-double-max':(1000,5000),
    'plural-decimal':(10000,50000), 'generated-32768':(100,3276800),
    'idna-manifest':(200,200*len('https://xn--bcher-kva.example/catalogs/en.json'))}
PLURAL = '{"items":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one","CARDINALITY_OTHER":"other"}}}}}'
LIMITS = [
    'Fresh optimized consumer builds use current source copies without Reference, sibling repositories, plugins or external packages; installed Apple SDK caches are warmed, not flushed.',
    'Automatic SwiftPM product linking and stripped consumer sizes include the benchmark driver. The difference from the empty control is not an exact library-only or iOS app size.',
    'Each workload sample starts a fresh process. Warm lookup loops follow twenty excluded lookups and include output/status validation and checksum accumulation.',
    'Catalog input creation precedes parse timing; retained parsed models/runtime objects participate in live malloc snapshots. These are live requested bytes, not allocation counts or total application memory.',
    'Darwin peak RSS includes driver/SDK/runtime and input creation, is measured before JSON reporting, and is not the library incremental memory footprint.',
    'Timing/memory observations are machine/toolchain-specific and have no noisy latency thresholds. No old-OS/iOS/Intel/minimum-compiler runtime or release parity is inferred.']


def canonical(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def sha(value):return hashlib.sha256(value).hexdigest()
def require(value,message):
    if not value:raise ValueError(message)


def unique(items):
    d={}
    for k,v in items:
        require(k not in d,'Duplicate JSON member '+k);d[k]=v
    return d


def read(path):return json.loads(Path(path).read_text(),object_pairs_hook=unique)


def snapshot():
    paths=sorted((ROOT/'Sources/Lokalized').rglob('*'))
    paths=[p for p in paths if p.is_file()]+[ROOT/'Package.swift',ROOT/'LICENSE',HARNESS,ROOT/'Tools/measure_package.py']
    return [{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in paths]


def source_sizes(files):
    runtime=[f for f in files if f['path'].startswith('Sources/Lokalized/') and f['path'].endswith('.swift')]
    generated=[f for f in runtime if f['path'].startswith('Sources/Lokalized/Data/')]
    # SwiftPM treats .docc catalogs as documentation inputs, not runtime resources.
    # Keep their hashes in the source receipt without charging the resource cap.
    resources=[f for f in files if f['path'].startswith('Sources/Lokalized/') and not f['path'].endswith('.swift')
               and not any(part.endswith('.docc') for part in Path(f['path']).parts)]
    return {'runtimeSwiftBytes':sum(f['bytes'] for f in runtime),'generatedSwiftBytes':sum(f['bytes'] for f in generated),
        'runtimeSwiftFiles':len(runtime),'generatedFiles':[{k:f[k] for k in ['path','bytes','sha256']} for f in generated],
        'runtimeResourceBytes':sum(f['bytes'] for f in resources),'runtimeResources':resources}


def source_check(budgets,sizes):
    require(set(budgets)=={'formatVersion','scope','sourceByteCaps','artifactProfiles','policy'},'Unknown size budget fields')
    require(budgets['formatVersion']==1 and budgets['scope']=='native-package-size-budgets','Wrong size budget version/scope')
    require(set(budgets['sourceByteCaps'])=={'runtimeSwiftBytes','generatedSwiftBytes','runtimeResourceBytes'},'Incomplete source caps')
    for name,cap in budgets['sourceByteCaps'].items():
        require(type(cap)is int and cap>0 and sizes[name]<=cap,'Source size budget exceeded: '+name)


def expected_input(mode):
    if mode in ('cold-start','lookup-plain','lookup-fallback'):return b'{"hello":"Hello {{name}}!"}'
    if mode.startswith('plural-'):return PLURAL.encode()
    if mode.startswith('catalog-'):
        count=int(mode.split('-')[1]);return ('{'+','.join('"K'+str(i)+'":"Value'+str(i)+' {{name}}"' for i in range(count))+'}').encode()
    if mode=='generated-32768':return ('{"k":{"translation":"'+'{{leaf}}'*256+'","placeholders":{"leaf":{"translation":"'+'v'*128+'"}}}}').encode()
    if mode=='idna-manifest':return 'https://bücher.example/catalogs/'.encode()
    raise ValueError('Unknown workload')


def observation_check(row,mode):
    require(set(row)==set('workload iterations inputBytes inputSHA256 checksum durationNs liveMallocDeltaBytes peakResidentBytes budgetRefusalChecked'.split()),'Unknown workload observation fields')
    require(row['workload']==mode and type(row['iterations'])is int and row['iterations']==WORKLOADS[mode][0]
        and type(row['checksum'])is int and row['checksum']==WORKLOADS[mode][1], 'Workload outcome/checksum differs: '+mode)
    data=expected_input(mode)
    require(row['inputBytes']==len(data) and row['inputSHA256']==sha(data),'Workload input differs: '+mode)
    required_times={'cold-start':{'total','localeFirstUse','parse','construct','firstLookup'},
        'catalog-1000':{'parse','construct','firstLookup'},'catalog-10000':{'parse','construct','firstLookup'},
        'idna-manifest':{'firstUse','repeated'}}.get(mode,{'repeated'})
    required_memory={'cold-start':{'total'},'catalog-1000':{'parse','construct'},'catalog-10000':{'parse','construct'},
        'idna-manifest':{'firstUse','repeated'}}.get(mode,{'repeated'})
    require(set(row['durationNs'])==required_times and all(type(n)is int and n>0 for n in row['durationNs'].values()),'Missing/invalid timing sample')
    require(set(row['liveMallocDeltaBytes'])==required_memory and all(type(n)is int for n in row['liveMallocDeltaBytes'].values()),'Missing/invalid live malloc sample')
    require(type(row['peakResidentBytes'])is int and row['peakResidentBytes']>0,'Missing Darwin memory sample')
    require(row['budgetRefusalChecked'] is (mode=='generated-32768'),'Generated output-budget refusal was not checked')


def invoke(args,cwd=None,environment=None):
    start=time.perf_counter_ns();result=subprocess.run(args,cwd=cwd,env=environment,capture_output=True,text=True)
    duration=time.perf_counter_ns()-start
    require(result.returncode==0,f'{args} failed ({result.returncode}): {result.stderr[-6000:]}')
    return result,duration


def measure(samples,track):
    require(platform.system()=='Darwin','Measurement requires Apple SDK/Darwin statistics')
    inputs=snapshot();package=package_check(track)
    compiler=package['compiler'];sdk=invoke(['xcrun','--sdk','macosx','--show-sdk-version'])[0].stdout.strip()
    build_samples=[];observations={name:[] for name in WORKLOADS};artifacts=[]
    with tempfile.TemporaryDirectory(prefix='lokalized-package-measure-',dir='/private/tmp') as temporary:
        scratch=Path(temporary);copied=scratch/'Package';copied.mkdir()
        import shutil
        for name in ['Package.swift','LICENSE']:shutil.copy2(ROOT/name,copied/name)
        shutil.copytree(ROOT/'Sources',copied/'Sources')
        consumer=scratch/'Consumer';(consumer/'Sources/BenchmarkConsumer').mkdir(parents=True)
        (consumer/'Sources/EmptyConsumer').mkdir(parents=True)
        (consumer/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "PackageMeasure", platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [.package(path: "../Package")], targets: [
      .executableTarget(name: "BenchmarkConsumer", dependencies: [.product(name: "Lokalized", package: "package")]),
      .executableTarget(name: "EmptyConsumer")], swiftLanguageModes: [.v6])
''')
        (consumer/'Sources/BenchmarkConsumer/main.swift').write_bytes(HARNESS.read_bytes())
        (consumer/'Sources/EmptyConsumer/main.swift').write_text('import Foundation\nprint("empty consumer")\n')
        environment=os.environ.copy();environment['CLANG_MODULE_CACHE_PATH']=str(scratch/'sdk-cache')
        environment['SWIFTPM_MODULECACHE_OVERRIDE']=str(scratch/'sdk-cache')
        def build(product,directory):
            args=['swift','build','--disable-sandbox','--scratch-path',str(directory),'--cache-path',str(scratch/'spm-cache'),
                '--config-path',str(scratch/'spm-config'),'--security-path',str(scratch/'spm-security'),
                '-c','release','--product',product,'-Xswiftc','-module-cache-path','-Xswiftc',str(scratch/'sdk-cache')]
            result,duration=invoke(args,consumer,environment)
            path=Path(invoke(args+['--show-bin-path'],consumer,environment)[0].stdout.strip())/product
            return path,duration,result.stderr
        def size(path):
            stripped=path.with_name(path.name+'-stripped');shutil.copy2(path,stripped)
            invoke(['xcrun','strip','-S','-x',str(stripped)])
            return {'unstrippedBytes':path.stat().st_size,'strippedBytes':stripped.stat().st_size,
                'unstrippedSHA256':sha(path.read_bytes()),'strippedSHA256':sha(stripped.read_bytes())}
        empty,empty_build_ns,_=build('EmptyConsumer',scratch/'EmptyBuild')
        empty_size=size(empty)
        for sample in range(samples):
            print(f'Optimized source-only build {sample+1}/{samples}',flush=True)
            binary,duration,diagnostics=build('BenchmarkConsumer',scratch/f'Build{sample}')
            build_samples.append({'durationNs':duration,'exitCode':0,'diagnostics':diagnostics})
            floor=binary_check(binary,'macos')
            architecture=invoke(['xcrun','lipo','-archs',str(binary)])[0].stdout.strip()
            resource_files=list(binary.parent.rglob('PrivacyInfo.xcprivacy'))
            expected_privacy=sha((ROOT/'Sources/Lokalized/PrivacyInfo.xcprivacy').read_bytes())
            require(len(resource_files)==1 and sha(resource_files[0].read_bytes())==expected_privacy,'Packaged privacy resource missing/altered')
            artifacts.append({'binary':size(binary),'floor':floor,'architecture':architecture,'privacyResourceSHA256':expected_privacy})
            for mode in WORKLOADS:
                result,_=invoke([str(binary),mode]);row=json.loads(result.stdout,object_pairs_hook=unique)
                observation_check(row,mode);observations[mode].append(row)
        profile=sha(canonical({'compiler':compiler,'sdk':sdk,'architecture':artifacts[0]['architecture']}))
    require(snapshot()==inputs,'Measured inputs changed during builds/execution')
    return {'formatVersion':1,'scope':'native-package-size-performance','status':'measured-not-certified','releaseParity':False,
        'measuredAtUTC':datetime.now(timezone.utc).isoformat(),'compiler':compiler,'sdkVersion':sdk,'hostOS':platform.platform(),
        'architecture':platform.machine(),'compilerTrack':track,'minimumCompilerExecuted':package['minimumCompilerExecuted'],
        'sourceFiles':inputs,'sourceManifestSHA256':sha(canonical(inputs)),'sourceInputsRevalidated':True,'sourceSizes':source_sizes(inputs),
        'externalPackageDependencies':0,'freshConsumerReferenceArtifacts':False,'buildConfiguration':'release','samples':samples,
        'emptyConsumer':{'buildNs':empty_build_ns,'size':empty_size},'buildSamples':build_samples,'artifacts':artifacts,
        'artifactProfile':profile,'workloads':observations,'limits':LIMITS}


def initialize_budgets(report):
    require(not BUDGETS.exists(),'Budgets already exist; edit reviewed caps explicitly instead of silently replacing them')
    def rounded(n,unit):return math.ceil(n/unit)*unit
    budgets={'formatVersion':1,'scope':'native-package-size-budgets',
        'sourceByteCaps':{key:rounded(report['sourceSizes'][key],65536 if key!='runtimeResourceBytes' else 4096)
            for key in ['runtimeSwiftBytes','generatedSwiftBytes','runtimeResourceBytes']},
        'artifactProfiles':{report['artifactProfile']:{'compiler':report['compiler'],'sdkVersion':report['sdkVersion'],
            'architecture':report['artifacts'][0]['architecture'],
            'maximumStrippedConsumerBytes':rounded(math.ceil(max(a['binary']['strippedBytes'] for a in report['artifacts'])*1.10),65536)}},
        'policy':'Source caps round observed bytes to the next 64 KiB (resources 4 KiB). Measured profile binary cap adds 10% then rounds to 64 KiB. Other compiler/SDK/architecture profiles report sizes without a binary cap until measured. No timing or memory gate.'}
    BUDGETS.write_text(json.dumps(budgets,indent=2,sort_keys=True)+'\n')


def report_check(report,budgets):
    fields='formatVersion scope status releaseParity measuredAtUTC compiler sdkVersion hostOS architecture compilerTrack minimumCompilerExecuted sourceFiles sourceManifestSHA256 sourceInputsRevalidated sourceSizes externalPackageDependencies freshConsumerReferenceArtifacts buildConfiguration samples emptyConsumer buildSamples artifacts artifactProfile workloads limits'.split()
    require(set(report)==set(fields),'Unknown/missing measurement report fields')
    require(report['formatVersion']==1 and report['scope']=='native-package-size-performance' and report['status']=='measured-not-certified'
        and report['releaseParity']is False,'Measurement cannot certify parity')
    files=snapshot();require(report['sourceFiles']==files and report['sourceManifestSHA256']==sha(canonical(files))
        and report['sourceInputsRevalidated']is True,'Stale/incomplete source receipt')
    require(report['sourceSizes']==source_sizes(files),'Changed deterministic source inventory')
    source_check(budgets,report['sourceSizes'])
    require(report['externalPackageDependencies']==0 and report['freshConsumerReferenceArtifacts']is False and report['buildConfiguration']=='release','Incorrect consumer dependency/build scope')
    count=report['samples'];require(type(count)is int and 1<=count<=5,'Invalid measured sample count')
    require(set(report['workloads'])==set(WORKLOADS),'Workload inventory changed')
    for mode,rows in report['workloads'].items():
        require(isinstance(rows,list) and len(rows)==count,'Missing workload samples')
        for row in rows:observation_check(row,mode)
    require(len(report['buildSamples'])==count and all(set(s)=={'durationNs','exitCode','diagnostics'} and type(s['durationNs'])is int and s['durationNs']>0 and s['exitCode']==0 for s in report['buildSamples']),'Incomplete/failed optimized build')
    require(len(report['artifacts'])==count and report['limits']==LIMITS,'Missing artifacts/measurement limitations')
    for a in report['artifacts']:
        require(set(a)=={'binary','floor','architecture','privacyResourceSHA256'} and a['floor']['builtMinimumOS']=='12.0'
            and a['floor']['linkedTestFramework']is False and a['privacyResourceSHA256']==sha((ROOT/'Sources/Lokalized/PrivacyInfo.xcprivacy').read_bytes()),'Incorrect binary/resource evidence')
        require(set(a['binary'])=={'unstrippedBytes','strippedBytes','unstrippedSHA256','strippedSHA256'} and all(type(a['binary'][k])is int and a['binary'][k]>0 for k in ['unstrippedBytes','strippedBytes'])
            and a['binary']['strippedBytes']<=a['binary']['unstrippedBytes'],'Invalid artifact size')
    profile=sha(canonical({'compiler':report['compiler'],'sdk':report['sdkVersion'],'architecture':report['artifacts'][0]['architecture']}))
    require(report['artifactProfile']==profile,'Changed compiler/SDK/architecture profile')
    if profile in budgets['artifactProfiles']:
        cap=budgets['artifactProfiles'][profile]['maximumStrippedConsumerBytes']
        require(all(a['binary']['strippedBytes']<=cap for a in report['artifacts']),'Optimized artifact profile size cap exceeded')
    return {'sourceBudgetStatus':'passed','binaryBudgetStatus':'passed' if profile in budgets['artifactProfiles'] else 'unmeasured-profile',
        'medianBuildSeconds':statistics.median(s['durationNs'] for s in report['buildSamples'])/1e9,
        'medianStrippedConsumerBytes':statistics.median(a['binary']['strippedBytes'] for a in report['artifacts']),
        'workloads':{mode:{'medianDurationNs':{key:statistics.median(r['durationNs'][key] for r in rows) for key in rows[0]['durationNs']},
            'medianLiveMallocDeltaBytes':{key:statistics.median(r['liveMallocDeltaBytes'][key] for r in rows) for key in rows[0]['liveMallocDeltaBytes']},
            'medianPeakResidentBytes':statistics.median(r['peakResidentBytes'] for r in rows),'iterations':WORKLOADS[mode][0]} for mode,rows in report['workloads'].items()}}


def negative_controls(report,budgets):
    rejected=[]
    for name,mutate in [
        ('stale-source',lambda d:d['sourceFiles'][0].update(sha256='0'*64)),
        ('missing-workload',lambda d:d['workloads'].pop('plural-double')),
        ('wrong-output-checksum',lambda d:d['workloads']['lookup-plain'][0].update(checksum=1)),
        ('changed-catalog-input',lambda d:d['workloads']['catalog-10000'][0].update(inputSHA256='0'*64)),
        ('missing-budget-refusal',lambda d:d['workloads']['generated-32768'][0].update(budgetRefusalChecked=False)),
        ('failed-build',lambda d:d['buildSamples'][0].update(exitCode=1)),
        ('invented-parity',lambda d:d.update(releaseParity=True)),
        ('omitted-limits',lambda d:d.update(limits=[])),
    ]:
        value=copy.deepcopy(report);mutate(value)
        try:report_check(value,budgets)
        except (ValueError,KeyError,TypeError):rejected.append(name)
        else:raise ValueError('Damaged measurement passed: '+name)
    value=copy.deepcopy(budgets);value['sourceByteCaps']['generatedSwiftBytes']=report['sourceSizes']['generatedSwiftBytes']-1
    try:source_check(value,report['sourceSizes'])
    except ValueError:rejected.append('source-size-over-budget')
    else:raise ValueError('Exceeded source cap passed')
    return rejected


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--measure',action='store_true');mode.add_argument('--check',action='store_true');mode.add_argument('--report-check',type=Path)
    parser.add_argument('--report',type=Path);parser.add_argument('--samples',type=int,default=3);parser.add_argument('--compiler-track',choices=['current','minimum'],default='current')
    parser.add_argument('--initialize-budgets',action='store_true');parser.add_argument('--negative-controls',action='store_true');args=parser.parse_args()
    try:
        require(1<=args.samples<=5,'Samples must be 1 through 5')
        require(not args.initialize_budgets or args.measure,'Initial budget creation requires measured artifacts')
        report=measure(args.samples,args.compiler_track) if args.measure else read(args.report_check) if args.report_check else None
        if args.initialize_budgets:initialize_budgets(report)
        budgets=read(BUDGETS);source_check(budgets,source_sizes(snapshot()))
        summary=report_check(report,budgets) if report else {'sourceBudgetStatus':'passed'}
        require(not args.negative_controls or report is not None,'Report controls need measured evidence')
        rejected=negative_controls(report,budgets) if args.negative_controls else []
        if args.report:
            require(report is not None,'--report requires measurement or saved report');args.report.parent.mkdir(parents=True,exist_ok=True)
            args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
        print(json.dumps({'status':'measured-not-certified' if report else 'source-budgets-passed','summary':summary,'rejectedControls':rejected}))
        return 0
    except (ValueError,RuntimeError,KeyError,TypeError,OSError) as error:
        print(json.dumps({'status':'error','error':str(error)}));return 1


if __name__=='__main__':raise SystemExit(main())
