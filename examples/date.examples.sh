#!/usr/bin/env bash

function ak::date:currentDate() {
    local -r format=${1:-UA}
    echo $(date +'%Y-%m-%d')
}

declare -r currentTime=$(date +'%H-%M-%S')
