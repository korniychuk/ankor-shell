#!/usr/bin/env bash

# TODO: checking minimum bash version
# TODO: versions
# TODO: bundling via Travis CI

declare -r SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

source "${SCRIPT_PATH}/array.sh"
source "${SCRIPT_PATH}/bash.sh"
source "${SCRIPT_PATH}/git.sh"
