#!/bin/zsh
[[ "$1" == '80E785BC-69B1-4846-B1BF-B54A77ABE39D' ]] || exit 97
print -r -- "$$ $PPID" > '/Users/runner/work/_temp/local-cli-lifetime-check/raw/raw-81D979E1-A74D-4A18-BF91-FFF38B4F551D/ready'
deadline=$((SECONDS + 20))
while [[ ! -e "${0:h}/release" && $SECONDS -lt $deadline ]]; do :; done
[[ -e "${0:h}/release" ]] || exit 98
IFS= read -r -d '' input || :
print -rn -- '  <think>literal é 日本語</think>
{"literal":true}
  '
