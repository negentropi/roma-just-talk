#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
fixtures = root / "scripts/tests/fixtures/macos-build-job"
job_name = "Build reusable runtime E2E helper"

def query(value, expression, run_id):
    return subprocess.run(
        ["jq", "-e", "-L", str(root / "scripts"), "--argjson", "run_id", str(run_id),
         "--arg", "run_text", str(run_id), "--arg", "job_name", job_name,
         'include "macos-build-job"; ' + expression],
        input=json.dumps(value), text=True, capture_output=True,
    )

def select(value, expected_provider):
    run_id = value["jobs"][0]["run_id"]
    result = query(value, "select_macos_build_job($run_id; $job_name)", run_id)
    assert result.returncode == 0, result.stderr
    record = json.loads(result.stdout)
    assert record["job"]["provider"] == expected_provider
    assert record["job"]["runnerLabels"] == value["jobs"][0]["labels"]
    assert query(record, "valid_macos_build_job_record($run_text; $job_name)", run_id).returncode == 0
    return record

def reject(value):
    run_id = value["jobs"][0]["run_id"]
    assert query(value, "select_macos_build_job($run_id; $job_name)", run_id).returncode != 0

hosted = json.loads((fixtures / "hosted-helper.json").read_text())
namespace = json.loads((fixtures / "namespace-helper.json").read_text())
hosted_record = select(hosted, "github-hosted")
select(namespace, "namespace")

for fixture in (hosted, namespace):
    for field, value in (
        ("id", 0), ("id", 1.5), ("runner_id", None), ("runner_id", 0),
        ("runner_id", 1.5), ("runner_name", ""),
        ("name", "Other job"), ("status", "in_progress"), ("conclusion", "failure"),
        ("conclusion", "skipped"), ("labels", []), ("labels", ["ubuntu-latest"]),
        ("labels", [None]), ("labels", None),
    ):
        invalid = copy.deepcopy(fixture)
        invalid["jobs"][0][field] = value
        reject(invalid)
    duplicate = copy.deepcopy(fixture)
    duplicate["jobs"].append(copy.deepcopy(duplicate["jobs"][0]))
    reject(duplicate)
    duplicate["jobs"][1]["conclusion"] = "failure"
    reject(duplicate)

for field, value in (("runner_group_name", "Default"), ("runner_name", "self-hosted-mac")):
    invalid = copy.deepcopy(hosted)
    invalid["jobs"][0][field] = value
    reject(invalid)

run_id = hosted["jobs"][0]["run_id"]
assert query(hosted, "select_macos_build_job($run_id; $job_name)", run_id + 1).returncode != 0
assert query({"jobs": []}, "select_macos_build_job($run_id; $job_name)", run_id).returncode != 0
assert query({"jobs": {"one": hosted["jobs"][0]}}, "select_macos_build_job($run_id; $job_name)", run_id).returncode != 0
for mutation in (
    lambda r: r.update(runId=run_id + 1),
    lambda r: r["job"].update(provider="namespace"),
    lambda r: r["job"].update(runnerLabels=["ubuntu-latest"]),
):
    invalid = copy.deepcopy(hosted_record)
    mutation(invalid)
    assert query(invalid, "valid_macos_build_job_record($run_text; $job_name)", run_id).returncode != 0

print("Mac build job provider selection and receipt rejection passed")
PY
