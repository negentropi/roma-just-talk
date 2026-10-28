#!/usr/bin/env python3
import copy
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SOURCE = "VoiceInkTests/DictationStoreSeedLiveTests.swift"
KNOWN_BAD = "cc88b5b1e79a158e5665d81b7d179a42ebe12935"
FIXTURES = REPO / "docs/research/competitors/evidence/store-seed-40568776080"
EXPECTED = {
    "seed/schema-raw.json": "9022a2a23935b340ef0862c4161d801184b901047572fbdfacf3a3941fd02d3e",
    "seed/schema-canonical.json": "412aceafcd347b193af83af7f7d133fb903fdcfde2fd01f5f15debb19c9677be",
    "old-reopen/schema-raw.json": "cdf96457dc57faf8edbee73cd92cb70b9546d7ec087f3ba20c87142cedbd2232",
    "old-reopen/schema-canonical.json": "8b108a2dcfc9faeb103874daea745a3cb3943292d95a9a16ced0b66188ef867e"
}
FIELD_COUNTS = {"SessionMetric": 12, "Transcription": 16, "VocabularyWord": 2, "WordReplacement": 5}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def extract(source):
    matches = re.findall(r"(?ms)^    private static func canonicalSchema\(_ value: Any, key: String\? = nil\) throws -> Any \{\n.*?^    \}", source)
    assert len(matches) == 1, "The actual Swift canonicalization function is missing or ambiguous"
    return matches[0]


def actual_fixtures():
    receipt = json.loads((FIXTURES / "schema-fixture-receipt.json").read_text())
    assert receipt["runID"] == 40568776080 and receipt["sourceCommit"] == KNOWN_BAD
    assert receipt["classification"] == "original-failed-run-captured-schema-fixtures"
    assert receipt["artifactID"] == 12764288502
    assert receipt["artifactSHA256"] == "d2b5ee72550b1cf4eb4f5236f45a33f9ead0181c322a74bf34dfb6961aaecf84"
    documents = {}
    entities = {}
    for phase in ["seed", "old-reopen"]:
        observation = receipt["phases"][phase]
        assert observation["sourceSHA"] == "ebc92f1e60fdabbb9e26b2817f414d154865a9d5"
        assert type(observation["hostPID"]) is int and observation["hostPID"] > 0
        for name in ["schema-raw.json", "schema-canonical.json"]:
            data = (FIXTURES / phase / "observations" / name).read_bytes()
            assert sha256(data) == EXPECTED[phase + "/" + name] == observation["files"][name]["sha256"]
            assert len(data) == observation["files"][name]["bytes"]
            documents[phase + "/" + name] = json.loads(data)
        assert observation["runtimeSchemaRawSHA256"] == EXPECTED[phase + "/schema-raw.json"]
        rows = documents[phase + "/schema-raw.json"]["entities"]
        assert len(rows) == 4 and {row["name"] for row in rows} == set(FIELD_COUNTS)
        entities[phase] = {}
        for row in rows:
            maps = {}
            for key in ["attributes", "storedAttributes"]:
                attributes = row[key]
                maps[key] = {attribute["name"]: attribute for attribute in attributes}
                assert len(attributes) == len(maps[key]) == FIELD_COUNTS[row["name"]], "Actual fixture attribute names must be unique"
            assert maps["attributes"] == maps["storedAttributes"], "The stored-attribute array must contain exactly the public attribute values"
            entities[phase][row["name"]] = maps["attributes"]
    assert sum(FIELD_COUNTS.values()) == 35
    assert entities["seed"] == entities["old-reopen"]
    assert receipt["phases"]["seed"]["hostPID"] != receipt["phases"]["old-reopen"]["hostPID"]
    return documents


def mutated_attribute(document, change):
    result = copy.deepcopy(document)
    entity = next(row for row in result["entities"] if row["name"] == "Transcription")
    for key in ["attributes", "storedAttributes"]:
        row = next(value for value in entity[key] if value["name"] == "text")
        change(entity[key], row)
    return result


def run_functions(old, candidate, inputs):
    wrappers = []
    for name, function in [("KnownBad", old), ("Candidate", candidate)]:
        wrappers.append("enum " + name + " {\n" + function + "\n    static func apply(_ value: Any) throws -> Any { try canonicalSchema(value) }\n}\n")
    harness = "import Foundation\n" + "\n".join(wrappers) + '''
let inputs = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [Any]
let results: [String: Any] = [
    "old": try inputs.map { try KnownBad.apply($0) },
    "candidate": try inputs.map { try Candidate.apply($0) }
]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]))
'''
    with tempfile.TemporaryDirectory(prefix="rjt-schema-canonicalization-") as temporary:
        root = Path(temporary)
        source, executable = root / "main.swift", root / "schema-canonicalization"
        source.write_text(harness)
        build = subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(root / "module-cache"), str(source), "-o", str(executable)], capture_output=True, text=True)
        if build.returncode:
            raise RuntimeError("Swift Foundation regression harness failed to compile:\n" + build.stderr)
        result = subprocess.run([str(executable)], input=json.dumps(inputs).encode(), capture_output=True)
        if result.returncode:
            raise RuntimeError("Swift Foundation regression harness failed:\n" + result.stderr.decode(errors="replace"))
        return json.loads(result.stdout)


def check():
    if sys.platform != "darwin":
        raise RuntimeError("This regression requires macOS and xcrun swiftc for the actual Swift Foundation function")
    old_source = subprocess.check_output(["git", "-C", str(REPO), "show", KNOWN_BAD + ":" + SOURCE], text=True)
    old, candidate = extract(old_source), extract((REPO / SOURCE).read_text())
    documents = actual_fixtures()
    inputs = dict(documents)
    base = documents["seed/schema-raw.json"]
    changes = {
        "attribute-type": lambda rows, row: row.update(valueTypeName="MutationType"),
        "attribute-optional": lambda rows, row: row.update(isOptional=not row["isOptional"]),
        "attribute-hash-modifier": lambda rows, row: row.update(hashModifier="changed schema hash"),
        "attribute-default": lambda rows, row: row.update(defaultValue="new default"),
        "attribute-name": lambda rows, row: row.update(name="renamed_text"),
        "attribute-missing": lambda rows, row: rows.remove(row),
        "attribute-duplicate": lambda rows, row: rows.append(copy.deepcopy(row))
    }
    for name, change in changes.items():
        inputs[name] = mutated_attribute(base, change)
    ordered_controls = []
    for key in ["indices", "uniquenessConstraints", "futureOrderedMetadata"]:
        value = copy.deepcopy(base)
        value[key] = [["text", "timestamp"], ["id", "duration"]]
        inputs[key + "-base"] = value
        outer = copy.deepcopy(value)
        outer[key].reverse()
        inputs[key + "-outer-reversed"] = outer
        inner = copy.deepcopy(value)
        inner[key][0].reverse()
        inputs[key + "-inner-reversed"] = inner
        ordered_controls.extend([(key + "-base", key + "-outer-reversed"), (key + "-base", key + "-inner-reversed")])
    results = run_functions(old, candidate, list(inputs.values()))
    old_results = dict(zip(inputs, results["old"], strict=True))
    new_results = dict(zip(inputs, results["candidate"], strict=True))
    for phase in ["seed", "old-reopen"]:
        raw, retained = phase + "/schema-raw.json", phase + "/schema-canonical.json"
        assert old_results[raw] == documents[retained], "Extracted old algorithm must reproduce the actual captured canonical schema"
        assert new_results[raw] == new_results[retained]
        old_rows, new_rows = copy.deepcopy(old_results[raw]), copy.deepcopy(new_results[raw])
        for old_entity, new_entity in zip(old_rows["entities"], new_rows["entities"], strict=True):
            old_attributes = old_entity.pop("storedAttributes")
            new_attributes = new_entity.pop("storedAttributes")
            assert sorted(json.dumps(row, sort_keys=True) for row in old_attributes) == sorted(json.dumps(row, sort_keys=True) for row in new_attributes), "Normalization cannot drop, duplicate or alter a stored attribute"
        assert old_rows == new_rows, "The candidate may change only storedAttributes ordering on these actual fixtures"
    assert old_results["seed/schema-raw.json"] != old_results["old-reopen/schema-raw.json"], "Actual known-bad function did not reproduce the cross-host schema ordering failure"
    expected = new_results["seed/schema-raw.json"]
    assert expected == new_results["old-reopen/schema-raw.json"], "The same real raw schemas must normalize identically"
    for name in changes:
        assert new_results[name] != expected, "Attribute change was hidden by canonicalization: " + name
    for baseline, changed in ordered_controls:
        assert new_results[baseline] != new_results[changed], "Ordered or unknown array order was lost: " + changed
    return {
        "classification": "schema-canonicalization-regression-passed", "known_bad_commit": KNOWN_BAD,
        "known_bad_function_sha256": sha256(old.encode()), "candidate_function_sha256": sha256(candidate.encode()),
        "fixture_sha256": EXPECTED, "unique_attributes_per_schema": 35,
        "actual_old_function_matches_captured_native_canonical_files": True,
        "actual_known_bad_cross_host_outputs_differ": True, "candidate_cross_host_outputs_equal": True,
        "candidate_only_reorders_stored_attributes": True, "attribute_mutations_preserved": list(changes),
        "ordered_array_controls_preserved": [changed for _, changed in ordered_controls],
        "scope": "Actual extracted Swift Foundation function against captured native schema JSON. No app, SwiftData container, migration or current-host execution."
    }


if __name__ == "__main__":
    print(json.dumps(check(), sort_keys=True))
