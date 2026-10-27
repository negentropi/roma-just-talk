#!/bin/zsh
[[ "$1" == 'DE2E25A4-8987-4E15-8C9B-D9B760C7F7D9' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/dual-pipe-92B86747-2C30-47D9-AA7E-8D8A6383E97D/ready'
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

