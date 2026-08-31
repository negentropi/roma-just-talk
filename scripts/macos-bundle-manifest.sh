#!/usr/bin/env bash

write_macos_bundle_manifest() {
  local bundle="$1"
  local output="$2"
  local file relative sha256 mode

  : > "$output"
  while IFS= read -r file; do
    relative="${file#"$bundle"}"
    relative="${relative#/}"
    [[ -n "$relative" ]] || relative="."
    mode="$(stat -f '%Lp' "$file")"
    printf 'directory  mode=%s  %s\n' "$mode" "$relative" >> "$output"
  done < <(find "$bundle" -type d -print | LC_ALL=C sort)
  while IFS= read -r file; do
    relative="${file#"$bundle"/}"
    sha256="$(shasum -a 256 "$file" | awk '{print $1}')"
    mode="$(stat -f '%Lp' "$file")"
    printf '%s  mode=%s  %s\n' "$sha256" "$mode" "$relative" >> "$output"
  done < <(find "$bundle" -type f -print | LC_ALL=C sort)
  while IFS= read -r file; do
    relative="${file#"$bundle"/}"
    printf 'symlink  %s -> %s\n' "$relative" "$(readlink "$file")" >> "$output"
  done < <(find "$bundle" -type l -print | LC_ALL=C sort)
}

compare_macos_bundle_to_manifest() {
  local bundle="$1"
  local expected="$2"
  local observed="$3"
  local difference="$4"

  write_macos_bundle_manifest "$bundle" "$observed"
  if cmp -s "$expected" "$observed"; then
    rm -f "$difference"
    return 0
  fi
  diff -u "$expected" "$observed" > "$difference" || true
  return 1
}
