#!/usr/bin/env python3
"""Offline rejection tests for native host qualification; no hardware is simulated as evidence."""
import unittest

import verify_deployment as deployment


class NativeHostTests(unittest.TestCase):
    def check(self, observation, architecture):
        return deployment.validate_host(observation, architecture, architecture, "27.0.1")

    def observation(self, architecture):
        return {"architecture": architecture, "hardwareCPUType": 0x0100000C if architecture == "arm64" else 7,
                "hardwareArm64": 1 if architecture == "arm64" else 0,
                "processTranslated": 0, "macOS": "27.0.1"}

    def test_accepts_native_observation_shapes(self):
        for architecture in ("arm64", "x86_64"):
            with self.subTest(architecture=architecture):
                observation = self.observation(architecture)
                self.assertEqual(self.check(observation, architecture), observation)

    def test_accepts_intel_abi64_cpu_type(self):
        observation = self.observation("x86_64")
        observation["hardwareCPUType"] = 0x01000007
        self.check(observation, "x86_64")

    def test_refuses_translated_intel(self):
        observation = self.observation("x86_64")
        observation.update(hardwareCPUType=0x0100000C, hardwareArm64=1, processTranslated=1)
        with self.assertRaises(deployment.VerificationError):
            self.check(observation, "x86_64")

    def test_refuses_contradictory_hardware_even_if_translation_flag_is_zero(self):
        for architecture in ("arm64", "x86_64"):
            for field in ("hardwareCPUType", "hardwareArm64"):
                with self.subTest(architecture=architecture, field=field):
                    observation = self.observation(architecture)
                    other = self.observation("x86_64" if architecture == "arm64" else "arm64")
                    observation[field] = other[field]
                    with self.assertRaises(deployment.VerificationError):
                        self.check(observation, architecture)

    def test_refuses_wrong_requested_runner(self):
        with self.assertRaises(deployment.VerificationError):
            deployment.validate_host(self.observation("arm64"), "x86_64", "arm64", "27.0.1")

    def test_refuses_different_python_process_architecture(self):
        with self.assertRaises(deployment.VerificationError):
            deployment.validate_host(self.observation("arm64"), "arm64", "x86_64", "27.0.1")

    def test_refuses_boolean_and_noninteger_kernel_values(self):
        for field in ("hardwareCPUType", "hardwareArm64", "processTranslated"):
            for invalid in (True, False, "0", 0.0, None):
                with self.subTest(field=field, value=invalid):
                    observation = self.observation("arm64")
                    observation[field] = invalid
                    with self.assertRaises(deployment.VerificationError):
                        self.check(observation, "arm64")

    def test_refuses_missing_and_unknown_observations(self):
        for field in self.observation("arm64"):
            observation = self.observation("arm64")
            del observation[field]
            with self.assertRaises(deployment.VerificationError):
                self.check(observation, "arm64")
        observation = self.observation("arm64")
        observation["nativeIntel"] = True
        with self.assertRaises(deployment.VerificationError):
            self.check(observation, "arm64")

    def test_refuses_unknown_translation_status(self):
        observation = self.observation("arm64")
        observation["processTranslated"] = -1
        with self.assertRaises(deployment.VerificationError):
            self.check(observation, "arm64")

    def test_refuses_malformed_old_or_different_os(self):
        for version in ("11.0.0", "27", "27.0", "27.0.1-dev", "26.0.1", None):
            with self.subTest(version=version):
                observation = self.observation("arm64")
                observation["macOS"] = version
                with self.assertRaises(deployment.VerificationError):
                    self.check(observation, "arm64")

    def test_refuses_unknown_architecture(self):
        observation = self.observation("arm64")
        observation["architecture"] = "aarch64"
        with self.assertRaises(deployment.VerificationError):
            self.check(observation, "arm64")


if __name__ == "__main__":
    unittest.main()
