#!/usr/bin/env bash

# TODO: Improve to install version automatically https://github.com/nvm-sh/nvm#zsh

# works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
#[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export __ak_nvm_isLoaded=0
export __ak_nvm_msgPrefix='NVM Loader:'
function __ak.nvm.load() {
  if [[ "$__ak_nvm_isLoaded" == "0" ]]; then
    export __ak_nvm_isLoaded=1

    local command="$1"; shift
    unset -f nvm node npm npx ng nest yarn

    if [[ "${command}" == "automatically" ]]; then
      echo "${__ak_nvm_msgPrefix} .nvmrc found --> Loading NVM ..."
    else
      echo "${__ak_nvm_msgPrefix} Loading ..."
    fi

    # This dir will contains node.js installations
    if [[ -z "${NVM_DIR+x}" ]]; then
      export NVM_DIR="$HOME/.nvm"
    fi
    if [[ ! -d "${NVM_DIR}" ]]; then
      mkdir "$NVM_DIR"
    fi

    local nvmShDir="$(realpath -e $(brew --prefix nvm))"
    local nvmShLoader="${nvmShDir}/nvm.sh"
    local nvmShCompletion="${nvmShDir}/etc/bash_completion.d/nvm"
    [[ -s "$nvmShLoader" ]]     && source "$nvmShLoader"
    [[ -s "$nvmShCompletion" ]] && source "$nvmShCompletion"

    # load .nvmrc from the current working directory in case it exists
    if [[ -f "$PWD/.nvmrc" ]]; then
      nvm use > /dev/null
      ak.nvm.version 1
    else
      ak.nvm.version 0
    fi

    if ! ak.sh.commandExists node; then
      return 1
    fi

    # execute only in case at least one argument passed
    if [[ "${1}" != "" ]]; then
      "${command}" "$@"
    fi
  fi
}

# automatically loading nvm on SHELL open in case .nvmrc found
function __ak.nvm.autoloadNvmRc() {
  if [[ -f "$PWD/.nvmrc" ]]; then
    __ak.nvm.load 'automatically'
  fi
}

function ak.nvm.version() {
  local isNvmRcUsed="${1:-unknown}"

  # TODO: Use global styles function after it will be implemented
  local style_Off='\033[0m' # Text Reset
  local style_Bold='\033[1m'
  local style_BoldRed='\033[1;31m'
  local style_BoldGreen='\033[1;32m'
  local cursorToPreviousLine='\e[1A'

  local nvmRcInfo=''
  if [[ "${isNvmRcUsed}" == "1" ]]; then
    nvmRcInfo=' (From .nvmrc)'
  elif [[ "${isNvmRcUsed}" == "0" ]]; then
    nvmRcInfo=' (Default)'
  fi

  if ak.sh.commandExists node; then
    echo -en "\r${cursorToPreviousLine}${__ak_nvm_msgPrefix} ${style_BoldGreen}Loaded${style_Off} --> "
    echo -en "node: ${style_Bold}$(node --version)${style_Off}${nvmRcInfo}"
    echo -en "   npm: ${style_Bold}$(npm --version)${style_Off}"
    echo -en "   nvm: ${style_Bold}$(nvm --version)${style_Off}"
    if ak.sh.commandExists yarn; then
      echo -en "   yarn: ${style_Bold}$(yarn --version)${style_Off}"
    else
      echo -en "   yarn: ${style_BoldRed}NO${style_Off}"
    fi
    echo
  else
    echo -e "${cursorToPreviousLine}${__ak_nvm_msgPrefix} ${style_BoldRed}Can not load NodeJS${style_Off}" >&2
  fi
}

function nvm()  { __ak.nvm.load nvm  "$@"; }
function node() { __ak.nvm.load node "$@"; }
function npm()  { __ak.nvm.load npm  "$@"; }
function npx()  { __ak.nvm.load npx  "$@"; }
function ng()   { __ak.nvm.load ng   "$@"; }
function nest() { __ak.nvm.load nest "$@"; }
function yarn() { __ak.nvm.load yarn "$@"; }

__ak.nvm.autoloadNvmRc
