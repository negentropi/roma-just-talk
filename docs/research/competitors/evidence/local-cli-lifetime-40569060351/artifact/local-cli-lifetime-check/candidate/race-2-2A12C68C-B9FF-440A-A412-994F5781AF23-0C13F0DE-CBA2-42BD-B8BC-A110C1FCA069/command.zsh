#!/bin/zsh
[[ "$1" == '95F545B9-77B3-44EA-B6F1-C3739397AEFC' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/race-2-2A12C68C-B9FF-440A-A412-994F5781AF23-0C13F0DE-CBA2-42BD-B8BC-A110C1FCA069/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'RACE_EXACT'
