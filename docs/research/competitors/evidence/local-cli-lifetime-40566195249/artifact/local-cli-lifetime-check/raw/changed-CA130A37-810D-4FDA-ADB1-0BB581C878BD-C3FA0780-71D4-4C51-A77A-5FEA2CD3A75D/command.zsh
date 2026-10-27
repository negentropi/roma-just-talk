#!/bin/zsh
[[ "$1" == 'CC0A08DD-D378-4ED7-8547-B4EA174925AC' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/changed-CA130A37-810D-4FDA-ADB1-0BB581C878BD-C3FA0780-71D4-4C51-A77A-5FEA2CD3A75D/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'WRONG_COMMAND'
