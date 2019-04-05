#!/usr/bin/env bash

declare -a testArr=('aaa', 'bbb', 'ccc')

if inArray 'bbb' "${testArr[@]}"; then
  echo 'Has "bbb"'
fi

if ! inArray 'ddd' "${testArr[@]}"; then
  echo 'Does not have "ddd"'
fi
