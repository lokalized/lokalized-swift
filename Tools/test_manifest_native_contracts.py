#!/usr/bin/env python3
"""Verify offline snapshot independence and compiler-diagnostic refusal paths."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import sync_manifest_contracts as sync
import verify_manifest_types as types
import verify_manifest_native_contracts as native
from ManifestContracts import native_policy as policy

ROOT=Path(__file__).resolve().parents[1]


class ManifestNativeTests(unittest.TestCase):
    def test_host_observation_control_targets_the_actual_architecture(self):
        triples = ['arm64-apple-macosx12.0', 'x86_64-apple-macosx12.0']
        for host in triples:
            with self.subTest(host=host):
                # Match the real deployment shape: every target carries the
                # field, but only the executing host carries an object there.
                evidence = {'compiler': {'target': host}, 'deployment': {'targets': [
                    {'triple': triple, 'runtimeExecution':
                        {'manifestContract': {'runtimePassed': ['first', 'second']}}
                        if triple == host else 'not executed'} for triple in triples]}}
                native.corrupt_host_observation(evidence)
                for target in evidence['deployment']['targets']:
                    if target['triple'] == host:
                        self.assertEqual(target['runtimeExecution']['manifestContract']['runtimePassed'], ['first'])
                    else:
                        self.assertEqual(target['runtimeExecution'], 'not executed')

    def test_snapshot_and_profile_are_complete_offline(self):
        self.assertEqual(len(sync.read_pinned(ROOT)),14)
        profile=policy.read(ROOT/'Reference/swift-manifest-v1.json')
        cases=policy.read(ROOT/'Reference/manifest-contract-vectors.json')['cases']
        policy.check_profile(profile,cases)

    def test_unrelated_errors_and_unicode_recovery_without_primary_are_refused(self):
        self.assertFalse(types.diagnostics_match("error: cannot find 'String' in scope",'type','String'))
        self.assertFalse(types.diagnostics_match("error: missing argument for parameter 'catalogVersion' in call",'unicode','unicode scalar'))
        self.assertFalse(types.diagnostics_match("error: invalid unicode scalar\nerror: cannot find 'ExactString' in scope",'unicode','unicode scalar'))
        self.assertTrue(types.diagnostics_match("error: invalid unicode scalar\nerror: missing argument for parameter 'catalogVersion' in call",'unicode','unicode scalar'))

    def test_corrupt_source_refused_before_any_sync_write(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for original,local,_,_ in sync.COPIES:
                path=root/original;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes((ROOT/local).read_bytes())
            (root/sync.COPIES[-1][0]).write_bytes(b'corrupt')
            before=sync.read_pinned(ROOT)
            result=subprocess.run(['python3',str(ROOT/'Tools/sync_manifest_contracts.py'),'--sync','--source',str(root)],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(sync.read_pinned(ROOT),before)

    def test_isolated_snapshot_needs_no_sibling_or_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for _,local,_,_ in sync.COPIES:
                path=root/local;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes((ROOT/local).read_bytes())
            for relative in ['Tools/sync_manifest_contracts.py','Tools/manifest_contract.py','Reference/behavioral-vectors.json']:
                target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/relative,target)
            for command in [['Tools/sync_manifest_contracts.py','--check'],['Tools/manifest_contract.py','--check']]:
                result=subprocess.run(['python3',str(root/command[0]),*command[1:]],capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)

    def test_corrupt_local_fixture_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for _,local,_,_ in sync.COPIES:
                path=root/local;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes((ROOT/local).read_bytes())
            path=root/'Reference/manifest-contract-vectors.json';path.write_bytes(path.read_bytes()+b' ')
            with self.assertRaises(ValueError):sync.read_pinned(root)


if __name__=='__main__':unittest.main()
