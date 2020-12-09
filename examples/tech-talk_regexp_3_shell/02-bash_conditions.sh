#!/usr/bin/env bash

#if [[ 'aaa' == 'aaa' ]]; then
#  echo "'aaa' is equal 'aaa'"
#fi

#declare -r var='test'
#if [[ "$var" == 'test' ]]; then
#  echo "\$var is equal 'test'"
#fi

#
# Checking return code
#
#mkdir "/test"
#echo "Return code (first access): $?"
#echo "Return code (second access): $?"

#if [[ $? -eq 0 ]]; then
#  echo "Directory created"
#else
#  echo "Can't create dir"
#fi

#if test "$?" '-eq' '0'; then
#  echo "Directory created"
#else
#  echo "Can't create dir"
#fi

#if mkdir '/test'; then
#  echo "Directory created"
#else
#  echo "Can't create dir"
#fi

#if mkdir '/test' 2> /dev/null; then
#  echo "Directory created"
#else
#  echo "Can't create dir"
#fi

#
# Logical AND, OR
#

#mkdir '/test'  2> /dev/null && echo "SUCCESS: Dir created" || echo "ERROR: Can't create dir" >&2
#mkdir './test' 2> /dev/null && echo "SUCCESS: Dir created" || echo "ERROR: Can't create dir" >&2

#declare -r var='test'
#[[ "$var" == 'test' ]] && echo "\$var is equal 'test'"
#test "$var" '==' 'test' && echo "\$var is equal 'test'"
