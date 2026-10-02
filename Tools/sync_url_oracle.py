#!/usr/bin/env python3
"""Verify or explicitly sync the shared URL oracle's frozen Swift development copy.

--check is offline and reads this checkout only. --check-source and --sync require
an explicit lokalized-spec directory. All source bytes are pinned and verified
before copying; neither operation runs a generator, oracle, resolver or Git.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Canonical spec path, Swift snapshot path, SHA-256 and exact byte count.
# Updating a profile is a reviewed change to these pins, not an automatic sync.
COPIES = [
    ('generated/url-oracle/manifest-idna-goldens.json.gz', 'Reference/manifest-idna-goldens.json.gz', '325a22caa753d399319dd0572d99f159042ca32acdae9548d5db87a628ba7603', 731845),
    ('tools/url_oracle/__init__.py', 'Tools/URLOracle/__init__.py', 'ca36072ae1a8bd2729c90fedb2176326c8a7e4bcbb43787f37319e07e108bca4', 78),
    ('tools/url_oracle/idna_corpus.py', 'Tools/URLOracle/idna_corpus.py', 'a73aea78e3351a651adecf6df39126c73076045d5c8aaa2f34b02a93c78b715a', 17422),
    ('tools/url_oracle/normalization_inputs.py', 'Tools/URLOracle/normalization_inputs.py', 'edae0ccb8c690548f408b19bac754f2494b334b84f3e52b73ec90c3a6a141f4e', 4848),
    ('tools/url_oracle/oracle_runtime.py', 'Tools/URLOracle/oracle_runtime.py', 'd59ffdbfc27e603869c5ca427e8560ee3171748b3bd1461ba44c2f492fe3f84c', 3188),
    ('tools/url_oracle/property_inputs.py', 'Tools/URLOracle/property_inputs.py', '3888740e1828ca393dc0ca14834b610fbd230c696b6be5396a37e3cdc499e2b5', 6858),
    ('tools/url_oracle/reference/IDNA-Compatibility/LICENSE-MIT.txt', 'Reference/IDNA-Compatibility/LICENSE-MIT.txt', 'af0d7d2cef91fc243cf4ad98570b03d1f26f5e0227cad0f5f4a7376e2feb3160', 1071),
    ('tools/url_oracle/reference/IDNA-Compatibility/normalization-profile.json', 'Reference/IDNA-Compatibility/normalization-profile.json', '9cb7782123a2f08f8a69a8ec702ff7910cff69cd03773e6d665d79ed5a4b327c', 234866),
    ('tools/url_oracle/reference/IDNA-Compatibility/oracle-runtime-lock.json', 'Reference/IDNA-Compatibility/oracle-runtime-lock.json', 'e0fa1af12b31b3750be894db9a892775b672e5d2577923b84e7c83154130cb1d', 2048),
    ('tools/url_oracle/reference/IDNA-Compatibility/property-profile.json', 'Reference/IDNA-Compatibility/property-profile.json', '84ae2c73b06823e54716dff80f7f539e588a676e7ff8529424046fe34f7a1098', 121910),
    ('tools/url_oracle/reference/Unicode-17.0.0/DerivedBidiClass.txt', 'Reference/Unicode-17.0.0/DerivedBidiClass.txt', '4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4', 173433),
    ('tools/url_oracle/reference/Unicode-17.0.0/DerivedJoiningType.txt', 'Reference/Unicode-17.0.0/DerivedJoiningType.txt', 'f39ebe974825d6736aee15582250307aa532b2cfab3caf3f86bd23fddc9c5c4d', 40635),
    ('tools/url_oracle/reference/Unicode-17.0.0/DerivedNormalizationProps.txt', 'Reference/Unicode-17.0.0/DerivedNormalizationProps.txt', '71fd6a206a2c0cdd41feb6b7f656aa31091db45e9cedc926985d718397f9e488', 1377582),
    ('tools/url_oracle/reference/Unicode-17.0.0/IdnaMappingTable.txt', 'Reference/Unicode-17.0.0/IdnaMappingTable.txt', '87f05505dc026fdb2bff16132bdc68a8014675836882a9a2b1844540ad3be382', 787378),
    ('tools/url_oracle/reference/Unicode-17.0.0/IdnaTestV2.txt', 'Reference/Unicode-17.0.0/IdnaTestV2.txt', 'beb5d0be20e896189b03209a82fdc34f06351502bbd4b8e2523583fc2954d9cf', 775973),
    ('tools/url_oracle/reference/Unicode-17.0.0/LICENSE.txt', 'Reference/Unicode-17.0.0/LICENSE.txt', 'e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96', 1995),
    ('tools/url_oracle/reference/Unicode-17.0.0/NormalizationTest.txt', 'Reference/Unicode-17.0.0/NormalizationTest.txt', '5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db', 2827429),
    ('tools/url_oracle/reference/Unicode-17.0.0/UnicodeData.txt', 'Reference/Unicode-17.0.0/UnicodeData.txt', '2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c', 2198209),
    ('tools/url_oracle/unicode_inputs.py', 'Tools/URLOracle/unicode_inputs.py', '04e06e02816fb41799f766bc407d683df4846d7f5b34fa90bff70e316d461350', 3580),
    ('generated/url-oracle/manifest-idna-lock.json', 'Reference/manifest-idna-lock.json', 'f6182c017be1f182f5f3ce64d394472e5f3b0c7c7b64ab212bac7dfef094e8e2', 4548),
]


def read_pinned(base, source):
    data = {}
    for original, local, pin, count in COPIES:
        path = base / (original if source else local)
        raw = path.read_bytes()
        if len(raw) != count or hashlib.sha256(raw).hexdigest() != pin:
            raise ValueError("Shared URL oracle snapshot differs: " + str(path))
        data[local] = raw
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--check-source", action="store_true")
    mode.add_argument("--sync", action="store_true")
    parser.add_argument("--source", type=Path, help="Canonical lokalized-spec checkout")
    args = parser.parse_args()
    if args.sync or args.check_source:
        if not args.source:
            parser.error("--sync/--check-source requires --source pointing to lokalized-spec")
        canonical = read_pinned(args.source.resolve(), source=True)
        if args.sync:
            for relative, raw in canonical.items():
                path = ROOT / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
    local = read_pinned(ROOT, source=False)
    if args.check_source and local != canonical:
        raise ValueError("Swift URL oracle snapshot differs from canonical spec bytes")
    print(json.dumps({"status": "passed", "sourceRepository": "lokalized-spec",
                      "artifacts": len(COPIES), "mode": "synced" if args.sync else "source-check" if args.check_source else "offline-check"}, indent=2))


if __name__ == "__main__":
    main()
