#!/usr/bin/env bash

# works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export _NVM_LOADED=0
function _nvm() {
  local Style_Off='\033[0m'              # Text Reset
  local Style_Bold='\033[1m'
  local Style_Bold_Red='\033[1;31m'
  local Style_Bold_Green='\033[1;32m'
  local Prev_Line='\e[1A'

  if [[ "$_NVM_LOADED" == "0" ]]; then
    export _NVM_LOADED=1

    local COMMAND="$1"; shift
    unset -f nvm node npm npx ng

    if [[ "${COMMAND}" == "automatically" ]]; then
      echo 'NVM Loader: .nvmrc found --> Loading NVM ...'
    else
      echo 'NVM Loader: Loading ...'
    fi

    # This dir will contains node.js installations
    export NVM_DIR="$HOME/.nvm"
    if [[ ! -d "${NVM_DIR}" ]]; then
      mkdir "$NVM_DIR"
    fi

    local NVM_SH_DIR="$(realpath -e $(brew --prefix nvm))"
    local NVM_SH_LOADER="${NVM_SH_DIR}/nvm.sh"
    local NVM_SH_COMPLETION="${NVM_SH_DIR}/etc/bash_completion.d/nvm"
    [[ -s "$NVM_SH_LOADER" ]]     && source "$NVM_SH_LOADER"
    [[ -s "$NVM_SH_COMPLETION" ]] && source "$NVM_SH_COMPLETION"

    # load .nvmrc from the current working directory in case it exists
    local NVMRC_INFO='Default'
    if [[ -f "$PWD/.nvmrc" ]]; then
      nvm use > /dev/null
      NVMRC_INFO='From .nvmrc'
    fi

    if [[ ! -f "$(which node)" ]]; then
      echo -e "NVM Loader: ${Style_Bold_Red}Can not load NodeJS${Style_Off}" >&2
      return 1
    fi

    echo -e "\r${Prev_Line}NVM Loader: ${Style_Bold_Green}Loaded${Style_Off} --> " \
      "node: ${Style_Bold}$(node --version)${Style_Off} (${NVMRC_INFO})   " \
      "npm: ${Style_Bold}$(npm --version)${Style_Off}   " \
      "nvm: ${Style_Bold}$(nvm --version)${Style_Off}"
#      "\n"

    # execute only in case at least one argument passed
    if [[ "${1}" != "" ]]; then
      "${COMMAND}" "$@"
    fi
  fi
}

function nvm()  { _nvm nvm  "$@" }
function node() { _nvm node "$@" }
function npm()  { _nvm npm  "$@" }
function npx()  { _nvm npm  "$@" }
function ng()   { _nvm ng   "$@" }
function yarn() { _nvm yarn "$@" }

# automatically loading nvm on SHELL open in case .nvmrc found
if [[ -f "$PWD/.nvmrc" ]]; then
  _nvm 'automatically'
fi
