#!/bin/zsh
[[ "$1" == 'E2D3A390-D356-4D63-BD76-121B521E7851' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/captured-BD14DB7B-88D3-435B-95FA-3309E6D46EF4-B34CC230-C2F1-42A3-B597-749BB4A213AD/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'CAPTURED_EXACT'
