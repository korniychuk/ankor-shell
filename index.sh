#!/usr/bin/env bash

# TODO: checking minimum bash version
# TODO: versions
# TODO: bundling via Travis CI

declare -r AK_SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

source "${AK_SCRIPT_PATH}/config.sh"
source "${AK_SCRIPT_PATH}/lib/array.sh"
source "${AK_SCRIPT_PATH}/lib/bash.sh"
source "${AK_SCRIPT_PATH}/lib/git.sh"
