#!/usr/bin/env bash

write_macos_bundle_manifest() {
  local bundle="$1"
  local output="$2"
  local file relative sha256

  : > "$output"
  while IFS= read -r file; do
    relative="${file#"$bundle"/}"
    sha256="$(shasum -a 256 "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sha256" "$relative" >> "$output"
  done < <(find "$bundle" -type f -print | LC_ALL=C sort)
  while IFS= read -r file; do
    relative="${file#"$bundle"/}"
    printf 'symlink  %s -> %s\n' "$relative" "$(readlink "$file")" >> "$output"
  done < <(find "$bundle" -type l -print | LC_ALL=C sort)
}
