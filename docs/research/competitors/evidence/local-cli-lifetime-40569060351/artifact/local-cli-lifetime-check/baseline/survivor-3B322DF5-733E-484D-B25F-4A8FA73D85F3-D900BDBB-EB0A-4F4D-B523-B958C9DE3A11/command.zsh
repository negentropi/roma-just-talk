#!/bin/zsh
[[ "$1" == 'E542F8D3-7639-4F96-81DC-138F0323805E' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/baseline/survivor-3B322DF5-733E-484D-B25F-4A8FA73D85F3-D900BDBB-EB0A-4F4D-B523-B958C9DE3A11/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'SURVIVOR_EXACT'
