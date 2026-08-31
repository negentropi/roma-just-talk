#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <volume> <downloaded-outer-zip> <expected-inner-sha256> <app-name>" >&2
  exit 2
fi

volume="${1%/}"
downloaded_outer="$2"
expected_inner_sha256="$3"
app_name="$4"

[[ -d "$volume" ]] || {
  echo "Finder extraction volume is missing: $volume" >&2
  exit 2
}
[[ -f "$downloaded_outer" ]] || {
  echo "Downloaded outer ZIP is missing: $downloaded_outer" >&2
  exit 2
}
[[ "$expected_inner_sha256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Expected inner SHA-256 is invalid" >&2
  exit 2
}

apps=()
while IFS= read -r candidate; do
  apps+=("$candidate")
done < <(find "$volume" -type d -name "$app_name" -prune -print 2>/dev/null)

inner_archives=()
unexpected_archives=()
while IFS= read -r candidate; do
  [[ "$candidate" != "$downloaded_outer" ]] || continue
  candidate_sha256="$(shasum -a 256 "$candidate" | awk '{print $1}')"
  if [[ "$candidate_sha256" == "$expected_inner_sha256" ]]; then
    inner_archives+=("$candidate")
  else
    unexpected_archives+=("$candidate")
  fi
done < <(
  find "$volume" \
    -type d -name "$app_name" -prune \
    -o -type f -name '*.zip' -print \
    2>/dev/null
)

state="invalid"
if [[ "${#apps[@]}" -eq 0 \
  && "${#inner_archives[@]}" -eq 0 \
  && "${#unexpected_archives[@]}" -eq 0 ]]; then
  state="pending"
elif [[ "${#apps[@]}" -eq 1 \
  && "${#inner_archives[@]}" -le 1 \
  && "${#unexpected_archives[@]}" -eq 0 ]]; then
  state="recursive"
elif [[ "${#apps[@]}" -eq 0 \
  && "${#inner_archives[@]}" -eq 1 \
  && "${#unexpected_archives[@]}" -eq 0 ]]; then
  state="separate"
fi

printf 'state\t%s\n' "$state"
printf 'app_count\t%s\n' "${#apps[@]}"
printf 'inner_count\t%s\n' "${#inner_archives[@]}"
printf 'unexpected_archive_count\t%s\n' "${#unexpected_archives[@]}"
if [[ "${#apps[@]}" -eq 1 ]]; then
  printf 'app_path\t%s\n' "${apps[0]}"
fi
if [[ "${#inner_archives[@]}" -eq 1 ]]; then
  printf 'inner_path\t%s\n' "${inner_archives[0]}"
fi
