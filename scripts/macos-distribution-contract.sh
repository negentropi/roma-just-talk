#!/usr/bin/env bash

distribution_launch_contract="${DISTRIBUTION_E2E_LAUNCH_CONTRACT:-adhoc-approval}"
distribution_developer_id_team="${DISTRIBUTION_E2E_DEVELOPER_ID_TEAM:-}"
distribution_final_archive_url="${DISTRIBUTION_E2E_FINAL_ARCHIVE_URL:-}"
case "$distribution_launch_contract" in
  adhoc-approval)
    distribution_require_translocation=true
    if [[ -n "$distribution_developer_id_team" || -n "$distribution_final_archive_url" ]]; then
      echo 'Developer ID and final archive URL require notarized-first-open' >&2
      exit 2
    fi
    ;;
  notarized-first-open)
    distribution_require_translocation=false
    if [[ "${distribution_expectation:-fixed}" != fixed ]]; then
      echo 'Notarized first Open requires a fixed candidate, not an ad-hoc negative control' >&2
      exit 2
    fi
    if [[ ! "$distribution_developer_id_team" =~ ^[A-Z0-9]{10}$ ]]; then
      echo 'Notarized first Open requires the expected Developer ID team' >&2
      exit 2
    fi
    if ! DISTRIBUTION_FINAL_ARCHIVE_URL="$distribution_final_archive_url" python3 - <<'PY'
import os, sys
from urllib.parse import urlsplit
try:
    raw = os.environ['DISTRIBUTION_FINAL_ARCHIVE_URL']
    url = urlsplit(raw)
    port = url.port
    valid = (url.scheme == 'https' and bool(url.hostname) and
             url.username is None and url.password is None and not url.fragment and
             (port is None or 1 <= port <= 65535) and
             not any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in raw))
except ValueError:
    valid = False
sys.exit(0 if valid else 1)
PY
    then
      echo 'Notarized first Open requires an HTTPS final app ZIP URL without user credentials' >&2
      exit 2
    fi
    ;;
  *)
    echo "Unsupported distribution launch contract: $distribution_launch_contract" >&2
    exit 2
    ;;
esac
