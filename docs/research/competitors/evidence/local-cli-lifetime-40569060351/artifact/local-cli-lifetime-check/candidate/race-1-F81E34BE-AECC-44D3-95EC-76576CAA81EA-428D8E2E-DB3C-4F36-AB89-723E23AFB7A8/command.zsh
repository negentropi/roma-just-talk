#!/bin/zsh
[[ "$1" == 'BFCC02FA-2A37-4913-9618-A781A560F7AD' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/race-1-F81E34BE-AECC-44D3-95EC-76576CAA81EA-428D8E2E-DB3C-4F36-AB89-723E23AFB7A8/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
