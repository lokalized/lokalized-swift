#!/usr/bin/env python3
"""Offline source-distribution controls; no Swift build or third-party packages."""
import io
from pathlib import Path
import shutil
import tarfile
import tempfile
import unittest

import source_package as packaging


class SourcePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lokalized-source-controls-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "Source"
        self.root.mkdir()
        for name in packaging.ROOT_FILES:
            shutil.copy2(packaging.ROOT / name, self.root / name)
        for name in packaging.DIRECTORIES:
            (self.root / name).mkdir()
            (self.root / name / ".keep").write_text("fixture-directory\n")
        shutil.copytree(packaging.ROOT / "Licenses", self.root / "Licenses", dirs_exist_ok=True)
        (self.root / "Sources/Lokalized").mkdir()
        (self.root / "Sources/Lokalized/PrivacyInfo.xcprivacy").write_text("privacy-control")
        (self.root / "Sources/Lokalized/API.swift").write_text("public let fixture = 1\n")
        (self.root / "Reference/manifest-idna-goldens.json.gz").write_bytes(b"compressed-control")
        self.archive = self.base / "source.tar.gz"

    def make_archive(self):
        return packaging.create_archive(self.root, self.archive)["files"]

    def rewrite(self, transform):
        with tarfile.open(self.archive, "r:gz") as tar:
            rows = [(member, tar.extractfile(member).read()) for member in tar]
        rows = transform(rows)
        with tarfile.open(self.archive, "w:gz", format=tarfile.PAX_FORMAT) as tar:
            for member, data in rows:
                tar.addfile(member, io.BytesIO(data))

    def test_deterministic_roundtrip_preserves_sources_notices_and_modes(self):
        path = self.root / "Tools/script.py"
        path.write_text("#!/usr/bin/env python3\n")
        path.chmod(0o755)
        first = packaging.create_archive(self.root, self.archive)
        second = packaging.create_archive(self.root, self.base / "second.tar.gz")
        self.assertEqual(first["sha256"], second["sha256"])
        destination = self.base / "Extracted"
        packaging.check_archive(self.archive, first["files"], destination)
        self.assertEqual(packaging.source_files(destination), first["files"])
        self.assertEqual((destination / "Tools/script.py").stat().st_mode & 0o777, 0o755)

    def test_caches_and_resolver_files_do_not_enter_archive(self):
        before = packaging.source_files(self.root)
        for name in ("Sources/.DS_Store", "Tools/__pycache__/old.pyc", "Examples/.build/stale",
                     "Examples/.swiftpm/configuration", "Examples/Package.resolved",
                     "Examples/Apple.xcodeproj/xcuserdata/user", "Tools/node_modules/package.json"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("excluded")
        self.assertEqual(self.make_archive(), before)

    def test_missing_project_notice_refused(self):
        (self.root / "NOTICE").unlink()
        with self.assertRaisesRegex(ValueError, "notice"):
            self.make_archive()

    def test_changed_license_refused(self):
        (self.root / "Licenses/Unicode-15.0.md").write_text("abbreviated notice")
        with self.assertRaisesRegex(ValueError, "complete third-party license"):
            self.make_archive()

    def test_unreferenced_license_refused(self):
        path = self.root / "THIRD-PARTY-NOTICES.md"
        path.write_text(path.read_text().replace("Licenses/Ada-MIT.txt", "Ada.txt"))
        with self.assertRaisesRegex(ValueError, "do not reference"):
            self.make_archive()

    def test_missing_iana_attribution_refused(self):
        path = self.root / "THIRD-PARTY-NOTICES.md"
        path.write_text(path.read_text().replace("2026-09-17", "unknown"))
        with self.assertRaisesRegex(ValueError, "IANA attribution"):
            self.make_archive()

    def test_external_source_symlink_refused(self):
        (self.root / "Sources/External.swift").symlink_to(packaging.ROOT / "Package.swift")
        with self.assertRaisesRegex(ValueError, "Symlinks"):
            self.make_archive()

    def test_directory_symlink_refused(self):
        shutil.rmtree(self.root / "Examples")
        (self.root / "Examples").symlink_to(packaging.ROOT / "Examples", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            self.make_archive()

    def test_uncompressed_idna_archive_refused(self):
        (self.root / "Reference/manifest-idna-goldens.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "Uncompressed IDNA"):
            self.make_archive()

    def test_missing_privacy_declaration_refused(self):
        (self.root / "Sources/Lokalized/PrivacyInfo.xcprivacy").unlink()
        with self.assertRaisesRegex(ValueError, "privacy declaration"):
            self.make_archive()

    def test_output_in_source_tree_refused(self):
        with self.assertRaisesRegex(ValueError, "outside the packaged input"):
            packaging.create_archive(self.root, self.root / "Tools/archive.tar.gz")

    def test_omitted_member_refused(self):
        files = self.make_archive()
        self.rewrite(lambda rows: rows[1:])
        with self.assertRaisesRegex(ValueError, "omitted"):
            packaging.check_archive(self.archive, files)

    def test_duplicate_member_refused(self):
        files = self.make_archive()
        self.rewrite(lambda rows: rows + [rows[0]])
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            packaging.check_archive(self.archive, files)

    def test_modified_member_bytes_refused(self):
        files = self.make_archive()
        def change(rows):
            member, data = rows[0]
            rows[0] = member, bytes([data[0] ^ 1]) + data[1:]
            return rows
        self.rewrite(change)
        with self.assertRaisesRegex(ValueError, "content differs"):
            packaging.check_archive(self.archive, files)

    def test_traversal_member_refused_before_extraction(self):
        files = self.make_archive()
        def change(rows):
            rows[0][0].name = "lokalized-swift/../escaped"
            return rows
        self.rewrite(change)
        destination = self.base / "Extracted"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            packaging.check_archive(self.archive, files, destination)
        self.assertFalse(destination.exists())
        self.assertFalse((self.base / "escaped").exists())

    def test_archive_symlink_refused(self):
        files = self.make_archive()
        def change(rows):
            rows[0][0].type = tarfile.SYMTYPE
            rows[0][0].linkname = "../../escape"
            rows[0][0].size = 0
            rows[0] = rows[0][0], b""
            return rows
        self.rewrite(change)
        with self.assertRaisesRegex(ValueError, "nonregular"):
            packaging.check_archive(self.archive, files)

    def test_noncanonical_metadata_refused(self):
        files = self.make_archive()
        def change(rows):
            rows[0][0].mtime = 1
            return rows
        self.rewrite(change)
        with self.assertRaisesRegex(ValueError, "metadata differs"):
            packaging.check_archive(self.archive, files)

    def test_current_tree_change_invalidates_archive(self):
        self.make_archive()
        (self.root / "Sources/Lokalized/API.swift").write_text("changed\n")
        with self.assertRaisesRegex(ValueError, "differs"):
            packaging.check_archive(self.archive, packaging.source_files(self.root))

    def test_existing_extraction_destination_refused(self):
        files = self.make_archive()
        destination = self.base / "Existing"
        destination.mkdir()
        with self.assertRaisesRegex(ValueError, "must be fresh"):
            packaging.check_archive(self.archive, files, destination)


if __name__ == "__main__":
    unittest.main()
