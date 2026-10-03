#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 || ! "$2" =~ ^[A-Z0-9]{10}$ || ! "$3" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
  echo "usage: $0 <app> <expected-developer-id-team> <expected-signing-identifier> <evidence-directory>" >&2
  exit 2
fi
app="$1"
team="$2"
identifier="$3"
evidence="$4"
mkdir -p "$evidence"
[[ ! -e "$evidence/trust-verdict.txt" ]] \
  || { echo 'Trust verdict already exists' >&2; exit 2; }

requirement="=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[subject.OU] = \"$team\" and identifier \"$identifier\""
codesign --verify --deep --strict --test-requirement="$requirement" "$app" \
  > "$evidence/developer-id-verification.txt" 2>&1
codesign --display --verbose=4 "$app" > "$evidence/signature.txt" 2>&1
grep -Eq '^CodeDirectory .*flags=.*\(.*runtime.*\)' "$evidence/signature.txt"
xcrun stapler validate "$app" > "$evidence/stapled-ticket.txt" 2>&1
spctl --assess --type execute --verbose=4 "$app" \
  > "$evidence/gatekeeper-assessment.txt" 2>&1
grep -Fxq 'source=Notarized Developer ID' "$evidence/gatekeeper-assessment.txt"
if grep -Eq '^override=' "$evidence/gatekeeper-assessment.txt"; then
  echo 'Gatekeeper assessment used a policy override' >&2
  exit 1
fi
printf 'trust_verdict=passed\ndeveloper_id_team=%s\nsigning_identifier=%s\n' "$team" "$identifier" > "$evidence/trust-verdict.txt"
