#!/bin/zsh
trap '' TERM
[[ "$1" == '63CF529F-5CA9-48C3-B1B4-C101FC4B5FFE' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/cancel-49CF949C-366E-4BC6-8C47-3F238C379050-D80CC86D-6810-4C99-96EE-EAB027187F00/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'CANCEL_FINISHED'
