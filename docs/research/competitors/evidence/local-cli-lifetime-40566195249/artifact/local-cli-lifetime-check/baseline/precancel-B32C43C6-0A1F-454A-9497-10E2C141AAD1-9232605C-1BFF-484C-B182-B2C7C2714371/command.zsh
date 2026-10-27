#!/bin/zsh
[[ "$1" == '5A51FB20-627A-4D92-B783-10B207AF423E' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/precancel-B32C43C6-0A1F-454A-9497-10E2C141AAD1-9232605C-1BFF-484C-B182-B2C7C2714371/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'PRE'
