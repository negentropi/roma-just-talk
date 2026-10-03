#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


spec = importlib.util.spec_from_file_location(
    "regression", Path(__file__).resolve().parents[1] / "prove-recording-cache-regression.py"
)
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)


class RegressionLifecycleTests(unittest.TestCase):
    def test_timeout_retains_output_stops_descendants_and_restores_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.swift"
            source.write_bytes(b"candidate")
            evidence = root / "evidence"
            evidence.mkdir()
            child = root / "child.py"
            child.write_text(
                "from pathlib import Path\nimport os, signal, time\n"
                "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                f"Path({str(root / 'child.pid')!r}).write_text(str(os.getpid()))\n"
                "time.sleep(0.6)\n"
                f"Path({str(root / 'late-source')!r}).write_bytes(Path({str(source)!r}).read_bytes())\n"
            )
            command = [sys.executable, "-c",
                       "import subprocess, sys, time; "
                       f"subprocess.Popen([sys.executable, {str(child)!r}]); "
                       "print('partial compiler output', flush=True); time.sleep(30)"]
            with self.assertRaises(subprocess.TimeoutExpired):
                regression.prove_regression(source, b"known-bad", command, evidence, timeout=0.3)
            self.assertEqual(source.read_bytes(), b"candidate")
            self.assertIn("partial compiler output", (evidence / "known-bad.log").read_text())
            self.assertTrue((root / "child.pid").exists())
            time.sleep(0.7)
            self.assertFalse((root / "late-source").exists())
            self.assertFalse((evidence / "receipt.json").exists())

    def test_build_failure_is_not_a_behavioral_red(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.swift"
            source.write_bytes(b"candidate")
            command = [sys.executable, "-c", "print('compiler error'); raise SystemExit(1)"]
            with self.assertRaisesRegex(RuntimeError, "after a successful build"):
                regression.prove_regression(source, b"known-bad", command, root, timeout=5)
            self.assertEqual(source.read_bytes(), b"candidate")
            self.assertFalse((root / "candidate.log").exists())
            self.assertFalse((root / "receipt.json").exists())

    def test_behavioral_red_then_green_uses_restored_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.swift"
            source.write_bytes(b"candidate")
            code = (
                "from pathlib import Path; "
                f"bad = Path({str(source)!r}).read_bytes() == b'known-bad'; "
                "print('Build complete!'); "
                f"print({regression.ASSERTION!r} if bad else 'selected test passed'); "
                "raise SystemExit(1 if bad else 0)"
            )
            regression.prove_regression(source, b"known-bad", [sys.executable, "-c", code], root, timeout=5)
            self.assertEqual(source.read_bytes(), b"candidate")
            self.assertTrue((root / "receipt.json").exists())
            self.assertIn("selected test passed", (root / "candidate.log").read_text())


if __name__ == "__main__":
    unittest.main()
