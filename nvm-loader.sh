#!/usr/bin/env bash
# shellcheck disable=2155

##
# Works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
##

export __ak_nvm_isLoaded=0
export __ak_nvm_msgPrefix='NVM Loader:'
function __ak.nvm.load() {
  # 0. fuse - first fn execution
  [[ "$__ak_nvm_isLoaded" != "0" ]] && return 0
  export __ak_nvm_isLoaded=1

  # 1. parse first arg
  local command="$1"; shift
  unset -f nvm node npm npx ng nest yarn nx # DELETE temporary loader function

  if [[ "${command}" == "automatically" ]]; then
    echo "${__ak_nvm_msgPrefix} .nvmrc found --> Loading NVM ..."
  else
    echo "${__ak_nvm_msgPrefix} Loading ..."
  fi

  # 2. This dir will contains node.js installations
  if [[ -z "${NVM_DIR+x}" ]]; then
    export NVM_DIR="$HOME/.nvm"
  fi
  if [[ ! -d "${NVM_DIR}" ]]; then
    mkdir "$NVM_DIR"
  fi

  # 3. The NVM Loading
  local nvmShDir="$(realpath "$(brew --prefix nvm)")"
  local nvmShLoader="${nvmShDir}/nvm.sh"
  local nvmShCompletion="${nvmShDir}/etc/bash_completion.d/nvm"
  [[ -s "$nvmShLoader" ]]     && source "$nvmShLoader"
  [[ -s "$nvmShCompletion" ]] && source "$nvmShCompletion"

  # 3. load .nvmrc from the current working directory in case it exists
  if [[ -f "$PWD/.nvmrc" ]]; then
    local tmpfile=$(mktemp)
    nvm use &>"$tmpfile"; local -i __ret=$?
    local __out=$(<"$tmpfile")
    rm "$tmpfile"

    if ((__ret == 0)); then
      ak.nvm.version 1
    elif ((__ret == 3)); then # 3 - Requested NodeJS version isn't installed
      local __msg=$(echo -n "$__out" | grep -F 'Found ');
      local __err=$(echo -n "$__out" | grep -F 'N/A');
      [[ -n "$__msg" ]] && echo "$__msg"
      # shellcheck disable=2154
      [[ -n "$__err" ]] && echo -e "${AK_COLOR_BRed}${__err}${AK_COLOR_NC}" >&2
      echo

      if [[ "$command" == 'automatically' ]]; then
        ak.sh.warn "Install it manually using command 'nvm install $(cat "$PWD/.nvmrc")'"
        return 2
      else
      # shellcheck disable=2154
        echo -e "${AK_COLOR_Yellow}Installing ...${AK_COLOR_NC}"
        nvm install
      fi

      ak.nvm.version 1
    else # Unsupported error
      ak.sh.err "$__out"
      return 3
    fi

  else
    ak.nvm.version 0
  fi

  # 4. Check 'node' command exists
  if ! ak.sh.commandExists node; then
    ak.sh.err "Loader is finished its work, but the 'node' CLI command is still absent"
    return 1
  fi

  # 5. Execute the command
  [[ "$command" == 'automatically' ]] && return 0
  if ak.sh.commandExists "$command"; then
    echo
    "${command}" "$@"
  else
    ak.sh.err "Can't find command '$command'"
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

  local nvmRcInfo=''
  if [[ "${isNvmRcUsed}" == "1" ]]; then
    nvmRcInfo=' (From .nvmrc)'
  elif [[ "${isNvmRcUsed}" == "0" ]]; then
    nvmRcInfo=' (Default)'
  fi

  if ak.sh.commandExists node; then
    # shellcheck disable=2154
    echo -en "\r${AK_SHELL_CURSOR_UP}${__ak_nvm_msgPrefix} ${AK_COLOR_BGreen}OK${AK_COLOR_NC} → "
    # shellcheck disable=2154
    echo -en "node: ${AK_COLOR_BBlue}$(node --version)${AK_COLOR_Gray}${nvmRcInfo}${AK_COLOR_NC}"
    echo -en "   npm: ${AK_COLOR_BBlue}$(npm --version)${AK_COLOR_NC}"
    echo -en "   nvm: ${AK_COLOR_BBlue}$(nvm --version)${AK_COLOR_NC}"
    if ak.sh.commandExists yarn; then
      echo -en "   yarn: ${AK_COLOR_BBlue}$(yarn --version)${AK_COLOR_NC}"
    else
      echo -en "   yarn: ${AK_COLOR_BRed}NO${AK_COLOR_NC}"
    fi
    echo
  else
    echo -e "${AK_SHELL_CURSOR_UP}${__ak_nvm_msgPrefix} ${AK_COLOR_BRed}Can not load NodeJS${AK_COLOR_NC}" >&2
  fi
}

function nvm()  { __ak.nvm.load nvm  "$@"; }
function node() { __ak.nvm.load node "$@"; }
function npm()  { __ak.nvm.load npm  "$@"; }
function npx()  { __ak.nvm.load npx  "$@"; }
function ng()   { __ak.nvm.load ng   "$@"; }
function nest() { __ak.nvm.load nest "$@"; }
function yarn() { __ak.nvm.load yarn "$@"; }
function nx()   { __ak.nvm.load nx   "$@"; }

__ak.nvm.autoloadNvmRc

