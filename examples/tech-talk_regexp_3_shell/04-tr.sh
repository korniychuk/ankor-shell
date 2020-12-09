#!/usr/bin/env bash

#
# Documentation: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/tr.html
# It should be noted that, despite similarities in appearance, the string operands used by tr are NOT regular expressions.
#

#tr '\n' ':' < ./01-data.txt
# Simple global replace of a char

#
# Range
#

#tr 'a-g' '!' < ./01-data.txt

#tr 'abcde' '54321' <<< 'a b c d e f g!'
#tr 'abcde' '5432'   <<< 'a b c d e f g!'
#tr 'abcde' '543'   <<< 'a b c d e f g!'


#
# Ranges | case transform
#

#tr '[:lower:]' '[:upper:]' < ./01-data.txt

#tr '[:lower:]' '[:upper:]' <<< 'Hello!'
#tr 'a-z' 'A-Z' <<< 'Hello!'

#tr '[:lower:]' '[:upper:]' <<< 'Привет!'
#tr 'а-я' 'А-Я' <<< 'Привет!'

#
# '-d' Delete chars
#

#tr -d '\n' < ./01-data.txt
#tr -d '[:alpha:]' < ./01-data.txt

#
# '-s' Squeeze (joining char duplicates)
#

#tr -s '.' <<< "Heeeelloo....!"
#tr -s '.e' <<< "Heeeelloo....!"
#tr -s ' ' ':' <<< "I'm   a      Coder"

#
# '-c' reverse sense
#

#echo "My UID is $UID"
#echo "My UID is $UID" | tr -cd "[:digit:]\n"
#echo "My UID is $UID" | tr -d "a-zA-Z "

#echo "My UID is $UID" | tr -cd "[:digit:]"
#echo "My UID is $UID" | tr -d "a-zA-Z"

# [:print:] - all printable characters, including space
#tr -cd '[:print:]' <<< "I   am	Coder
#!!!"

#
# Common mistakes
#

#tr '[abcde]' '[543]'   <<< 'a b c d e f g!'
#tr '[abcde]' '(543)'   <<< '[][][]a b c d e f g!'
