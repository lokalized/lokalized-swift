#!/usr/bin/env python3
"""Exercise the offline shared snapshot and source-bound coverage refusal paths."""
import copy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import sync_native_contracts as sync
from NativeAdaptations import contract

ROOT = Path(__file__).resolve().parents[1]


class NativeContractTests(unittest.TestCase):
    def test_shared_snapshot_is_complete_and_offline(self):
        self.assertEqual(len(sync.read_pinned(ROOT)), 4)
        profile = contract.read(ROOT/'Reference/swift-native-v1.json')
        contract.check_profile(profile, contract.read_corpus(ROOT/'Reference/behavioral-vectors.json'))

    def test_local_corruption_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for relative, raw in sync.read_pinned(ROOT).items():
                path = root/relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
            path = root/'Reference/swift-native-v1.json'
            path.write_bytes(path.read_bytes()+b'\n')
            with self.assertRaises(ValueError):
                sync.read_pinned(root)

    def test_bad_source_is_refused_before_any_sync_write(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for source, local, _, _ in sync.COPIES:
                path = root/source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT/local).read_bytes())
            (root/sync.COPIES[-1][0]).write_bytes(b'broken')
            before = sync.read_pinned(ROOT)
            result = subprocess.run(['python3', str(ROOT/'Tools/sync_native_contracts.py'), '--sync', '--source', str(root)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sync.read_pinned(ROOT), before)

    def test_snapshot_checks_need_no_port_compiler_or_siblings(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for source, local, _, _ in sync.COPIES:
                path = root/local
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT/local).read_bytes())
            shutil.copy2(ROOT/'Tools/sync_native_contracts.py', root/'Tools/sync_native_contracts.py')
            result = subprocess.run(['python3', str(root/'Tools/sync_native_contracts.py'), '--check'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_profile_does_not_count_jvm_carriers_as_native_adaptations(self):
        profile = contract.read(ROOT/'Reference/swift-native-v1.json')
        corpus = contract.read_corpus(ROOT/'Reference/behavioral-vectors.json')
        changed = copy.deepcopy(profile)
        row = next(r for r in changed['records'] if r['kind'] == 'informational-jvm-carrier')
        row['kind'] = 'nonoptional-api-boundary'
        with self.assertRaises(ValueError):
            contract.check_profile(changed, corpus)


if __name__ == '__main__':
    unittest.main()
