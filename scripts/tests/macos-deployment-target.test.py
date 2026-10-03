import importlib.util
import pathlib
import platform
import plistlib
import subprocess
import sys
import tempfile
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


@unittest.skipUnless(sys.platform == "darwin", "requires Apple's Mach-O tools")
class BundledMinimumTests(unittest.TestCase):
    def test_higher_minimum_in_non_native_slice_is_rejected(self):
        native = "arm64" if platform.machine() == "arm64" else "x86_64"
        other = "x86_64" if native == "arm64" else "arm64"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            app = root / "fixture.app"
            contents = app / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "LSMinimumSystemVersion": "14.2.1",
            }))
            source = root / "fixture.c"
            source.write_text("int fixture(void) { return 0; }\n")
            objects = []
            for arch, minimum in [(native, "14.2.1"), (other, "14.4")]:
                target = root / f"{arch}.o"
                subprocess.run(["xcrun", "clang", "-target",
                                f"{arch}-apple-macos{minimum}", "-c",
                                str(source), "-o", str(target)], check=True,
                               capture_output=True, text=True)
                objects.append(str(target))
            subprocess.run(["xcrun", "lipo", "-create", *objects, "-output",
                            str(contents / "universal.o")], check=True,
                           capture_output=True, text=True)
            result = subprocess.run([sys.executable, spec.origin, str(app)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Mach-O requires macOS 14.4.0", result.stderr)


if __name__ == "__main__":
    unittest.main()
