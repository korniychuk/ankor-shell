#!/usr/bin/env bash

#
# 1. std out
# 2. std err
# 3. std in
#

#
# Output
#

#echo "I'm Coder"
#echo "I'm Coder $(date '+%s')" > 01-test.txt
#echo "I'm Coder $(date '+%s')" >> 01-test.txt

#mkdir "/test"
#mkdir "/test" 2> 01-test.txt
#mkdir "/test" > 01-test.txt 2>&1
#mkdir "/test" &> 01-test.txt
#mkdir "/test" 2> /dev/null

#mkdir "/test" &>> 01-test.txt
#mkdir "/test" >> 01-test.txt 2>&1


#
# Input
#

#sort ./01-data.txt
#sort # Ctrl+D - Stop

#cat ./01-data.txt | sort
#sort < ./01-data.txt

#tr ' ' '.' <<< '
#1 apple
#2 pear
#3 banana
#'

#
# Heredoc
#

#sort <<AOEUAE
#1 apple
#2 pear
#3 banana
#AOEUAE

#sort <<'END'
#1 apple
#2 pear
#3 banana
#$USER
#END

#sort <<"END"
#1 apple
#2 pear
#3 banana
#$USER
#END

#
# Piping stdout to stdin
#
#   command1 | command2 paramater1 | command3 parameter1 ‑ parameter2 | command4
#

#cat ./01-data.txt | sort
#ls y x z u q  2>&1 | sort

#bunzip2 -c somefile.tar.bz2 | tar -xvf -

#
# Read and write
#
#sort < ./01-data.txt > 01-test.txt
#cat ./01-data.txt | sort > 01-test.txt
