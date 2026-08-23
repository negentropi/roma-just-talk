#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-ci-reuse.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/bin"
cat >"$fixture_root/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

endpoint=""
has_arg() {
  local expected="$1"
  shift
  local arg
  for arg in "$@"; do
    [[ "$arg" == "$expected" ]] && return 0
  done
  return 1
}

for arg in "$@"; do
  if [[ "$arg" == repos/* ]]; then
    endpoint="$arg"
  fi
done

case "$endpoint" in
  */actions/workflows/*/runs)
    has_arg "--paginate" "$@"
    has_arg "--slurp" "$@"
    has_arg "head_sha=0123456789abcdef0123456789abcdef01234567" "$@"
    has_arg "status=success" "$@"
    has_arg "per_page=100" "$@"
    cat <<'JSON'
[{"workflow_runs":[{"id":404},{"id":303},{"id":202},{"id":101}]}]
JSON
    ;;
  */actions/runs/404/artifacts)
    cat <<'JSON'
[{"artifacts":[{"name":"app","expired":false,"size_in_bytes":10},{"name":"proof","expired":false,"size_in_bytes":0}]}]
JSON
    ;;
  */actions/runs/303/artifacts)
    has_arg "--paginate" "$@"
    has_arg "--slurp" "$@"
    has_arg "per_page=100" "$@"
    cat <<'JSON'
[{"artifacts":[{"name":"app","expired":true,"size_in_bytes":10}]}]
JSON
    ;;
  */actions/runs/202/artifacts)
    cat <<'JSON'
[{"artifacts":[{"name":"app","expired":false,"size_in_bytes":10}]},{"artifacts":[{"name":"proof","expired":false,"size_in_bytes":20}]}]
JSON
    ;;
  */actions/runs/101/artifacts)
    cat <<'JSON'
[{"artifacts":[{"name":"app","expired":false,"size_in_bytes":10}]}]
JSON
    ;;
  *)
    echo "unexpected endpoint: $endpoint" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fixture_root/bin/gh"

export PATH="$fixture_root/bin:$PATH"
export GITHUB_REPOSITORY="owner/repository"
export GITHUB_OUTPUT="$fixture_root/output"

bash "$repo_root/scripts/find-reusable-ci-run.sh" \
  voiceink-build.yml \
  0123456789abcdef0123456789abcdef01234567 \
  app \
  proof

grep -Fxq 'hit=true' "$GITHUB_OUTPUT"
grep -Fxq 'run_id=202' "$GITHUB_OUTPUT"

: >"$GITHUB_OUTPUT"
bash "$repo_root/scripts/find-reusable-ci-run.sh" \
  voiceink-build.yml \
  0123456789abcdef0123456789abcdef01234567 \
  missing

grep -Fxq 'hit=false' "$GITHUB_OUTPUT"
grep -Fxq 'run_id=' "$GITHUB_OUTPUT"

if bash "$repo_root/scripts/find-reusable-ci-run.sh" \
  ../unsafe.yml \
  0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; then
  echo "unsafe workflow filename should fail" >&2
  exit 1
fi

if bash "$repo_root/scripts/find-reusable-ci-run.sh" \
  voiceink-build.yml \
  not-a-sha >/dev/null 2>&1; then
  echo "invalid commit SHA should fail" >&2
  exit 1
fi

echo "Exact-SHA CI reuse checks passed."
