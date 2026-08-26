#!/usr/bin/env bash

runtime_model_file_valid() {
  local file="$1"
  local expected_size="$2"
  local expected_sha256="$3"
  local actual_size
  local actual_sha256

  [ -f "$file" ] || return 1
  actual_size="$(wc -c < "$file" | tr -d ' ')"
  [ "$actual_size" = "$expected_size" ] || return 1
  actual_sha256="$(shasum -a 256 "$file" | awk '{print $1}')"
  [ "$actual_sha256" = "$expected_sha256" ]
}

runtime_model_manifest_shape_valid() {
  local manifest="$1"
  local expected_file_count="${2:-22}"
  local expected_sha256
  local expected_size
  local relative_path
  local extra
  local seen_paths="|"
  local file_count=0

  [ -s "$manifest" ] || return 1
  [[ "$expected_file_count" =~ ^[1-9][0-9]*$ ]] || return 1
  [ -z "$(tail -c 1 "$manifest")" ] || return 1
  while read -r expected_sha256 expected_size relative_path extra; do
    case "$expected_sha256" in
      ""|'#'*) continue ;;
    esac
    case "$relative_path" in
      ""|/*|..|../*|*/../*|*/..) return 1 ;;
    esac
    [ -z "${extra:-}" ] || return 1
    [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$expected_size" =~ ^[0-9]+$ ]] || return 1
    [[ "$relative_path" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
    case "$seen_paths" in
      *"|$relative_path|"*) return 1 ;;
    esac
    seen_paths="$seen_paths$relative_path|"
    file_count=$((file_count + 1))
  done < "$manifest"

  [ "$file_count" -eq "$expected_file_count" ]
}

runtime_model_manifest_valid() {
  local manifest="$1"
  local model_directory="$2"
  local expected_file_count="${3:-22}"
  local expected_sha256
  local expected_size
  local relative_path

  runtime_model_manifest_shape_valid "$manifest" "$expected_file_count" || return 1
  while read -r expected_sha256 expected_size relative_path _; do
    case "$expected_sha256" in
      ""|'#'*) continue ;;
    esac
    runtime_model_file_valid \
      "$model_directory/$relative_path" \
      "$expected_size" \
      "$expected_sha256" || return 1
  done < "$manifest"
}

runtime_hydrate_model_partition() {
  local manifest="$1"
  local model_directory="$2"
  local source_base_url="$3"
  local nsc_bin="$4"
  local partition_index="$5"
  local partition_count="$6"
  local expected_sha256
  local expected_size
  local relative_path
  local destination
  local temporary
  local entry_index=0

  while read -r expected_sha256 expected_size relative_path _; do
    case "$expected_sha256" in
      ""|'#'*) continue ;;
    esac
    if [ $((entry_index % partition_count)) -ne "$partition_index" ]; then
      entry_index=$((entry_index + 1))
      continue
    fi
    entry_index=$((entry_index + 1))

    destination="$model_directory/$relative_path"
    if runtime_model_file_valid "$destination" "$expected_size" "$expected_sha256"; then
      continue
    fi

    mkdir -p "$(dirname "$destination")"
    temporary="$destination.runtime-download.$$"
    test ! -e "$temporary"
    if ! "$nsc_bin" artifact cache-url \
      "$source_base_url/$relative_path" \
      --out="$temporary"; then
      rm -f "$temporary"
      return 1
    fi
    if ! runtime_model_file_valid "$temporary" "$expected_size" "$expected_sha256"; then
      echo "Pinned runtime model file failed verification: $relative_path" >&2
      rm -f "$temporary"
      return 1
    fi
    mv -f "$temporary" "$destination"
  done < "$manifest"
}

runtime_prepare_pinned_model() {
  local manifest="$1"
  local model_directory="$2"
  local source_base_url="$3"
  local nsc_bin="$4"
  local source_output="$5"
  local expected_file_count="${6:-22}"
  local partition_count="${7:-4}"
  local partition_index
  local partition_pid
  local prepare_status=0
  local partition_pids=()

  runtime_model_manifest_shape_valid "$manifest" "$expected_file_count" || return 2
  [[ "$partition_count" =~ ^[1-9][0-9]*$ ]] || return 2
  [ "$partition_count" -le "$expected_file_count" ] || return 2
  if runtime_model_manifest_valid "$manifest" "$model_directory" "$expected_file_count"; then
    printf '%s\n' verified-existing > "$source_output"
    return 0
  fi

  mkdir -p "$model_directory"
  partition_index=0
  while [ "$partition_index" -lt "$partition_count" ]; do
    runtime_hydrate_model_partition \
      "$manifest" \
      "$model_directory" \
      "$source_base_url" \
      "$nsc_bin" \
      "$partition_index" \
      "$partition_count" &
    partition_pids+=("$!")
    partition_index=$((partition_index + 1))
  done
  for partition_pid in "${partition_pids[@]}"; do
    if ! wait "$partition_pid"; then
      prepare_status=1
    fi
  done
  [ "$prepare_status" -eq 0 ] || return 1
  runtime_model_manifest_valid \
    "$manifest" \
    "$model_directory" \
    "$expected_file_count" || return 1

  printf '%s\n' namespace-url-artifact > "$source_output"
}

runtime_write_model_receipt() {
  local manifest="$1"
  local model_directory="$2"
  local output="$3"
  local expected_file_count="${4:-22}"
  local expected_sha256
  local expected_size
  local relative_path
  local file
  local actual_sha256
  local actual_size
  local temporary="$output.pending.$$"

  runtime_model_manifest_shape_valid "$manifest" "$expected_file_count" || return 2
  test ! -e "$temporary"
  : > "$temporary"
  while read -r expected_sha256 expected_size relative_path _; do
    case "$expected_sha256" in
      ""|'#'*) continue ;;
    esac
    file="$model_directory/$relative_path"
    if [ ! -f "$file" ]; then
      rm -f "$temporary"
      return 1
    fi
    actual_size="$(wc -c < "$file" | tr -d ' ')"
    actual_sha256="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [ "$actual_size" != "$expected_size" ] \
      || [ "$actual_sha256" != "$expected_sha256" ]; then
      rm -f "$temporary"
      return 1
    fi
    printf '%s %s %s\n' "$actual_sha256" "$actual_size" "$relative_path" \
      >> "$temporary"
  done < "$manifest"
  mv -f "$temporary" "$output"
}

runtime_wait_background_job() {
  local job_pid="$1"

  [ -n "$job_pid" ] || return 0
  wait "$job_pid" 2>/dev/null || true
}
