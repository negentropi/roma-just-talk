#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/roma-notarized-contract.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

check_contract() {
  env DISTRIBUTION_E2E_LAUNCH_CONTRACT="$1" \
    DISTRIBUTION_E2E_DEVELOPER_ID_TEAM="$2" \
    DISTRIBUTION_E2E_FINAL_ARCHIVE_URL="$3" \
    bash -c 'distribution_expectation="$2"; source "$1"; printf "%s" "$distribution_require_translocation"' \
      _ "$root/scripts/macos-distribution-contract.sh" "$4"
}
[[ "$(check_contract adhoc-approval '' '' fixed)" == true ]]
[[ "$(check_contract notarized-first-open ABCDE12345 https://example.invalid/final.zip fixed)" == false ]]
for expectation in known-bad-framework-signature fixed-after-framework-signature; do
  if check_contract notarized-first-open ABCDE12345 https://example.invalid/final.zip "$expectation" > "$scratch/out" 2>&1; then
    echo 'Normal first Open accepted an ad-hoc regression expectation' >&2; exit 1
  fi
done
for url in '' http://example.invalid/final.zip https://user:pass@example.invalid/final.zip \
  'https://example.invalid/final.zip#fragment' $'\nhttps://example.invalid/final.zip' \
  $'https://example.invalid/fi\tnal.zip' 'https://example.invalid:bad/final.zip' \
  'https://example.invalid:0/final.zip' 'https://example.invalid:65536/final.zip'; do
  if check_contract notarized-first-open ABCDE12345 "$url" fixed > "$scratch/out" 2>&1; then
    echo 'Normal first Open accepted an invalid final URL' >&2; exit 1
  fi
done
if check_contract adhoc-approval ABCDE12345 https://example.invalid/final.zip fixed > "$scratch/out" 2>&1 \
  || check_contract unknown '' '' fixed > "$scratch/out" 2>&1 \
  || check_contract notarized-first-open '' https://example.invalid/final.zip fixed > "$scratch/out" 2>&1; then
  echo 'Invalid distribution contract accepted' >&2; exit 1
fi

eval "$(sed -n '/^wait_for_matching_browser_download()/,/^}/p' "$root/scripts/run-macos-distribution-e2e.sh")"
volume="$scratch/downloads"
mkdir "$volume"
printf 'final app ZIP fixture' > "$volume/final.zip"
printf 'Actions wrapper with another ZIP inside' > "$volume/wrapper.zip"
download_expected_size="$(stat -f '%z' "$volume/final.zip")"
download_expected_sha256="$(shasum -a 256 "$volume/final.zip" | awk '{print $1}')"
[[ "$(wait_for_matching_browser_download "$((SECONDS + 5))")" == "$volume/final.zip" ]]
mv "$volume/final.zip" "$scratch/final.zip"
if wait_for_matching_browser_download "$((SECONDS + 1))" > "$scratch/out"; then
  echo 'Final download matcher accepted the Actions wrapper' >&2; exit 1
fi
download_expected_size="$(stat -f '%z' "$volume/wrapper.zip")"
download_expected_sha256="$(shasum -a 256 "$volume/wrapper.zip" | awk '{print $1}')"
[[ "$(wait_for_matching_browser_download "$((SECONDS + 5))")" == "$volume/wrapper.zip" ]]

python3 - "$root" "$scratch" <<'PY'
import json, os, re, subprocess, sys, textwrap
from pathlib import Path
root, scratch = map(Path, sys.argv[1:])
workflow = (root / '.github/workflows/voiceink-remote-e2e-stage.yml').read_text()
assert 'STAGE_MACOS_FINAL_ARCHIVE_URL' not in workflow
assert 'DISTRIBUTION_E2E_FINAL_ARCHIVE_URL: ${{' not in workflow
block = re.search(r'(          FINAL_URL_FILE=.*?)(?=          bash scripts/prepare-remote-e2e-stage.sh)', workflow, re.S)
assert block is not None
value = 'https://example.invalid/final.zip?token=fixture%2Bprivate'
event = scratch / 'event.json'
event.write_text(json.dumps({'inputs': {'macos_final_archive_url': value}}))
preexisting = scratch / 'roma-final-archive-url.preexisting'
preexisting.write_text('preserve this unrelated file')
environment = dict(os.environ, GITHUB_EVENT_PATH=str(event), RUNNER_TEMP=str(scratch))
script = textwrap.dedent(block.group(1)) + '''
python3 - <<'CHECK'
import json, os, stat
from pathlib import Path
path = Path(os.environ['FINAL_URL_FILE'])
expected = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())['inputs']['macos_final_archive_url']
assert os.environ['DISTRIBUTION_E2E_FINAL_ARCHIVE_URL'] == expected
assert path.read_text() == expected
assert stat.S_IMODE(path.stat().st_mode) == 0o600
CHECK
'''
result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script], env=environment, text=True, capture_output=True)
assert result.returncode == 0, result.stderr
assert result.stdout == '::add-mask::' + value.replace('%', '%25') + '\n'
assert list(scratch.glob('roma-final-archive-url.*')) == [preexisting]
assert preexisting.read_text() == 'preserve this unrelated file'
event.write_text(json.dumps({'inputs': {'macos_final_archive_url': value + '\n'}}))
result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script], env=environment, text=True, capture_output=True)
assert result.returncode != 0 and 'Invalid final archive URL input' in result.stderr
assert list(scratch.glob('roma-final-archive-url.*')) == [preexisting]
PY

mkdir "$scratch/bin"
cat > "$scratch/bin/codesign" <<'SH'
#!/bin/bash
set -euo pipefail
case "$1" in
  --verify)
    [[ "$*" == *'--deep --strict --test-requirement==anchor apple generic'* ]] || exit 1
    [[ "$*" == *'certificate leaf[subject.OU] = "ABCDE12345"'* ]] || exit 1
    [[ "$*" == *'and identifier "com.example.Roma"'* ]] || exit 1
    [[ "${TRUST_FAILURE:-}" != identity ]] || exit 1
    if [[ "${TRUST_FAILURE:-}" == verify-exit ]]; then echo 'verification successful'; exit 17; fi
    ;;
  --display)
    if [[ "${TRUST_FAILURE:-}" == runtime ]]; then
      echo 'CodeDirectory v=20500 flags=0x0(none)'
    else
      echo 'CodeDirectory v=20500 flags=0x10000(runtime)'
    fi
    if [[ "${TRUST_FAILURE:-}" == display-exit ]]; then exit 18; fi
    ;;
  *) exit 1 ;;
esac
SH
cat > "$scratch/bin/xcrun" <<'SH'
#!/bin/bash
[[ "$1 $2" == 'stapler validate' && "${TRUST_FAILURE:-}" != ticket ]]
command_status=$?
echo 'The validate action worked!'
if [[ "${TRUST_FAILURE:-}" == ticket-exit ]]; then exit 19; fi
exit "$command_status"
SH
cat > "$scratch/bin/spctl" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$*" == '--assess --type execute --verbose=4 '* ]] || exit 1
[[ "${TRUST_FAILURE:-}" != assessment ]] || exit 1
echo 'fixture.app: accepted'
if [[ "${TRUST_FAILURE:-}" == source ]]; then
  echo 'source=Developer ID'
else
  echo 'source=Notarized Developer ID'
fi
if [[ "${TRUST_FAILURE:-}" == override ]]; then echo 'override=security disabled'; fi
if [[ "${TRUST_FAILURE:-}" == assessment-exit ]]; then exit 20; fi
exit 0
SH
chmod +x "$scratch/bin/"*
PATH="$scratch/bin:$PATH" bash "$root/scripts/verify-macos-notarized-app.sh" fixture.app ABCDE12345 com.example.Roma "$scratch/trusted"
grep -Fxq 'trust_verdict=passed' "$scratch/trusted/trust-verdict.txt"
python3 - "$scratch/trusted" <<'PY'
import hashlib, json, sys
from datetime import datetime
from pathlib import Path
root = Path(sys.argv[1])
receipt = json.loads((root / 'trust-command-receipts.json').read_text())
assert receipt['schemaVersion'] == 1
assert receipt['developerIdTeam'] == 'ABCDE12345'
assert receipt['signingIdentifier'] == 'com.example.Roma'
assert [command['name'] for command in receipt['commands']] == [
    'codesign-verify', 'codesign-display', 'stapler-validate', 'gatekeeper-assess']
for command in receipt['commands']:
    assert command['argv'][-1] == receipt['app']
    assert command['exitStatus'] == 0
    assert command['timedOut'] is False
    assert datetime.fromisoformat(command['startedAt'].replace('Z', '+00:00')) <= datetime.fromisoformat(command['endedAt'].replace('Z', '+00:00'))
    for stream in ('stdout', 'stderr'):
        record = command[stream]
        raw = (root / record['path']).read_bytes()
        assert len(raw) == record['size']
        assert hashlib.sha256(raw).hexdigest() == record['sha256']
PY
for failure in identity runtime ticket assessment source override verify-exit display-exit ticket-exit assessment-exit; do
  if PATH="$scratch/bin:$PATH" TRUST_FAILURE="$failure" \
    bash "$root/scripts/verify-macos-notarized-app.sh" fixture.app ABCDE12345 com.example.Roma "$scratch/$failure" > "$scratch/out" 2>&1; then
    echo "Trust gate accepted $failure failure" >&2; exit 1
  fi
  [[ ! -e "$scratch/$failure/trust-verdict.txt" ]]
done
failed_receipt_sha="$(shasum -a 256 "$scratch/verify-exit/trust-command-receipts.json" | awk '{print $1}')"
if PATH="$scratch/bin:$PATH" bash "$root/scripts/verify-macos-notarized-app.sh" fixture.app ABCDE12345 com.example.Roma "$scratch/verify-exit" > "$scratch/out" 2>&1; then
  echo 'Trust gate reused an existing failed receipt' >&2; exit 1
fi
[[ "$(shasum -a 256 "$scratch/verify-exit/trust-command-receipts.json" | awk '{print $1}')" == "$failed_receipt_sha" ]]
python3 - "$scratch" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
for name, status in [('verify-exit', 17), ('display-exit', 18), ('ticket-exit', 19), ('assessment-exit', 20)]:
    directory = root / name
    receipt = json.loads((directory / 'trust-command-receipts.json').read_text())
    assert receipt['commands'][-1]['exitStatus'] == status
    assert not (directory / 'trust-verdict.txt').exists()
    for command in receipt['commands']:
        for channel in ('stdout', 'stderr'):
            output = command[channel]
            assert hashlib.sha256((directory / output['path']).read_bytes()).hexdigest() == output['sha256']
    assert (directory / receipt['commands'][-1]['stdout']['path']).stat().st_size > 0
PY
if PATH="$scratch/bin:$PATH" bash "$root/scripts/verify-macos-notarized-app.sh" fixture.app ABCDE12345 com.example.Roma "$scratch/trusted" > "$scratch/out" 2>&1; then
  echo 'Trust gate reused an existing verdict' >&2; exit 1
fi
if PATH="$scratch/bin:$PATH" bash "$root/scripts/verify-macos-notarized-app.sh" fixture.app ABCDE12345 com.example.Other "$scratch/wrong-identifier" > "$scratch/out" 2>&1; then
  echo 'Trust gate accepted the wrong signing identifier' >&2; exit 1
fi
echo 'Distribution contract validation and trust failure handling passed; mocks do not prove notarization or launch'
