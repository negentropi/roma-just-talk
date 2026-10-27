#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


baseline = "c1a0f967b11794b45f68d07d0d02e6dfb3eac81b"
source_path = "VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift"
tests_path = "VoiceInkCore/Tests/VoiceInkCoreTests/DictionaryPolicyTests.swift"
support_path = "VoiceInkCore/Tests/VoiceInkCoreTests/TestSupport.swift"
runner_path = "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
methods = [
    "testWordReplacementEngineApplyReturnsInputForNoRules",
    "testWordReplacementEngineApplySortsRulesByLongerOriginalText",
    "testWordReplacementEngineApplyUsesCaseInsensitiveWordBoundariesForSpacedText",
    "testWordReplacementEngineApplySortsCommaSeparatedVariantsByLength",
    "testWordReplacementEngineApplyUsesSubstringReplacementForNonSpacedScripts",
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def section(data, begin, end):
    if data.count(begin) != 1 or data.count(end) != 1:
        raise SystemExit("The source extraction boundaries changed")
    return data[data.index(begin):data.index(end)]


parser = argparse.ArgumentParser(description="Compare real dictionary sources with the same registered test bodies.")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[5]
output = args.output
if output is None:
    output = Path(tempfile.mkdtemp(prefix="rjt-unicode-replacement-proof-"))
else:
    output.mkdir(parents=True, exist_ok=False)

bad = subprocess.check_output(["git", "-C", str(repo), "show", baseline + ":" + source_path])
candidate = (repo / source_path).read_bytes()
tests = (repo / tests_path).read_bytes()
support = (repo / support_path).read_bytes()
runner = (repo / runner_path).read_text()
for method in methods:
    if runner.count('name: "DictionaryPolicyTests.' + method + '"') != 1:
        raise SystemExit("The focused behavior test is not registered exactly once: " + method)

focused = b"import Foundation\nfinal class DictionaryPolicyTests: XCTestCase {\n" + section(
    tests,
    b"    func testWordReplacementEngineApplyReturnsInputForNoRules()",
    b"    func testWordReplacementRuleCodableRoundTripsIOSPreferenceShape()",
) + b"}\n"
driver = (
    "import Foundation\nlet tests = DictionaryPolicyTests()\n"
    + "".join("tests." + method + "()\n" for method in methods)
    + 'if VoiceInkCoreTestRecorder.failureCount > 0 { print(VoiceInkCoreTestRecorder.failureSummary) }\n'
    + 'print("focused_registered_methods=5 failures=\\(VoiceInkCoreTestRecorder.failureCount)")\n'
    + "exit(VoiceInkCoreTestRecorder.failureCount == 0 ? 0 : 1)\n"
).encode()
receipt = {
    "baseline": baseline,
    "source_path": source_path,
    "known_bad_source_sha256": digest(bad),
    "candidate_source_sha256": digest(candidate),
    "test_source_sha256": digest(tests),
    "focused_test_source_sha256": digest(focused),
    "test_support_sha256": digest(support),
    "driver_sha256": digest(driver),
    "registered_methods": methods,
    "scope": "Compiled exact production engine extraction and unchanged registered test bodies. No full package or native app execution.",
    "contract": "Preserve existing non-spaced ranges, mixed-script matches and separators. Block other letters, combining marks and all decimal digits around spaced-script rules. No normalization or linguistic segmentation claim.",
    "swift_version": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
    "lanes": {},
}
with tempfile.TemporaryDirectory(prefix="rjt-unicode-replacement-build-") as temporary:
    build = Path(temporary)
    (build / "FocusedTests.swift").write_bytes(focused)
    (build / "TestSupport.swift").write_bytes(support)
    (build / "main.swift").write_bytes(driver)
    for lane, data, expected_exit, expected_failures in [
        ("known-bad", bad, 1, 8),
        ("candidate", candidate, 0, 0),
    ]:
        engine = b"import Foundation\n" + section(
            data, b"public struct VoiceInkWordReplacementRule:", b"public struct VoiceInkWordReplacementInsertPlan:"
        )
        (build / "Engine.swift").write_bytes(engine)
        command = [
            "xcrun", "swiftc", "-swift-version", "5", "-warnings-as-errors",
            str(build / "Engine.swift"), str(build / "TestSupport.swift"),
            str(build / "FocusedTests.swift"), str(build / "main.swift"), "-o", str(build / "check"),
        ]
        subprocess.run(command, check=True)
        result = subprocess.run([str(build / "check")], capture_output=True, text=True)
        log = result.stdout.replace(str(build) + "/", "") + result.stderr.replace(str(build) + "/", "")
        (output / (lane + ".txt")).write_text(log)
        observed = re.findall(r"focused_registered_methods=(\d+) failures=(\d+)", log)
        if result.returncode != expected_exit or observed != [("5", str(expected_failures))]:
            raise SystemExit("The matched behavior contract failed for " + lane + ". Inspect " + str(output))
        receipt["lanes"][lane] = {
            "exit_code": result.returncode,
            "failures": expected_failures,
            "engine_sha256": digest(engine),
            "log_sha256": digest(log.encode()),
        }

receipt["classification"] = "matched-red-green"
(output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(output)
print("PASS: known-bad 8 failures; candidate 0 failures; same 5 registered methods")
