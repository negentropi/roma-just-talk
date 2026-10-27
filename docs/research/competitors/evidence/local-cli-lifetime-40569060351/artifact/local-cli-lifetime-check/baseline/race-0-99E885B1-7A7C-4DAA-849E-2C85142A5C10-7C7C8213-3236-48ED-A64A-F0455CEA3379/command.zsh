#!/bin/zsh
[[ "$1" == 'D961FDAF-53D6-4BF5-85A5-C302D0595A6F' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/race-0-99E885B1-7A7C-4DAA-849E-2C85142A5C10-7C7C8213-3236-48ED-A64A-F0455CEA3379/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
