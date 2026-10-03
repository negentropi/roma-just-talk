#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo/scripts/build-whisper-upstream-dynamic-experiment.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/roma-whisper-upstream-inputs.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

reject() {
  if "$@" > "$scratch/rejected.log" 2>&1; then
    echo "Expected rejection: $*" >&2
    exit 1
  fi
}

reject bash "$repo/scripts/build-whisper-upstream-dynamic-experiment.sh" --unknown
git clone --quiet --shared --no-checkout "$repo" "$scratch/source"
git -C "$scratch/source" checkout --quiet --detach "$APP_SOURCE_SHA"
python3 -B "$scratch/source/Tools/SwiftDataExactModelProbe/verify-inputs.py" \
  --union "$scratch/source" "$scratch/union.json" > "$scratch/union-receipt.json"
python3 - "$scratch/union.json" "$scratch/union-receipt.json" <<'PY'
import json, sys
union, receipt = [json.load(open(p)) for p in sys.argv[1:]]
assert len(union['pins']) == receipt['unionPinCount'] == 41
assert receipt['unionSHA256'] == 'b9b2810ec36cbd89289804ac8ee83d894bc6231d3e08ec8887bec8d08c540a45'
PY
project="$scratch/source/VoiceInk.xcodeproj/project.pbxproj"
cp "$project" "$scratch/original-project.pbxproj"
patch_dynamic_project "$project" "$scratch/whisper.xcframework"
plutil -lint "$project"
python3 - "$project" "$scratch/whisper.xcframework" <<'PY'
import json, subprocess, sys
objects = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', sys.argv[1]]))['objects']
phase = objects['E1A8C8CD2E1257B7003E58EC']
whisper = objects['D10000012FA0000000000001']
assert whisper['settings']['ATTRIBUTES'] == ['CodeSignOnCopy', 'RemoveHeadersOnCopy']
assert phase['files'] == ['E1D7EF9A2E35E19B00640029', 'D10000012FA0000000000001']
assert objects[whisper['fileRef']]['path'] == sys.argv[2]
PY
cp "$project" "$scratch/patched-project.pbxproj"
reject patch_dynamic_project "$project" "$scratch/other.xcframework"
cmp "$project" "$scratch/patched-project.pbxproj"
cp "$scratch/original-project.pbxproj" "$project"
reject patch_dynamic_project "$project" $'unsupported\npath'
cmp "$project" "$scratch/original-project.pbxproj"
printf '\n' >> "$scratch/source/$PROJECT_LOCK_PATH"
reject python3 -B "$scratch/source/Tools/SwiftDataExactModelProbe/verify-inputs.py" \
  --union "$scratch/source" "$scratch/invalid-union.json"

ruby -ryaml - "$repo/.github/workflows/roma-whisper-upstream-dynamic.yml" <<'RUBY'
text = File.read(ARGV.fetch(0))
workflow = YAML.safe_load(text)
raise 'Unexpected permissions' unless workflow.fetch('permissions') == {'contents' => 'read'}
triggers = workflow['on'] || workflow[true]
raise 'Unexpected transport' unless triggers.fetch('push').fetch('branches') == ['ci/roma-whisper-upstream-dynamic-*']
raise 'Missing manual dispatch' unless triggers.key?('workflow_dispatch')
job = workflow.fetch('jobs').fetch('diagnostic-build')
raise 'Unexpected runner' unless job.fetch('runs-on') == 'macos-26'
raise 'Unexpected timeout' unless job.fetch('timeout-minutes') == 90
checkout = job.fetch('steps').find { |step| step['uses'] == 'actions/checkout@v4' }
raise 'Incomplete source history' unless checkout.fetch('with').fetch('fetch-depth') == 0
raise 'Persisted credentials' unless checkout.fetch('with').fetch('persist-credentials') == false
artifact = job.fetch('steps').find { |step| step['uses'] == 'actions/upload-artifact@v4' }
raise 'Unexpected artifact' unless artifact.fetch('with').fetch('name') == 'roma.whisper-upstream-dynamic-D'
raise 'Production authority in diagnostic workflow' if text.include?('secrets.') || text.include?('contents: write')
RUBY
echo 'PASS normal Whisper project embedding, exact input union, rejection cases and diagnostic workflow; no app runtime proof'
