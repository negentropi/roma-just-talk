#!/bin/zsh
[[ "$1" == 'E7BF9432-99B7-496A-81E3-4D937F84131F' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/race-0-D4200326-87B6-48EE-9C0F-52B6D77B35A0-9A0915F2-AB34-451C-AA69-F7FDD4E19B68/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
