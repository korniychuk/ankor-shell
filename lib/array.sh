#!/usr/bin/env bash

function ak.array.inArray() {
    local needle="${1}"; shift
    local haystack="${@}"

    for haystack; do
        if [[ "$haystack" == "$needle" ]]; then
            return 0;
        fi
    done

    return 1;
}

# joinBy ,      a b c #a,b,c
# joinBy ' , '  a b c #a , b , c
# joinBy ')|('  a b c #a)|(b)|(c
# joinBy ' %s ' a b c #a %s b %s c
# joinBy $'\n'  a b c #a<newline>b<newline>c
# joinBy -      a b c #a-b-c
# joinBy '\'    a b c #a\b\c
function ak.array.joinBy {
    local d=$1;
    shift;

    echo -n "$1";
    shift;

    printf "%s" "${@/#/$d}";
}
