#!/bin/zsh
[[ "$1" == '65F1C717-F95A-48E0-97D0-3C62A77D2F14' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/dual-pipe-F95DBA0A-E57D-40C7-B146-E8360C81FC76/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
block=X
for index in {1..17}; do block="$block$block"; done
print -rn -- "$block"
print -rn -- "$block" >&2
print -r -- ${#block} > "${0:h}/stderr-written.txt"

