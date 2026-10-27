#!/bin/zsh
[[ "$1" == '958A0212-E25E-4A44-A735-51119330A000' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/survivor-FB2D718F-3721-4AAB-B8F2-BBDD5760C54C-63F290E0-1635-47C9-BBDE-FDEAA7CCF8F0/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'SURVIVOR_EXACT'
