#!/bin/zsh
[[ "$1" == 'DB691582-2576-4F9E-9043-B51094A938B4' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/captured-3DB0814D-68CD-4FF3-A73B-D762DE273F64-F4C4ABB1-C032-4F90-99AA-849628C0E876/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'CAPTURED_EXACT'
