#!/bin/bash
set -euo pipefail
case_id="${PWD##*/}"
[[ "$case_id" =~ ^C0[1-9]-(natural|casual|formal)$ ]]
launch=$(/usr/bin/mktemp -d '/tmp/rjt-clarity-semantic-execution-40582234931-9kd7p1ao/observations/attempts'/"$case_id"/launch.XXXXXX)
printf "%s\n" "$$" > "$launch/owned-exec-pid.txt"
exec '/opt/homebrew/Caskroom/claude-code@latest/2.1.310/claude' '--bare' '--no-session-persistence' '--tools' '' '--strict-mcp-config' '--mcp-config' '{"mcpServers":{}}' '--setting-sources' 'user' '--settings' '{"disableAllHooks":true}' '--print' '--output-format' 'text' '--max-budget-usd' '0.50' < <(/usr/bin/tee "$launch/stdin.bin"; : > "$launch/stdin.complete") > >(/usr/bin/tee "$launch/stdout.bin"; : > "$launch/stdout.complete") 2> >(/usr/bin/tee "$launch/stderr.bin" >&2; : > "$launch/stderr.complete")
