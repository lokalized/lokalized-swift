#!/usr/bin/env python3
"""Development-only boundary controls for the compressed IDNA reference reader."""
import hashlib
from pathlib import Path
import tempfile
import unittest
import zlib
import verify_idna_urls as urls


class IDNAArchiveTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="lokalized-idna-gzip-", dir="/private/tmp")
        self.addCleanup(scratch.cleanup)
        self.path = Path(scratch.name) / "fixture.json.gz"
        self.payload = b"a" * 131_073
        self.compressed = urls.gzip_bytes(self.payload)

    def read(self, data, compressed_limit=1_024, decoded_limit=131_073):
        self.path.write_bytes(data)
        return urls.read_gzip(self.path, compressed_limit, decoded_limit)

    def test_exact_budgets_and_one_byte_overflows(self):
        self.assertEqual(self.read(self.compressed, len(self.compressed), len(self.payload)), self.payload)
        with self.assertRaisesRegex(ValueError, "^Reference file exceeds byte budget"):
            self.read(self.compressed, len(self.compressed) - 1, len(self.payload))
        with self.assertRaisesRegex(ValueError, "^Decoded reference exceeds byte budget"):
            self.read(self.compressed, len(self.compressed), len(self.payload) - 1)

    def test_empty_member_at_zero_decoded_budget(self):
        self.assertEqual(self.read(urls.gzip_bytes(b""), decoded_limit=0), b"")

    def test_truncated_and_damaged_members(self):
        variants = [b"", self.compressed[:4], self.compressed[:-1]]
        for position in (0, len(self.compressed) - 8, len(self.compressed) - 4):
            altered = bytearray(self.compressed)
            altered[position] ^= 1
            variants.append(bytes(altered))
        for invalid in variants:
            with self.subTest(data=invalid):
                with self.assertRaisesRegex(ValueError, "^Compressed reference is invalid or truncated"):
                    self.read(invalid)

    def test_trailing_bytes_and_concatenated_members(self):
        for invalid in [self.compressed + b" ", self.compressed + self.compressed]:
            with self.subTest(data=invalid):
                with self.assertRaisesRegex(ValueError, "^Compressed reference has trailing data"):
                    self.read(invalid, decoded_limit=2 * len(self.payload))

    def test_plaintext_raw_deflate_and_zlib_wrappers(self):
        for invalid in [b"{}\n", self.compressed[10:-8], zlib.compress(self.payload)]:
            with self.subTest(data=invalid):
                with self.assertRaisesRegex(ValueError, "^Compressed reference is invalid or truncated"):
                    self.read(invalid)

    def test_frozen_decoded_identity_and_recompression(self):
        decoded = urls.read_gzip(urls.GOLDENS)
        self.assertEqual(len(decoded), 19_308_094)
        self.assertEqual(hashlib.sha256(decoded).hexdigest(), urls.GOLDENS_SHA256)
        refreshed = urls.gzip_bytes(decoded)
        self.assertEqual(refreshed[:10], bytes.fromhex("1f8b08000000000002ff"))
        self.assertEqual(self.read(refreshed, urls.MAXIMUM_COMPRESSED_BYTES, urls.MAXIMUM_DECODED_BYTES), decoded)


if __name__ == "__main__":
    unittest.main()
