#!/bin/zsh
[[ "$1" == 'AD29D420-4785-4322-B7AC-8F32A37D9B88' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/precancel-5D370365-C7B9-4C17-AAF5-96CE4EAF73FB-2D6915D9-FDD2-429B-BC1E-D4BB7EE4BBB3/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'PRE'
