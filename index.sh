#!/usr/bin/env bash

# TODO: checking minimum bash version
# TODO: versions
# TODO: bundling via Travis CI
# TODO: implement functions to throw exceptions and check arguments
# TODO: implement function to read help from the function comment and print it by -h or --help
# TODO: ak.style function to work with text color, background, bold, italic, underline, and other styles.
#       https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
# TODO: use bash framework https://github.com/niieani/bash-oo-framework

# TODO: implement `const` keyword as alias for "declare -r". It defines local variables and global
# TODO: Implement ZSH/BASH detection
# TODO: Implement shopt for ZSH https://stackoverflow.com/questions/26616003/shopt-command-not-found-in-bashrc-after-shell-updation
# TODO: Check SH and exit

# Notes:
#  - $BASH_SOURCE[0] used for BASH
#  - $0 used for ZSH
declare -r AK_SCRIPT_PATH=$( cd $(
  [[ "${BASH_SOURCE[0]}" != "" ]] && dirname "$BASH_SOURCE[0]" || dirname "$0"
) ; pwd -P )

source "${AK_SCRIPT_PATH}/config.sh"
source "${AK_SCRIPT_PATH}/lib/str.sh"
source "${AK_SCRIPT_PATH}/lib/doc.sh"
source "${AK_SCRIPT_PATH}/lib/os.sh"
source "${AK_SCRIPT_PATH}/lib/array.sh"
source "${AK_SCRIPT_PATH}/lib/bash.sh"
source "${AK_SCRIPT_PATH}/lib/git.sh"
source "${AK_SCRIPT_PATH}/lib/inet.sh"
source "${AK_SCRIPT_PATH}/lib/updater.sh"
source "${AK_SCRIPT_PATH}/lib/docker.sh"

# TODO: Implement os detection, and don't import this script on non-macos systems
# https://stackoverflow.com/questions/394230/how-to-detect-the-os-from-a-bash-script
source "${AK_SCRIPT_PATH}/lib/macos.sh"
