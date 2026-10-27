#!/bin/zsh
trap '' TERM
[[ "$1" == '6617DF79-95EE-4809-B676-FB6E4099F8F8' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/cancel-EC8524B6-EDF0-4184-9DEA-2BD4874BC4FD-928F3172-8929-401A-9C1B-F87FC1B914C1/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'CANCEL_FINISHED'
