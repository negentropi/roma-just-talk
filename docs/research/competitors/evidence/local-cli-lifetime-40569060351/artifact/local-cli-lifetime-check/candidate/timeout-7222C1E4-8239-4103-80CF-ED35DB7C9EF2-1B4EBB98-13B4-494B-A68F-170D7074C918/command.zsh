#!/bin/zsh
trap '' TERM
[[ "$1" == '6C4A5E62-F5C7-45EC-85BF-36BA189A2A54' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/timeout-7222C1E4-8239-4103-80CF-ED35DB7C9EF2-1B4EBB98-13B4-494B-A68F-170D7074C918/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'TIMEOUT_RELEASED'
