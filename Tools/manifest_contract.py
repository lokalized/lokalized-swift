#!/usr/bin/env python3
"""Check the pinned shared manifest snapshot offline; refresh in lokalized-spec."""
from pathlib import Path
import sys
from ManifestContracts import archive

if __name__ == "__main__":
    if "--refresh" in sys.argv:
        raise SystemExit("Refresh canonical observations with lokalized-spec/tools/check-manifest-contract.py; then review pins and sync.")
    archive.configure(Path(__file__).resolve().parents[1] / "Reference")
    archive.main()
