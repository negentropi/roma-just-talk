#!/bin/zsh
trap '' TERM
[[ "$1" == 'A7BB92E4-21C7-4F7E-8592-CCF3A7DC9343' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/timeout-D68D89DC-EC72-4F51-A358-A1EFD3FD426C-2755F1EF-3284-4416-B42A-6767B04B4200/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'TIMEOUT_RELEASED'
