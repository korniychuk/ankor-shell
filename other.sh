#!/usr/bin/env bash

#
### NVM BEGIN ###
#

# works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
#source /usr/local/opt/nvm/nvm.sh
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export _NVM_LOADED=0
function _nvm() {
    if [[ "$_NVM_LOADED" == "0" ]]; then
            export _NVM_LOADED=1

            local COMMAND="$1"; shift
            unset -f npm npx nvm node ng

            export NVM_DIR=~/.nvm
            #local NVM_SH_DIR="/usr/local/opt/nvm/nvm.sh"
            local NVM_SH_DIR="$(brew --prefix nvm)/nvm.sh"
            [ -s "$NVM_SH_DIR" ] && source "$NVM_SH_DIR"  # This loads nvm
            # [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

            "${COMMAND}" "$@"
    fi
}

function nvm()  { _nvm nvm "$@" }
function node() { _nvm node "$@" }
function npm()  { _nvm npm "$@" }
function npx()  { _nvm npm "$@" }
function ng()   { _nvm ng "$@" }
