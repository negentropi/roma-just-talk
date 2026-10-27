#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$repo" "${1:-run}" <<'PY'
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

BASELINE = "919670ae5b918afbfad6f4d88982a481c1c4b532"
ROOTS = ["VoiceInkCore", "VoiceInkNVIDIA"]
POLICY = "VoiceInkCore/Sources/VoiceInkCore/DictionaryPolicy.swift"
TEST = "VoiceInkCore/Tests/VoiceInkCoreTests/LiteralCorrectionRuleTests.swift"
RUNNER = "VoiceInkCore/Tests/VoiceInkCoreTests/VoiceInkCoreCheckRunner.swift"
DRIVER = "scripts/run-literal-rule-check.sh"
WORKFLOW = ".github/workflows/voiceink-literal-rule-check.yml"
PREFIX = "LiteralCorrectionRuleTests."
REQUIRED_FAILURES = {PREFIX + name for name in [
    "testLiteralCommaIsOneSourcePhrase", "testLiteralOutputNeverFeedsAnotherReplacement",
    "testLegacyOutputCannotCreateALiteralMatch", "testLiteralSourceBlocksWholeCrossingLegacyMatches",
    "testProtectedRangesRemapUTF16AndInsertExactLiteralOutputLast",
    "testExplicitInvalidMatchingKindsRejectInsteadOfBecomingLegacy",
    "testSharedEditReconstructionPreservesLiteralKind", "testLegacyExportMapOmitsEveryLiteralRule"
]}
CONTROL = PREFIX + "testLegacyOnlyAndUnmatchedLiteralKeepSequentialCommaBehavior"
repo = Path(sys.argv[1])
mode = sys.argv[2]
digest = lambda value: hashlib.sha256(value).hexdigest()

def require(value, message):
    if not value:
        raise RuntimeError(message)

def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def git(*args):
    return subprocess.check_output(["git", "-C", str(repo), *args])

def blob(revision, path):
    return git("show", revision + ":" + path)

def snapshot(revision):
    result = {}
    for entry in git("ls-tree", "-r", "-z", revision, "--", *ROOTS).split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        file_mode, kind, object_id = metadata.decode().split()
        require(kind == "blob" and file_mode in {"100644", "100755"}, "Unexpected local Core source kind")
        path = name.decode()
        data = blob(revision, path)
        result[path] = {"sha256": digest(data), "gitObject": object_id, "mode": file_mode}
    return result

def materialize(revision, values, target):
    for name, value in values.items():
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(blob(revision, name))
        path.chmod(0o755 if value["mode"] == "100755" else 0o644)

def verify_tree(target, expected):
    actual = {}
    for root in ROOTS:
        require((target / root).is_dir() and not (target / root).is_symlink(), "Missing real Core package directory")
        for path in (target / root).rglob("*"):
            require(not path.is_symlink(), "Core source census cannot contain symlinks")
            if ".build" in path.parts or ".swiftpm" in path.parts or path.is_dir():
                continue
            require(path.is_file() and not path.is_symlink(), "Unexpected Core source filesystem kind")
            name = str(path.relative_to(target))
            require(name in expected, "Unexpected Core source file")
            require(path.stat().st_mode & 0o777 == int(expected[name]["mode"], 8) & 0o777, "Core source permissions changed")
            actual[name] = digest(path.read_bytes())
    require(actual == {name: value["sha256"] for name, value in expected.items()}, "Core source/lock census or bytes changed")

def registrations(source):
    names = re.findall(r'VoiceInkCoreCheck\(name: "([^"]+)"', source)
    require(names and len(names) == len(set(names)), "Missing or duplicate check registrations")
    return names

def assertion_ranges(source):
    starts = list(re.finditer(r"^    func (test\w+)\(", source, re.M))
    lines = source.splitlines()
    result = {}
    for index, match in enumerate(starts):
        first = source[:match.start()].count("\n") + 1
        end = source[:starts[index + 1].start()].count("\n") if index + 1 < len(starts) else len(lines)
        result[PREFIX + match.group(1)] = [number for number in range(first, end + 1)
            if re.search(r"\b(XCTAssert\w+|XCTFail|XCTUnwrap)\(", lines[number - 1])]
    return result

def classify(log, exit_code, lane, expected, ranges, fixture_path, required=REQUIRED_FAILURES, control=CONTROL):
    records = re.findall(r"^(PASS|FAIL) (\S+)$", log, re.M)
    names = [name for _, name in records]
    failures = {name for verdict, name in records if verdict == "FAIL"}
    fresh = {name for name in expected if name.startswith(PREFIX)}
    summary_marker = "VoiceInkCoreChecks failed:\n"
    assertions = []
    errors = []
    if names != expected:
        errors.append("Every registered check must execute exactly once in declared order")
    if lane == "candidate":
        if exit_code != 0 or failures or log.count("Executed " + str(len(expected)) + " VoiceInkCore checks.") != 1 or summary_marker in log:
            errors.append("Candidate requires exit zero, all checks passing and the completed count")
    else:
        if exit_code != 1 or log.count(summary_marker) != 1 or re.search(r"^Executed \d+ VoiceInkCore checks\.$", log, re.M):
            errors.append("Baseline requires a real assertion-failure exit and summary")
        if not required <= failures or not failures <= fresh or control in failures:
            errors.append("Baseline failures must include the named literal defects, with all legacy controls passing")
        if summary_marker in log:
            summary = log.split(summary_marker, 1)[1]
            for raw in summary.splitlines():
                if not raw.strip():
                    continue
                match = re.fullmatch(r"(.+):(\d+): (.*)", raw)
                if not match or Path(match.group(1)).resolve() != fixture_path.resolve():
                    errors.append("Failure summary contains an unrelated source or malformed assertion")
                    continue
                line = int(match.group(2))
                owners = [name for name, locations in ranges.items() if line in locations]
                if len(owners) != 1 or owners[0] not in failures or "unexpected thrown error" in match.group(3).lower():
                    errors.append("Failure must identify an actual assertion in a failed literal method")
                    continue
                assertions.append({"method": owners[0], "line": line, "message": match.group(3), "raw": raw})
        if {value["method"] for value in assertions} != failures:
            errors.append("Every failed method must have its own retained assertion")
    return {"valid": not errors, "classification": ("intended-literal-rule-failures" if lane == "baseline" else "passed") if not errors else "invalid-or-failed",
            "lane": lane, "exitCode": exit_code, "registered": len(expected), "executed": len(records),
            "passed": sum(value == "PASS" for value, _ in records), "failedMethods": sorted(failures),
            "assertionCount": len(assertions), "assertions": assertions, "errors": errors}

def self_test():
    names = ["Legacy.testControl", PREFIX + "testComma", PREFIX + "testCascade", PREFIX + "testControl"]
    ranges = {names[1]: [3], names[2]: [7], names[3]: [10]}
    path = Path("/owned/LiteralCorrectionRuleTests.swift")
    required, control = set(names[1:3]), names[3]
    bad = "\n".join(("FAIL " if name in required else "PASS ") + name for name in names)
    bad += "\nVoiceInkCoreChecks failed:\n" + str(path) + ":3: expected X to equal Y\n" + str(path) + ":7: expected A to equal B\n"
    good = "\n".join("PASS " + name for name in names) + "\nExecuted 4 VoiceInkCore checks.\n"
    def accepted(log, code, lane="baseline"):
        return classify(log, code, lane, names, ranges, path, required, control)["valid"]
    require(accepted(bad, 1) and accepted(good, 0, "candidate"), "Valid classifier controls failed")
    invalid = [
        ("compile error", 1, "baseline"), (bad, 0, "baseline"), (good, 0, "baseline"),
        (bad.replace("PASS Legacy.testControl", "FAIL Legacy.testControl"), 1, "baseline"),
        (bad.replace("FAIL " + names[1], "PASS " + names[1]), 1, "baseline"),
        (bad.replace("PASS " + control, "FAIL " + control), 1, "baseline"),
        (bad.replace("PASS Legacy.testControl\n", ""), 1, "baseline"),
        (bad + "PASS Legacy.testControl\n", 1, "baseline"),
        (bad.replace("PASS " + control, "PASS Legacy.testControl"), 1, "baseline"),
        (bad.replace(str(path), "/foreign/Test.swift"), 1, "baseline"),
        (bad.replace(":3:", ":999:"), 1, "baseline"),
        (bad.replace("expected X", "unexpected thrown error X"), 1, "baseline"),
        (bad.replace("PASS Legacy", "SKIP Legacy"), 1, "baseline"),
        (good.replace("Executed 4 VoiceInkCore checks.\n", ""), 0, "candidate"),
        (good, 1, "candidate"), (bad, 0, "candidate"),
        (good.replace("PASS " + names[1], "FAIL " + names[1]), 0, "candidate"),
    ]
    require(all(not accepted(*value) for value in invalid), "Invalid classifier fixture was accepted")
    with tempfile.TemporaryDirectory(prefix="rjt-literal-census-") as temporary:
        root = Path(temporary)
        for name in ROOTS:
            (root / name).mkdir()
        verify_tree(root, {})
        outside = root / "outside"
        outside.mkdir()
        (outside / "Unexpected.swift").write_text("unexpected source")
        (root / ROOTS[0] / "injected").symlink_to(outside, target_is_directory=True)
        try:
            verify_tree(root, {})
        except RuntimeError as error:
            require("symlink" in str(error), "Directory link rejected for an unrelated reason")
        else:
            raise RuntimeError("A source directory symlink escaped the census")
    print(json.dumps({"classification": "classifier-self-test-passed", "validControls": 3, "rejectedCases": len(invalid) + 1, "scope": "Result parsing and source census only; no Swift execution"}))

def package_state(scratch, pins):
    state = json.loads((scratch / "workspace-state.json").read_text())
    result = {}
    for dependency in state.get("object", {}).get("dependencies", []):
        checkout = dependency.get("state", {}).get("checkoutState")
        if checkout is None:
            continue
        identity = dependency["packageRef"]["identity"]
        path = scratch / "checkouts" / dependency["subpath"]
        require(identity in pins and identity not in result and path.parent == scratch / "checkouts", "Unexpected resolved package")
        revision = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
        dirty = subprocess.check_output(["git", "-C", str(path), "status", "--porcelain", "--untracked-files=no", "--ignore-submodules=none"], text=True)
        require(revision == checkout["revision"] == pins[identity]["state"]["revision"] and not dirty, "Resolved package revision/source differs from its frozen pin: " + identity)
        result[identity] = {"revision": revision, "location": dependency["packageRef"].get("location"), "trackedChanges": dirty}
    require(set(result) == set(pins), "All 22 resolved package checkouts must be present")
    return result

def native():
    require(mode == "run" and os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted" and sys.platform == "darwin" and os.getuid() != 0,
            "Native comparison requires a fresh non-root GitHub-hosted Mac; use --self-test elsewhere")
    output = Path(os.environ["RUNNER_TEMP"]) / "literal-rule-check"
    require(not output.exists(), "Refuse to overwrite an existing proof")
    output.mkdir(mode=0o700)
    stage = "prepare"
    try:
        head = git("rev-parse", "HEAD").decode().strip()
        require(head == os.environ["GITHUB_SHA"], "Checkout HEAD differs from the dispatched source")
        original, current = snapshot(BASELINE), snapshot(head)
        changed = {name for name in set(original) | set(current) if original.get(name) != current.get(name)}
        require(changed == {POLICY, TEST, RUNNER}, "Only the correction policy and exact oracle/registration may differ in local Core sources")
        for name, value in current.items():
            require(not (repo / name).is_symlink() and digest((repo / name).read_bytes()) == value["sha256"], "Checkout Core source is not its committed blob: " + name)
        for name in [DRIVER, WORKFLOW]:
            require((repo / name).read_bytes() == blob(head, name), "Verification helper is not committed")
        extra = git("ls-files", "--others", "--exclude-standard", "-z", "--", *ROOTS)
        require(not extra, "Unexpected untracked local Core source")
        test, runner = blob(head, TEST), blob(head, RUNNER)
        old_runner = blob(BASELINE, RUNNER)
        stripped = b"".join(line for line in runner.splitlines(keepends=True) if b'VoiceInkCoreCheck(name: "LiteralCorrectionRuleTests.' not in line)
        require(stripped == old_runner, "The baseline runner must change only by the 14 literal registrations")
        old_names, names = registrations(old_runner.decode()), registrations(runner.decode())
        new_names = [name for name in names if name.startswith(PREFIX)]
        require(len(old_names) == 1707 and len(names) == 1721 and len(new_names) == 14 and [name for name in names if name not in new_names] == old_names,
                "Expected all 1707 legacy registrations plus exactly 14 literal checks")
        ranges = assertion_ranges(test.decode())
        require(set(ranges) == set(new_names) and REQUIRED_FAILURES <= set(new_names) and CONTROL in new_names, "Literal test/registration methods differ")
        lock = blob(head, "VoiceInkCore/Package.resolved")
        pins = {value["identity"]: value for value in json.loads(lock)["pins"]}
        require(len(pins) == 22, "Expected the existing complete 22-pin Core graph")
        oracle = output / "oracle"
        oracle.mkdir()
        for name, data in {"LiteralCorrectionRuleTests.swift": test, "VoiceInkCoreCheckRunner.swift": runner,
                           "baseline-VoiceInkCoreCheckRunner.swift": old_runner,
                           "baseline-DictionaryPolicy.swift": blob(BASELINE, POLICY), "candidate-DictionaryPolicy.swift": blob(head, POLICY)}.items():
            (oracle / name).write_bytes(data)
        contract = {"version": 1, "baselineSHA": BASELINE, "candidateSHA": head, "originalSource": original, "candidateSource": current,
                    "oracleSHA256": digest(test), "runnerSHA256": digest(runner), "registrations": names, "oldRegistrations": old_names,
                    "literalRegistrations": new_names, "assertionLines": ranges, "requiredOldFailures": sorted(REQUIRED_FAILURES), "legacyControl": CONTROL,
                    "packageLockSHA256": digest(lock), "packagePins": pins, "helpers": {name: digest(blob(head, name)) for name in [DRIVER, WORKFLOW]},
                    "scope": "Actual old/current Core policy with byte-identical JSON oracle and registry; full Core checks, no app/provider/UI/storage-migration proof"}
        write(output / "contract.json", contract)
        def toolchain():
            return b"".join(subprocess.check_output(command, stderr=subprocess.STDOUT) for command in [["xcodebuild", "-version"], ["swift", "--version"], ["sw_vers"]])
        before = toolchain()
        (output / "toolchain-before.txt").write_bytes(before)
        results, package_states, lane_sources = {}, {}, {}
        for lane in ["baseline", "candidate"]:
            stage = lane
            target = output / (lane + "-source")
            values = copy.deepcopy(original if lane == "baseline" else current)
            materialize(BASELINE if lane == "baseline" else head, values, target)
            if lane == "baseline":
                for name, data in [(TEST, test), (RUNNER, runner)]:
                    (target / name).write_bytes(data)
                    values[name] = current[name]
            verify_tree(target, values)
            write(output / (lane + "-source-before.json"), values)
            scratch = Path(os.environ["RUNNER_TEMP"]) / ("literal-rule-build-" + lane)
            lane_sources[lane] = (target, values, scratch)
            require(not scratch.exists(), "Scratch builds must be fresh and distinct")
            command = ["swift", "run", "--package-path", str(target / "VoiceInkCore"), "--scratch-path", str(scratch),
                       "--force-resolved-versions", "--skip-update", "VoiceInkCoreChecks"]
            write(output / (lane + "-command.json"), {"argv": command})
            with (output / (lane + "-checks.log")).open("wb") as log:
                process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=1200)
            (output / (lane + "-exit.txt")).write_text(str(process.returncode) + "\n")
            verify_tree(target, values)
            write(output / (lane + "-source-after.json"), values)
            package_states[lane] = package_state(scratch, pins)
            write(output / (lane + "-packages.json"), package_states[lane])
            results[lane] = classify((output / (lane + "-checks.log")).read_text(errors="replace"), process.returncode, lane, names, ranges, target / TEST)
            write(output / (lane + "-result.json"), results[lane])
        stage = "verify"
        require(package_states["baseline"] == package_states["candidate"], "The two compiled package graphs differ")
        for lane, (target, values, scratch) in lane_sources.items():
            verify_tree(target, values)
            require(package_state(scratch, pins) == package_states[lane], "Resolved package state changed after its execution")
        after = toolchain()
        (output / "toolchain-after.txt").write_bytes(after)
        require(before == after, "Toolchain changed between the two executions")
        require(git("rev-parse", "HEAD").decode().strip() == head and snapshot(head) == current, "Checkout source revision changed")
        for name, value in current.items():
            require(digest((repo / name).read_bytes()) == value["sha256"], "Checkout source/lock changed")
        for name, expected in contract["helpers"].items():
            require(digest((repo / name).read_bytes()) == expected, "Verification helper changed during execution")
        require(all(value["valid"] for value in results.values()), "Native comparison did not meet its old-red/new-green contract")
        result = {"valid": True, "classification": "matched-old-red-new-green", "baselineSHA": BASELINE, "candidateSHA": head,
                  "oracleSHA256": digest(test), "runnerSHA256": digest(runner), "baseline": results["baseline"], "candidate": results["candidate"],
                  "sourcePinsAndToolchainUnchanged": True, "scope": contract["scope"]}
        write(output / "comparison-result.json", result)
        print(json.dumps({key: value for key, value in result.items() if key not in {"baseline", "candidate"}}, indent=2))
    except Exception as error:
        write(output / "failure.json", {"valid": False, "classification": "invalid-or-failed", "stage": stage, "error": str(error)})
        raise

if mode == "--self-test":
    self_test()
else:
    native()
PY
