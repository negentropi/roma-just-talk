#!/bin/zsh
[[ "$1" == 'E4BDCBD3-AAB8-4CF1-AF28-45D80CA32439' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/race-1-B61C926C-7B4E-4A80-82FF-C513E72682DE-10AD34F7-2B1E-421C-9FE7-B4AA61A6F867/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
