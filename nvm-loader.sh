#!/usr/bin/env bash

# works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


export _isNvmLoaded=0
function _ak.loadNvm() {
  local style_Off='\033[0m'              # Text Reset
  local style_Bold='\033[1m'
  local style_BoldRed='\033[1;31m'
  local style_BoldGreen='\033[1;32m'
  local cursorToPreviousLine='\e[1A'
  local nvmMsgPrefix='NVM Loader:'

  if [[ "$_isNvmLoaded" == "0" ]]; then
    export _isNvmLoaded=1

    local command="$1"; shift
    unset -f nvm node npm npx ng

    if [[ "${command}" == "automatically" ]]; then
      echo "${nvmMsgPrefix} .nvmrc found --> Loading NVM ..."
    else
      echo "${nvmMsgPrefix} Loading ..."
    fi

    # This dir will contains node.js installations
    export NVM_DIR="$HOME/.nvm"
    if [[ ! -d "${NVM_DIR}" ]]; then
      mkdir "$NVM_DIR"
    fi

    local nvmShDir="$(realpath -e $(brew --prefix nvm))"
    local nvmShLoader="${nvmShDir}/nvm.sh"
    local nvmShCompletion="${nvmShDir}/etc/bash_completion.d/nvm"
    [[ -s "$nvmShLoader" ]]     && source "$nvmShLoader"
    [[ -s "$nvmShCompletion" ]] && source "$nvmShCompletion"

    # load .nvmrc from the current working directory in case it exists
    local nvmRcInfo='Default'
    if [[ -f "$PWD/.nvmrc" ]]; then
      nvm use > /dev/null
      nvmRcInfo='From .nvmrc'
    fi

    if [[ ! -f "$(which node)" ]]; then
      echo -e "${nvmMsgPrefix} ${style_BoldRed}Can not load NodeJS${style_Off}" >&2
      return 1
    fi

    echo -e "\r${cursorToPreviousLine}${nvmMsgPrefix} ${style_BoldGreen}Loaded${style_Off} --> " \
      "node: ${style_Bold}$(node --version)${style_Off} (${nvmRcInfo})   " \
      "npm: ${style_Bold}$(npm --version)${style_Off}   " \
      "nvm: ${style_Bold}$(nvm --version)${style_Off}"
#      "\n"

    # execute only in case at least one argument passed
    if [[ "${1}" != "" ]]; then
      "${command}" "$@"
    fi
  fi
}

function nvm()  { _ak.loadNvm nvm  "$@" }
function node() { _ak.loadNvm node "$@" }
function npm()  { _ak.loadNvm npm  "$@" }
function npx()  { _ak.loadNvm npx  "$@" }
function ng()   { _ak.loadNvm ng   "$@" }
function yarn() { _ak.loadNvm yarn "$@" }

# automatically loading nvm on SHELL open in case .nvmrc found
if [[ -f "$PWD/.nvmrc" ]]; then
  _ak.loadNvm 'automatically'
fi
