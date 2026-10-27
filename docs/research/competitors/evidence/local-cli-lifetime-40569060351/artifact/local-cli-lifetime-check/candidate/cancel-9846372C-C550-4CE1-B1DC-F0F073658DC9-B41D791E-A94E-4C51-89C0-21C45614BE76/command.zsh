#!/bin/zsh
trap '' TERM
[[ "$1" == '712EC418-28E0-4D5D-9D5B-F863A6995B7C' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/cancel-9846372C-C550-4CE1-B1DC-F0F073658DC9-B41D791E-A94E-4C51-89C0-21C45614BE76/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'CANCEL_FINISHED'
