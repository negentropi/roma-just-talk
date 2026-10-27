#!/bin/zsh
[[ "$1" == '6BD37807-394C-42AA-A35F-2D7D3393ECB6' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/survivor-E409DC51-5499-45A3-98BC-65B850677E99-ECC4CFD8-068A-40C8-A2D4-5A5A96A858AB/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'SURVIVOR_EXACT'
