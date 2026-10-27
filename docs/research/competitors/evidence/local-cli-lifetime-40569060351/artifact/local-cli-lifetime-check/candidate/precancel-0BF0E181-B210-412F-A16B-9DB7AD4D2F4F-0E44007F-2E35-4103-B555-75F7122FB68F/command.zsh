#!/bin/zsh
[[ "$1" == 'D9FF1D95-CE12-4530-A550-D6CF696A3B19' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/precancel-0BF0E181-B210-412F-A16B-9DB7AD4D2F4F-0E44007F-2E35-4103-B555-75F7122FB68F/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'PRE'
