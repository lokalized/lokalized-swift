#!/usr/bin/env python3
"""Create/check a deterministic archive of the current source tree without Git.

Python standard library only. This is a local distribution rehearsal, not a
release publisher. The allowlist includes development inputs so the original
Package.swift, qualification tools and examples remain usable after extraction.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "lokalized-swift"
ROOT_FILES = {"Package.swift", "README.md", "LICENSE", "NOTICE", "THIRD-PARTY-NOTICES.md",
              ".gitignore", ".gitattributes"}
DIRECTORIES = {"Sources", "Tests", "Reference", "Tools", "Documentation", "Examples",
               "Licenses", ".github"}
EXCLUDED = {".git", ".build", ".swiftpm", "__pycache__", "node_modules", "xcuserdata",
            ".DS_Store", "Package.resolved"}
LICENSE_PINS = {
    "Unicode-CLDR-48.2.txt": "88865ffe4dc18bface3cf86d0c6080f924d3415d64f5098cd985cfd8a5bc52bd",
    "Unicode-15.0.md": "6f72f10d166b2c2e8a395e03e734c5afc852b59aeca73ced124f6b9c96268d53",
    "Unicode-17.0.0.txt": "e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96",
    "Ada-MIT.txt": "af0d7d2cef91fc243cf4ad98570b03d1f26f5e0227cad0f5f4a7376e2feb3160",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def excluded(path):
    return any(part in EXCLUDED for part in path.parts) or path.suffix in {".pyc", ".pyo"}


def notices_check(root):
    """Check the complete independently pinned data notices, without Reference/."""
    for name in ("LICENSE", "NOTICE", "THIRD-PARTY-NOTICES.md"):
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.read_bytes():
            raise ValueError(f"Missing/nonregular distribution notice: {name}")
    if "Apache License" not in (root / "LICENSE").read_text():
        raise ValueError("Missing Apache project license")
    notices = (root / "THIRD-PARTY-NOTICES.md").read_text()
    for name, expected in LICENSE_PINS.items():
        path = root / "Licenses" / name
        if path.is_symlink() or not path.is_file() or sha(path.read_bytes()) != expected:
            raise ValueError(f"Missing/changed complete third-party license: {name}")
        if f"Licenses/{name}" not in notices:
            raise ValueError(f"Third-party notices do not reference {name}")
    if "IANA Language Subtag Registry" not in notices or "2026-09-17" not in notices:
        raise ValueError("Missing pinned IANA attribution")
    return {"project": "Apache-2.0", "completeDataLicenseSHA256": LICENSE_PINS,
            "ianaRegistryFileDate": "2026-09-17"}


def source_files(root):
    notices_check(root)
    paths = []
    for name in sorted(ROOT_FILES | DIRECTORIES):
        base = root / name
        if base.is_symlink() or not base.exists():
            raise ValueError(f"Missing/symlinked source-package input: {name}")
        if name in ROOT_FILES:
            paths.append(base)
        else:
            if not base.is_dir():
                raise ValueError(f"Expected source-package directory: {name}")
            paths.extend(base.rglob("*"))
    result = {}
    for path in sorted(paths):
        relative = path.relative_to(root)
        if excluded(relative):
            continue
        if path.is_symlink():
            raise ValueError(f"Symlinks are not source-package inputs: {relative}")
        mode = path.stat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError(f"Nonregular source-package input: {relative}")
        data = path.read_bytes()
        result[relative.as_posix()] = {"bytes": len(data), "sha256": sha(data),
                                      "mode": 0o755 if mode & 0o111 else 0o644}
    required = {"Sources/Lokalized/PrivacyInfo.xcprivacy", "Reference/manifest-idna-goldens.json.gz"}
    if not required <= result.keys():
        raise ValueError("Missing privacy declaration or compressed IDNA development archive")
    if "Reference/manifest-idna-goldens.json" in result:
        raise ValueError("Uncompressed IDNA archive must not enter a source distribution")
    return result


def inventory_sha(files):
    return sha(json.dumps(files, sort_keys=True, separators=(",", ":")).encode())


def create_archive(root, archive):
    files = source_files(root)
    output_relative = None
    try:
        output_relative = archive.resolve().relative_to(root.resolve())
    except ValueError:
        pass
    if output_relative and (output_relative.parts[0] in DIRECTORIES or output_relative.as_posix() in ROOT_FILES):
        raise ValueError("Archive output must be outside the packaged input paths")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with archive.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT) as tar:
                for name, record in files.items():
                    data = (root / name).read_bytes()
                    if sha(data) != record["sha256"]:
                        raise ValueError(f"Source changed during packaging: {name}")
                    info = tarfile.TarInfo(f"{PREFIX}/{name}")
                    info.size, info.mode, info.mtime = len(data), record["mode"], 0
                    tar.addfile(info, io.BytesIO(data))
    if source_files(root) != files:
        raise ValueError("Source changed during packaging")
    check_archive(archive, files)
    return {"path": str(archive.resolve()), "bytes": archive.stat().st_size,
            "sha256": sha(archive.read_bytes()), "files": files,
            "inputInventorySHA256": inventory_sha(files), "fileCount": len(files),
            "uncompressedFileBytes": sum(record["bytes"] for record in files.values())}


def check_archive(archive, expected, destination=None):
    """Validate every member before extracting; never use tarfile.extractall."""
    contents = {}
    with tarfile.open(archive, mode="r:gz") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or path.as_posix() != member.name
                    or len(path.parts) < 2 or path.parts[0] != PREFIX):
                raise ValueError(f"Unsafe archive member: {member.name}")
            name = PurePosixPath(*path.parts[1:]).as_posix()
            record = expected.get(name)
            if name in contents or record is None or not member.isfile() or member.issparse():
                raise ValueError(f"Duplicate/unexpected/nonregular archive member: {name}")
            if (member.size != record["bytes"] or member.mode != record["mode"]
                    or member.uid != 0 or member.gid != 0 or member.mtime != 0
                    or member.uname or member.gname):
                raise ValueError(f"Archive metadata differs: {name}")
            with tar.extractfile(member) as stream:
                data = stream.read()
            if sha(data) != record["sha256"]:
                raise ValueError(f"Archive content differs: {name}")
            contents[name] = data
    if set(contents) != set(expected):
        raise ValueError("Archive silently omitted source-package inputs")
    if destination is not None:
        if destination.exists():
            raise ValueError("Extraction destination must be fresh")
        destination.mkdir(parents=True)
        for name, data in contents.items():
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(expected[name]["mode"])
        notices_check(destination)
    return {"status": "verified", "fileCount": len(contents),
            "inputInventorySHA256": inventory_sha(expected)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-check", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if sum((args.check, args.archive is not None, args.archive_check is not None)) != 1:
        parser.error("Choose exactly one of --check, --archive or --archive-check")
    files = source_files(ROOT)
    result = {"scope": "current-tree-source-distribution", "status": "passed", "releaseParity": False,
              "notices": notices_check(ROOT), "fileCount": len(files),
              "inputInventorySHA256": inventory_sha(files)}
    if args.archive:
        result["archive"] = create_archive(ROOT, args.archive)
    if args.archive_check:
        result["archiveCheck"] = check_archive(args.archive_check, files)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    # The full per-file inventory is retained in the report, not dumped to the terminal.
    print(json.dumps({k: v for k, v in result.items() if k != "archive"}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f"Source packaging refused: {error}", file=sys.stderr)
        sys.exit(1)
