#!/usr/bin/env bash

# TODO: checking minimum bash version
# TODO: versions
# TODO: bundling via Travis CI
# TODO: implement functions to throw exceptions and check arguments
# TODO: implement function to read help from the function comment and print it by -h or --help
# TODO: ak.style function to work with text color, background, bold, italic, underline, and other styles.
#       https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux

declare -r AK_SCRIPT_PATH="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

source "${AK_SCRIPT_PATH}/config.sh"
source "${AK_SCRIPT_PATH}/lib/array.sh"
source "${AK_SCRIPT_PATH}/lib/bash.sh"
source "${AK_SCRIPT_PATH}/lib/git.sh"
