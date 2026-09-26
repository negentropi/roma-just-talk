#!/usr/bin/env bash

macos_version_is_at_most() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}$ && "$2" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
  awk -v actual="$1" -v maximum="$2" 'BEGIN {
    split(actual, actual_parts, ".")
    split(maximum, maximum_parts, ".")
    for (part_index = 1; part_index <= 3; part_index++) {
      actual_part = actual_parts[part_index] + 0
      maximum_part = maximum_parts[part_index] + 0
      if (actual_part < maximum_part) exit 0
      if (actual_part > maximum_part) exit 1
    }
    exit 0
  }'
}

macos_load_command_records() {
  awk '
    $1 == "cmd" {
      reads_minimum = ($2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX")
      platform = ($2 == "LC_VERSION_MIN_MACOSX" ? "1" : "")
    }
    reads_minimum && $1 == "platform" {
      platform = $2
    }
    reads_minimum && ($1 == "minos" || $1 == "version") {
      print platform "\t" $2
      reads_minimum = 0
    }
  '
}
