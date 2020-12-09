#!/usr/bin/env bash

#
# Bash - Embedded RegExp
#

#declare -r digit='531531'
#if [[ $digit =~ [0-9] ]]; then
#    echo "$digit is a digit"
#else
#    echo "oops"
#fi

#
# Ask user
#

#echo -n "Your answer> "
#read -r REPLY
#if [[ "$REPLY" =~ ^[0-9]+$ ]]; then
#    echo Numeric
#else
#    echo Non-numeric
#fi

#
# One line error check
#

#echo -n "Your answer> "
#read -r REPLY
#[[ "$REPLY" =~ ^[0-9]+$ ]] || echo 'ERROR: Non-numeric'

#
# Simple email validation
#

# Notice: '-p' doesn't work in ZSH
#read -p "Enter email: " -r email
#if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]
#then
#    echo "This email address looks fine: $email"
#else
#    echo "This email address is flawed: $email"
#fi

#
# The problem is BRE. Base Regular Expressions.
#
#[[ 'ab' =~ ^[a-z]+$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'ab' =~ ^(a|b)+$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'ab ' =~ ^[a-z]+\ $ ]] && echo 'OK' || echo 'FAIL'

# Doesn't work:
#[[ 'ab' =~ ^[:alpha:]+$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'ab' =~ ^\w+$ ]] && echo 'OK' || echo 'FAIL'

#[[ 'aaaaa' =~ ^a+?$ ]] && echo 'OK' || echo 'FAIL' # Lazy

#[[ 'a1' =~ ^a(?=1)$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'a1' =~ ^a(?!1)$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'a1' =~ ^a(?:1)$ ]] && echo 'OK' || echo 'FAIL'

#[[ 'a5a' =~ ^([a-z])5\1$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'a5a' =~ ^([a-z])5\\1$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'a51' =~ ^([a-z])5\1$ ]] && echo 'OK' || echo 'FAIL'

#[[ 'ab
#' =~ ^[a-z]+\n$ ]] && echo 'OK' || echo 'FAIL'
#[[ 'ab ' =~ ^[a-z]+\s$ ]] && echo 'OK' || echo 'FAIL'

#
# $BASH_REMATCH[*] (bash only, not ZSH)
#

#declare envFileContent='    EMAIL:coder@mail.com   '
#if [[ "$envFileContent" =~ ^\ *([a-zA-Z0-9_-]+)[=:](.+)\ *$ ]]; then
#  echo "Matches number: ${#BASH_REMATCH[*]}"
#  echo "Full Match: ${BASH_REMATCH[0]}"
#  echo "Key: '${BASH_REMATCH[1]}'"
#  echo "Value: '${BASH_REMATCH[2]}'"
#fi

#
# Substring replacement
# It's not regex, it's just pattern matching similar to a file glob. extglob does affect the pattern matching behavior.
#

# ${string/#pattern/replacement} - replacement for substring if string begins with it
# ${string/%pattern/replacement} - replacement for substring if string ends with it
# ${string//pattern/replacement} - replace all occurrences of a substring

# ${string#pattern}  - removes the shortest match from the beginning
# ${string##pattern} - removes the longest match from the beginning
# ${string%pattern}  - removes the shortest match from the end
# ${string%%pattern} - removes the longest match from the end

#declare -r str="1. Hello, Tester! 22. I'm Coder.";
#echo "${str}"
#echo "${str/#[0-9]??[a-zA-Z]/~}"
#echo "${str/%2*r./~}"
#echo "${str//[0-9]/~}"

