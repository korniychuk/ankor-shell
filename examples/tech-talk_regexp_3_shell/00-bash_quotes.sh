#!/usr/bin/env bash

#
# print something
#
#echo I am Coder $USER

#
# single quotes
#
#echo I'm Coder $USER
#echo I\'m Coder $USER

# Escaping - problem
#echo 'I'm Coder $USER'
#echo 'I\'m Coder $USER'
#echo 'I''m Coder $USER'
#echo 'I'   STR   'm Coder $USER'
#echo 'I'\''m Coder $USER'

#
# Double quotes
#
#echo "I'm Coder $USER"

#
# Back quotes
#
#echo An Item: `ls -l | tail -n 1` # legacy
#echo An Item: $(ls -l | tail -n 1)
#echo "An Item: `ls -l | tail -n 1`"

#echo "An Item: $(ls -l | tail -n 1)"
#eval "ls -l | tail -n 1"
