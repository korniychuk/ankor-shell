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
# TODO: Implement root user checking https://askubuntu.com/questions/15853/how-can-a-script-check-if-its-being-run-as-root
#
# TODO: Create autoremovable cron task. Something like:
#  ak.cron.once ./command.sh at 2019-08-22 22:00:00
#  ak.cron.once ./command.sh at 22:00:00
#  ak.cron.once ./command.sh at 2019-08-22
#  ak.cron.once ./command.sh in 2h
#  ak.cron.once ./command.sh in 2h 35m 35s
#  and also ak.cron.every with the same arguments
#
# TODO: Implement simple one-line installer
#   Example: curl --compressed -o- -L https://yarnpkg.com/install.sh | bash
#   May be helpful: https://github.com/gregbugaj/git-multi-repo-tooling/blob/master/Makefile
#
# TODO: ak.git.commit --ak-date="..." ...throw...all...git..params...to...git...
# TODO: ak.git.redate today|yesterday|tomorrow morning|work|evening
# TODO: add convenient user management
#
# TODO: Implement an autoruner for local-scripts/custom-scripts/scripts
#
# TODO: Implement ak.ssh.save, ak.ssh.connect, persistance file storage
#
# TODO: Implement pbcopy/pbpaste for linux
# - http://itisgood.ru/2018/07/31/kak-ispolzovat-komandy-pbcopy-i-pbpaste-v-linux/
# - https://unix.stackexchange.com/questions/566081/xsel-cant-open-display-null?answertab=active#tab-top
#
# TODO: Implement a script to clone npm package sources from git and install dependencies

# Notes:
#  - $BASH_SOURCE[0] used for BASH
#  - $0 used for ZSH
declare -r AK_SCRIPT_PATH=$( cd $(
  [[ "${BASH_SOURCE[0]}" != "" ]] && dirname "${BASH_SOURCE[0]}" || dirname "$0"
) ; pwd -P )

source "${AK_SCRIPT_PATH}/config.sh"
source "${AK_SCRIPT_PATH}/lib/str.sh"
source "${AK_SCRIPT_PATH}/lib/array.sh"

source "${AK_SCRIPT_PATH}/lib/bash.sh"
source "${AK_SCRIPT_PATH}/lib/shell.sh"
source "${AK_SCRIPT_PATH}/lib/rnd.sh"
source "${AK_SCRIPT_PATH}/lib/doc.sh"
source "${AK_SCRIPT_PATH}/lib/os.sh"

source "${AK_SCRIPT_PATH}/lib/dt.sh"
source "${AK_SCRIPT_PATH}/lib/git.sh"
source "${AK_SCRIPT_PATH}/lib/inet.sh"
source "${AK_SCRIPT_PATH}/lib/updater.sh"
source "${AK_SCRIPT_PATH}/lib/docker.sh"
source "${AK_SCRIPT_PATH}/lib/downloader.sh"

if ak.os.type.isMacOS; then
  source "${AK_SCRIPT_PATH}/lib/macos.sh"
fi
