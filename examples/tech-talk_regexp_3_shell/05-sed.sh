#!/usr/bin/env bash

#
# Sed  is  a stream editor.
#

#
# How to execute command?
#

# Single command
#sed 's/apple/!!!/' ./01-data.txt

# Multiple commands
#sed 's/apple/one/; s/banana/two/' ./01-data.txt

# Multiple commands (multiline)
#sed '
#s/apple/one/
#s/banana/two/
#' ./01-data.txt

# Multiple commands (-e flags)
#sed -e 's/apple/one/' -e 's/banana/two/' ./01-data.txt

# Multiple commands (reading from file)
#sed -f ./05-commands-1.txt ./01-data.txt

#
# Flags
# * Number - When transmitting the number, the sequence number of the occurrence of the pattern in the string
#   is taken into account; this particular occurrence will be replaced.
# * The g flag indicates to process all occurrences of the pattern in the string.
# * The p flag indicates to print the contents of the original string.
# * A flag like w file tells the command to write the text processing results to a file.
#

#sed 's/[a-z]/!/'  ./01-data.txt # Default - One(first) replacement per line
#sed 's/[a-z]/!/2' ./01-data.txt # Match Number
#sed 's/e/!/p' ./01-data.txt #
#sed -n 's/e/!/p' ./01-data.txt #
#sed -n 's/e/!/w ./05-data-res.txt' ./01-data.txt

#
# Other
#

#echo 'sample' | sed -E 's|[a-e]+|_|g'
