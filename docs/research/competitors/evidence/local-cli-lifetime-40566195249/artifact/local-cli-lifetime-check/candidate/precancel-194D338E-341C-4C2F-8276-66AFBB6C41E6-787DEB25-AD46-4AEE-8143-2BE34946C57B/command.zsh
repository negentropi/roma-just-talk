#!/bin/zsh
[[ "$1" == 'ED91B07E-DF12-4716-87A4-265BD76B5E37' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/candidate/precancel-194D338E-341C-4C2F-8276-66AFBB6C41E6-787DEB25-AD46-4AEE-8143-2BE34946C57B/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- "$input" > "${0:h}/stdin.txt"
print -rn -- 'PRE'
