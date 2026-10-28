umask 077
/bin/cat > '/var/folders/n6/hn37q6pj7sj_9dmqqc2113800000gn/T/RJT-Polish-Native-68832AC6-65E4-41EC-89F5-8B621911BF89/clarity-fallback/stdin.txt'
printf '%s' "$VOICEINK_SYSTEM_PROMPT" > '/var/folders/n6/hn37q6pj7sj_9dmqqc2113800000gn/T/RJT-Polish-Native-68832AC6-65E4-41EC-89F5-8B621911BF89/clarity-fallback/system.txt'
printf '%s' "$VOICEINK_USER_PROMPT" > '/var/folders/n6/hn37q6pj7sj_9dmqqc2113800000gn/T/RJT-Polish-Native-68832AC6-65E4-41EC-89F5-8B621911BF89/clarity-fallback/user.txt'
printf '%s' "$$" > '/var/folders/n6/hn37q6pj7sj_9dmqqc2113800000gn/T/RJT-Polish-Native-68832AC6-65E4-41EC-89F5-8B621911BF89/clarity-fallback/pid.txt'
printf '%s\n' "$$" >> '/var/folders/n6/hn37q6pj7sj_9dmqqc2113800000gn/T/RJT-Polish-Native-68832AC6-65E4-41EC-89F5-8B621911BF89/clarity-fallback/calls.txt'
printf '%s' 'Synthetic Clarity failure 23' >&2; exit 23