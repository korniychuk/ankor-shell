#!/usr/bin/env bash
# shellcheck disable=2155

##
# Works faster then via brew
# http://broken-by.me/lazy-load-nvm/
# https://www.reddit.com/r/node/comments/4tg5jg/lazy_load_nvm_for_faster_shell_start/d5ib9fs/
##

export __ak_nl_isLoaded=0
export __ak_nl_msgPrefix='Node Loader:'
function __ak.node-loader.load() {
  # 0. fuse - first fn execution
  [[ "$__ak_nl_isLoaded" != "0" ]] && return 0
  export __ak_nl_isLoaded=1

  # 1. parse first arg
  local command="$1"; shift
  unset -f node npm npx ng nest yarn nx # DELETE temporary loader function

  if [[ "${command}" == "automatically" ]]; then
    echo "${__ak_nl_msgPrefix} local env found --> Loading Node Version ..."
  else
    echo "${__ak_nl_msgPrefix} Loading latest (offline) ..."
  fi

  # 2. This dir will contains node.js installations
  if [[ -z "${N_PREFIX+x}" ]]; then
    export N_PREFIX="$HOME/n"
  fi
  if [[ ! -d "${N_PREFIX}" ]]; then
    mkdir "$N_PREFIX"
  fi

  # 3. Check 'node' command exists
  if ! ak.sh.commandExists n; then
    ak.sh.err "The N (Node Version Manager) isn't installed"
    return 1
  fi

  # 4. Load Node
  if [[ "${command}" == "automatically" ]]; then
    n auto > /dev/null 2>&1
    ak.node-loader.version 1
  else
    n latest --offline > /dev/null 2>&1
    ak.node-loader.version 0
  fi

  # 5. Check 'node' command exists
  if ! ak.sh.commandExists node; then
    ak.sh.err "Loader is finished its work, but the 'node' CLI command is still absent"
    return 1
  fi

  # 6. Execute the command
  [[ "$command" == 'automatically' ]] && return 0
  if ak.sh.commandExists "$command"; then
    echo
    "${command}" "$@"
  else
    ak.sh.err "Can't find command '$command'"
  fi
}

##
 # Look for the next file exists in the current directory or any parent directory:
 # .n-node-version
 # .node-version
 # .nvmrc
 # package.json (with '"engines":' code fragment)
##
function __ak.node-loader.autoload() {
  local current_dir="$PWD"
  while [[ "$current_dir" != "/" ]]; do
    if [[ -f "$current_dir/.n-node-version" ]] || \
       [[ -f "$current_dir/.node-version" ]] || \
       [[ -f "$current_dir/.nvmrc" ]] || \
       ( [[ -f "$current_dir/package.json" ]] && grep -q '"engines":' "$current_dir/package.json" ); then
      __ak.node-loader.load 'automatically'
      return 0
    fi

    current_dir=$(dirname "$current_dir") # Move up to the parent directory
  done
}

function ak.node-loader.version() {
  local isLocal="${1:-unknown}"

  local info=''
  if [[ "${isLocal}" == "1" ]]; then
    info=' (from local)'
  elif [[ "${isLocal}" == "0" ]]; then
    info=' (default)'
  fi

  if ak.sh.commandExists node; then
    # shellcheck disable=2154
    echo -en "\r${AK_SHELL_CURSOR_UP}${__ak_nl_msgPrefix} ${AK_COLOR_BGreen}OK${AK_COLOR_NC} → "
    # shellcheck disable=2154
    echo -en "node: ${AK_COLOR_BBlue}$(node --version)${AK_COLOR_Gray}${info}${AK_COLOR_NC}"
    echo -en "   npm: ${AK_COLOR_BBlue}$(npm --version)${AK_COLOR_NC}"
    echo -en "   n: ${AK_COLOR_BBlue}$(n --version)${AK_COLOR_NC}"
    if ak.sh.commandExists yarn; then
      echo -en "   yarn: ${AK_COLOR_BBlue}$(yarn --version)${AK_COLOR_NC}"
    else
    # shellcheck disable=2154
      echo -en "   yarn: ${AK_COLOR_BRed}NO${AK_COLOR_NC}"
    fi
    echo
  else
    echo -e "${AK_SHELL_CURSOR_UP}${__ak_nl_msgPrefix} ${AK_COLOR_BRed}Can not load NodeJS${AK_COLOR_NC}" >&2
  fi
}

function node() { __ak.node-loader.load node "$@"; }
function npm()  { __ak.node-loader.load npm  "$@"; }
function npx()  { __ak.node-loader.load npx  "$@"; }
function ng()   { __ak.node-loader.load ng   "$@"; }
function nest() { __ak.node-loader.load nest "$@"; }
function yarn() { __ak.node-loader.load yarn "$@"; }
function nx()   { __ak.node-loader.load nx   "$@"; }

__ak.node-loader.autoload

