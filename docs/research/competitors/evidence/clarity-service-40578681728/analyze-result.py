#!/usr/bin/env python3
"""Revalidate the retained native calibration and actual service tests against pinned Git."""
import ast
import collections
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

directory = Path(__file__).resolve().parent
artifact = directory / "artifact"
calibration = artifact / "swiftpm-testing-signature-check"
service = artifact / "clarity-service-check"
revision = "4d5b65b5c662d1b78ccff883a10bf510ed7d82f3"
helper = "scripts/tests/swiftpm-testing-signature.test.sh"
driver = "scripts/run-clarity-service-check.sh"
read = lambda path: json.loads(path.read_text())
digest = lambda data: hashlib.sha256(data).hexdigest()

def source(path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"])

def definitions(path):
    block = source(path).decode().split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
    nodes = []
    for node in ast.parse(block).body:
        if isinstance(node, ast.Assign) and any(isinstance(item, ast.Name) and item.id == "command" for target in node.targets for item in ast.walk(target)):
            break
        nodes.append(node)
    namespace = {}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "<pinned-classifier>", "exec"), namespace)
    return namespace

run = read(directory / "run.json")
assert run["headSha"] == revision and run["conclusion"] == "success" and run["status"] == "completed"
assert all(step["conclusion"] == "success" for step in run["jobs"][0]["steps"])
cal, api = definitions(helper), definitions(driver)
contract = read(service / "source-contract.json")
inputs = contract["sourceInputs"]
assert len(inputs) == 172 and all(digest(source(path)) == value for path, value in inputs.items())
assert inputs == read(service / "source-before.json") == read(service / "source-after.json")
dependency_paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", "-z", revision, "--", "VoiceInkCore", "VoiceInkNVIDIA"]).decode().strip("\0").split("\0")
assert len(dependency_paths) == 156 and set(dependency_paths) == set(contract["dependencySources"])
assert all(digest(source(path)) == value for path, value in contract["dependencySources"].items())
for path, value in contract["appSources"].items():
    assert digest((service / "package/Sources/VoiceInk" / Path(path).name).read_bytes()) == value
assert len(contract["appSources"]) == 11
assert api["files"](service / "package/Sources") == contract["generatedSources"]
assert api["files"](service / "package/Tests") == contract["generatedTests"]
assert (service / "package/Tests/VoiceInkTests/ClarityProviderTests.swift").read_bytes() == source(api["TEST"])
assert (service / "package/Tests/VoiceInkTests/Namespace.swift").read_text() == api["WRAPPER"]
assert digest(source(api["TEST"])) == contract["testSourceSHA256"] == api["TEST_HASH"]
assert digest(source(api["SOURCES"][1])) == contract["serviceSourceSHA256"] == api["SERVICE_HASH"]
assert digest((service / "package/Package.swift").read_bytes()) == contract["packageManifestSHA256"]
canonical = api["pins"](source(api["LOCK"]))
assert len(canonical) == 41 and contract["expectedPins"] == {key: canonical[key] for key in contract["expectedPins"]}
for name in ["pins-before-build.json", "pins-after-build.json", "pins-after.json"]:
    pins = read(service / name)
    assert pins["valid"] is True and pins["observedPins"] == contract["expectedPins"] and len(pins["observedPins"]) == 26
assert (service / "resolved-before-build.json").read_bytes() == (service / "package/Package.resolved").read_bytes()
assert read(service / "source-verification.json")["valid"] is True

cal_contract = read(calibration / "source-contract.json")
assert cal_contract["scriptSHA256"] == digest(source(helper)) == inputs[helper]
assert (calibration / "package/Package.swift").read_text() == cal["MANIFEST"]
assert cal["files"](calibration / "package/Tests") == cal_contract["testCensus"]
assert (calibration / "package/Tests/SignaturePreparationTests/signed-resource.txt").read_bytes() == cal["RESOURCE"]
assert digest(cal["RESOURCE"]) == cal_contract["resourceSHA256"]
native, prepared, after = [read(calibration / f"{label}-bundle.json") for label in ["native", "prepared", "after"]]
assert prepared == after and native["resourceBundleManifests"] == prepared["resourceBundleManifests"]
resource_hashes = [value for bundle in after["resourceBundleManifests"].values() for path, value in bundle.items() if Path(path).name == "signed-resource.txt"]
assert resource_hashes == [cal_contract["resourceSHA256"]]
assert cal["native_pregate"](int((calibration / "native-verify-exit.txt").read_text()), (calibration / "native-verify-stdout.log").read_text(), (calibration / "native-verify-stderr.log").read_text(), native["bundle"])
assert cal["classify"]((calibration / "tests.log").read_text(), int((calibration / "test-exit.txt").read_text()), prepared, after)["valid"] is True
for name in ["sign-exit.txt", "prepared-verify-exit.txt", "after-verify-exit.txt", "native-display-exit.txt", "prepared-display-exit.txt", "after-display-exit.txt"]:
    assert int((calibration / name).read_text()) == 0
for channel in ["stdout", "stderr"]:
    assert (calibration / f"prepared-display-{channel}.log").read_bytes() == (calibration / f"after-display-{channel}.log").read_bytes()
assert read(calibration / "result.json")["valid"] is True
link = read(service / "signing-calibration.json")
assert link["valid"] is True and link["scriptSHA256"] == inputs[helper] and link["resultSHA256"] == digest((calibration / "result.json").read_bytes())

compiled = read(service / "test-binary-compiled.json")
signed = read(service / "test-binary-before.json")
assert signed == read(service / "test-binary-after.json")
assert compiled["resourceBundleManifests"] == signed["resourceBundleManifests"]
for old, new, key, executable in [
    (native, prepared, "bundleManifest", "Contents/MacOS/SignaturePreparationPackageTests"),
    (compiled, signed, "bundleManifest", "Contents/MacOS/ClarityServiceCheckPackageTests"),
]:
    assert set(new[key]) - set(old[key]) == {"Contents/_CodeSignature/CodeResources"}
    assert not set(old[key]) - set(new[key])
    assert [path for path in old[key] if old[key][path] != new[key][path]] == [executable]
assert (service / "signature-before.txt").read_bytes() == (service / "signature-after.txt").read_bytes()
assert "Sealed Resources version=2" in (service / "signature-before.txt").read_text()
assert (service / "signature-verification-before.log").read_bytes() == (service / "signature-verification-after.log").read_bytes() == b""
assert read(service / "identity-verification.json")["valid"] is True
log = (service / "tests.log").read_text()
result = api["classify"](log, int((service / "test-exit-code.txt").read_text()))
assert result["valid"] is True and read(service / "result.json")["valid"] is True
xml = ET.parse(service / "tests.xml").getroot()
suite = xml.find("testsuite")
assert all(suite.attrib[key] == value for key, value in {"tests": "7", "errors": "0", "failures": "0", "skipped": "0"}.items())
cases = suite.findall("testcase")
assert collections.Counter(case.attrib["name"].removesuffix("()") for case in cases) == collections.Counter(api["CASES"])
timings = {case.attrib["name"].removesuffix("()"): float(case.attrib["time"]) for case in cases}
core_registered = len(re.findall(rb'VoiceInkCoreCheck\(name: "', source("VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift")))
receipt = {
    "run_id": 40578681728, "run_url": run["url"], "source_head": revision,
    "classification": "passed-seven-clarity-service-tests-with-native-signing-calibration",
    "service_tests": {"started_once": result["startedTests"], "passed_once": result["passedTests"],
                      "native_exit_code": 0, "total": 7, "failed": 0, "skipped": 0,
                      "duration_seconds": float(suite.attrib["time"]), "case_total_seconds": timings,
                      "junit_and_standard_swift_testing_log_agree": True},
    "signing_calibration": {"native_strict_verify_exit_code": 1,
                            "native_exact_error": cal["FAILURE"], "single_resource_test_passed": True,
                            "processed_resource_sha256": cal_contract["resourceSHA256"],
                            "explicit_sign_exit_code": 0, "prepared_and_after_strict_verify_exit_code": 0,
                            "calibration_source_bound_to_main_gate": True},
    "identity": {"intentional_pre_freeze_signing_in_both_bundles": True,
                 "preparation_changes_only_main_macho_and_adds_code_resources": True,
                 "prepared_to_after_macho_full_bundle_external_resources_and_signatures_unchanged": True,
                 "service_signed_macho_sha256": signed["executableSHA256"],
                 "calibration_signed_macho_sha256": prepared["machOSHA256"]},
    "source_and_pins": {"source_inputs_verified": 172, "real_core_nvidia_file_count": 156,
                        "actual_app_library_file_count": 11, "canonical_service_pin_count": 26,
                        "pins_unchanged_after_metadata_normalization_build_and_tests": True,
                        "test_source_sha256": contract["testSourceSHA256"],
                        "service_source_sha256": contract["serviceSourceSHA256"]},
    "toolchain": (service / "toolchain.log").read_text(),
    "core_checks": {"registered_in_pinned_source": core_registered, "executed_in_this_run": False},
    "scope": "Actual Clarity/legacy service APIs with standard Swift Testing, real SDK dependencies, memory-only SwiftData and synthetic Local CLI commands. No normal app/UI, editor delivery, profile activation, unwired processor, authenticated provider, AI-quality, release, or full CoreChecks proof.",
    "artifact": read(directory / "artifact.json"),
}
(directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
(directory / "artifact-members.sha256").write_text("".join(digest(path.read_bytes()) + "  " + str(path.relative_to(directory)) + "\n" for path in sorted(artifact.rglob("*")) if path.is_file()))
print(json.dumps({"source_head": revision, "service_tests": 7, "calibration_test": 1,
                  "signing_and_runtime_integrity_verified": True, "canonical_pins": 26,
                  "core_registered_not_executed": core_registered}, indent=2))
