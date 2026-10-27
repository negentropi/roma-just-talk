#!/bin/zsh
[[ "$1" == '4F556846-6206-49D5-9D4C-B74AFE407F18' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/changed-8CF5D33E-AD4E-4E9C-8DB1-937AEDEECCDD-F4E9B6BB-A4FB-4B34-981E-81E9B8B129F7/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'WRONG_COMMAND'
