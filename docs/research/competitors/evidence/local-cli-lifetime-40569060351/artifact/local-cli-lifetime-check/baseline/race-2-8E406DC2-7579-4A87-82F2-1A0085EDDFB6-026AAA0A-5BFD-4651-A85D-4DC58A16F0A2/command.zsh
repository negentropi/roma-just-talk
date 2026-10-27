#!/bin/zsh
[[ "$1" == '62852C0C-1396-4DA1-9447-7B641168C6E8' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/race-2-8E406DC2-7579-4A87-82F2-1A0085EDDFB6-026AAA0A-5BFD-4651-A85D-4DC58A16F0A2/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
