import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location(
    "deployment_gate", pathlib.Path(__file__).parents[1] / "check-macos-deployment-target.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class DeploymentMinimumTests(unittest.TestCase):
    def test_zippered_swift_library_uses_mac_minimum(self):
        commands = """Load command 3
      cmd LC_BUILD_VERSION
 platform 1
    minos 13.1
Load command 4
      cmd LC_BUILD_VERSION
 platform 6
    minos 16.0
"""
        self.assertEqual(gate.macos_minimums(commands), [(13, 1, 0)])

    def test_every_universal_architecture_is_checked(self):
        commands = """binary (architecture arm64):
Load command 0
      cmd LC_BUILD_VERSION
 platform MACOS
    minos 14.2.1
binary (architecture x86_64):
Load command 0
      cmd LC_VERSION_MIN_MACOSX
  version 14.4
"""
        self.assertEqual(gate.macos_minimums(commands), [(14, 2, 1), (14, 4, 0)])

    def test_missing_mac_minimum_rejects_the_payload(self):
        with self.assertRaisesRegex(ValueError, "no macOS minimum"):
            gate.macos_minimums("""Load command 0
      cmd LC_BUILD_VERSION
 platform 6
    minos 16.0
""")

    def test_incomplete_mac_command_cannot_pass(self):
        with self.assertRaisesRegex(ValueError, "invalid macOS version"):
            gate.macos_minimums("""Load command 0
      cmd LC_BUILD_VERSION
 platform 1
""")

    def test_universal_slice_without_mac_support_rejects(self):
        with self.assertRaisesRegex(ValueError, "no macOS minimum"):
            gate.macos_minimums("""binary (architecture arm64):
Load command 0
      cmd LC_BUILD_VERSION
 platform 1
    minos 14.2.1
binary (architecture x86_64):
Load command 0
      cmd LC_BUILD_VERSION
 platform 6
    minos 16.0
""")


if __name__ == "__main__":
    unittest.main()
