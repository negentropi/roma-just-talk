#!/bin/zsh
[[ "$1" == '7029CF51-0D62-4CE4-9184-4531A835EF27' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/legacy-88949FDA-9AB0-4643-A507-2B5AB3D57F7B/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- '  <think>literal é 日本語</think>
{"literal":true}
  '
