#!/usr/bin/env bash


function inArray() {
    local needle="${1}"; shift
    local haystack="${@}"

    for haystack; do
        if [ "$haystack" == "$needle" ]; then
            return 0;
        fi
    done

    return 1;
}

declare -a testArr=('aaa', 'bbb', 'ccc')

if inArray 'bbb' "${testArr[@]}"; then
    echo 'Has "bbb"'
fi

if ! inArray 'ddd' "${testArr[@]}"; then
    echo 'Does not have "ddd"'
fi
