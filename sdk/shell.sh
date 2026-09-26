#!/usr/bin/env bash

# TODO: rename to AK_CLR_*
declare -r AK_COLOR_Green=$'\e[0;32m'
declare -r AK_COLOR_BGreen=$'\e[1;32m'
declare -r AK_COLOR_Red=$'\e[0;31m'
declare -r AK_COLOR_BRed=$'\e[1;31m'
declare -r AK_COLOR_Yellow=$'\e[0;33m'
declare -r AK_COLOR_BYellow=$'\e[1;33m'

declare -r AK_COLOR_Blue=$'\e[0;34m'
declare -r AK_COLOR_BBlue=$'\e[1;34m'
declare -r AK_COLOR_Magenta=$'\e[0;35m'
declare -r AK_COLOR_BMagenta=$'\e[1;35m'
declare -r AK_COLOR_Cyan=$'\e[0;36m'
declare -r AK_COLOR_BCyan=$'\e[1;36m'
declare -r AK_COLOR_White=$'\e[0;37m'
declare -r AK_COLOR_BWhite=$'\e[1;37m'
declare -r AK_COLOR_Gray=$'\e[0;90m'
declare -r AK_COLOR_BGray=$'\e[1;90m'

declare -r AK_COLOR_NC=$'\e[0m' # No Color
declare -r AK_SHELL_CURSOR_UP=$'\e[1A' # Move cursor to the previous line

#
# TODO: Implement normalize boolean function '', 0, false, null
#   - https://unix.stackexchange.com/questions/185670/what-is-a-best-practice-to-represent-a-boolean-value-in-a-shell-script
#   - https://www.google.com/search?q=bash+falsy+values&oq=bash+falsy+values&aqs=chrome..69i57j0.4094j0j4&sourceid=chrome&ie=UTF-8
#

#
# Shell independent command.
# This commands should works in any shell.
#
# Notice: 'SH' the function names means a shortcut of 'Shell'. It doesn't mean this commands for legasy shell - 'SH'
#

#
# Returns currently opened SHELL type.
# Notice: This library works only with bash & zsh
#
# @example
#
#   if [[ "$(ak.sh.type)" == 'zsh' ]]; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.type() {
  local type
  type=$(ps -hp $$ | grep sh | sed -E 's/.*((z|ba|c|tc|k)sh)$/\1/g')

  case "$type" in
    zsh)    echo 'zsh'       ;;
    bash)   echo 'bash'      ;;
    *)      echo 'unknown'   ;;
  esac
}

#
# @example
#
#   if ak.sh.isZsh; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.isZsh() {
  test "$(ak.sh.type)" "==" "zsh"
  return $?
}

function ak.sh.isBash() {
  test "$(ak.sh.type)" "==" "bash"
  return $?
}

function ak.sh.isUnknown() {
  test "$(ak.sh.type)" "==" "unknown"
  return $?
}

#
# Ask confirmation from the user.
#
# @param {string} msg custom confirmation message (optional)
#                     default value is: 'Are you sure?'
#
# @example Default message
#
#   if ak.sh.confirm; then
#     echo 'The action confirmed!'
#   fi
#
# @example Custom message
#
#   if ak.sh.confirm 'Are you sure to delete .env file?'; then
#     rm -f .env
#   fi
#
# @example Without 'if' statement
#
#   ak.sh.confirm 'Are you sure to delete .env file?' && rm -f .env
#
function ak.sh.confirm() {
  local -r msg="${1:-Are you sure?} [y/N]: "
  local response

  # 'echo' used instead of '-p' flag for 'read' because of some shells doesn't support the '-p' flag
  # (in ZSH for example on Mac OS X systems)
  echo -n "${msg}"
  read -r response

  if [[ "${response}" =~ ^[yY][eE][sS]\|[yY]$ ]]; then
    true
  else
    false
  fi
}

declare -r __AK_SH_SECRET_RC_CANCEL=130     # Ctrl-C, same code as SIGINT
declare -r __AK_SH_SECRET_RC_SIGTERM=143
declare -r __AK_SH_CSI_FINAL_MIN=64         # '@' — an escape sequence's final byte is @..~
declare -r __AK_SH_CSI_FINAL_MAX=126        # '~'

# Read ONE character from <fd> into the caller's REPLY (dynamic scope — the
# caller declares `local REPLY=''`). A newline is returned as a character, not
# swallowed as a delimiter.
# @param $1 fd
function __ak.sh.readSecret.readChar() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    IFS= read -r -k1 -u "$1"
  else
    IFS= read -r -n1 -d '' -u "$1"
  fi
}

# Consume the rest of an escape sequence whose ESC was just read: CSI
# (`ESC [ … final`, incl. the bracketed-paste markers `ESC [200~` / `ESC [201~`),
# SS3 (`ESC O x`), or a two-byte `ESC x`. Everything is dropped — a secret
# never contains escape sequences, and arrows/F-keys must not end up in it.
# @param $1 fd
function __ak.sh.readSecret.skipEscape() {
  local -r fd="$1"
  local REPLY=''

  __ak.sh.readSecret.readChar "${fd}" || return 0
  if [[ "${REPLY}" == 'O' ]]; then
    __ak.sh.readSecret.readChar "${fd}"
    return 0
  fi
  [[ "${REPLY}" == '[' ]] || return 0

  # CSI: parameter/intermediate bytes, then ONE final byte in @..~
  local -i code=0
  while __ak.sh.readSecret.readChar "${fd}"; do
    printf -v code '%d' "'${REPLY}"
    (( code >= __AK_SH_CSI_FINAL_MIN && code <= __AK_SH_CSI_FINAL_MAX )) && return 0
  done
  return 0
}

# The input loop of ak.sh.readSecret: reads <fd> char by char, echoes `*` per
# char to <fd>, prints the collected secret to stdout at the end.
# Returns 0 (Enter / Ctrl-D) or __AK_SH_SECRET_RC_CANCEL (Ctrl-C as a byte).
# @param $1 fd  a read-write descriptor on /dev/tty, already in -echo -icanon
function __ak.sh.readSecret.loop() {
  local -r fd="$1"
  local REPLY=''
  local secret=''
  local -i i=0

  while __ak.sh.readSecret.readChar "${fd}"; do
    case "${REPLY}" in
      $'\n' | $'\r' | $'\x04') break ;;
      $'\x03') return "${__AK_SH_SECRET_RC_CANCEL}" ;;
      $'\x7f' | $'\b')
        [[ -z "${secret}" ]] && continue
        secret="${secret%?}"
        printf '\b \b' >&"${fd}"
        ;;
      $'\x15')
        for (( i = 0; i < ${#secret}; i++ )); do printf '\b \b' >&"${fd}"; done
        secret=''
        ;;
      $'\e') __ak.sh.readSecret.skipEscape "${fd}" ;;
      '' | [[:cntrl:]]) ;;
      *)
        secret+="${REPLY}"
        printf '*' >&"${fd}"
        ;;
    esac
  done

  printf '%s' "${secret}"
  unset secret
  return 0
}

##
# Read a secret (password) from the terminal with `*` feedback — one star per
# character — and print it to stdout. Made for command substitution (a fork and
# a pipe, never a file):
#
#   pw="$(ak.sh.readSecret 'sudo password: ')"
#
# - Reads /dev/tty and writes the prompt and stars to /dev/tty: stdout carries
#   the secret only, without a trailing newline.
# - The terminal goes to `-echo -icanon` ONCE for the whole read and is restored
#   from a `stty -g` snapshot on every exit path, signals included. NOT
#   `read -s` per character: it turns echo back on between calls, and a fast
#   paste landing in that gap would show in clear text.
# - Enter ends; Backspace deletes a char; Ctrl-U clears; Ctrl-C cancels (130).
#   Bracketed-paste markers are stripped, other escape sequences (arrows, F-keys)
#   are ignored. Pasting works.
# - No history: this is not zle/readline, nothing reaches HISTFILE.
# - xtrace is switched off inside, so a caller's `set -x` cannot print the secret.
# - Ctrl-C is a SIGINT to the whole foreground process group (ISIG stays on):
#   a caller that must survive it sets its own INT trap around the call.
#
# @param {string} prompt text shown before the input (default 'Password: ')
# @output the secret, without a trailing newline (empty when nothing was typed)
# @returns 0 read (possibly empty) · 1 no terminal · 130 cancelled (Ctrl-C)
#
# @example
#
#   local pw=''
#   pw="$(ak.sh.readSecret 'vault password: ')" || return
#   [[ -z "${pw}" ]] && { echo 'cancelled' >&2; return 1; }
#
##
function ak.sh.readSecret() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions noxtrace
  else
    local -
    set +x
  fi
  local -r promptText="${1:-Password: }"

  if ! { : < /dev/tty; } 2> /dev/null; then
    ak.sh.err "ak.sh.readSecret: no terminal (/dev/tty) to read a secret from."
    return 1
  fi

  # Subshell: its traps restore the terminal on EVERY exit path without
  # replacing the caller's own traps.
  (
    # fd 3 = /dev/tty for the whole read. A literal number on purpose: a
    # redirection cannot take it from a variable portably (bash and zsh).
    local saved=''
    local -i rc=0
    exec 3<> /dev/tty
    saved="$(stty -g <&3)" || exit 1
    trap 'stty "${saved}" <&3 2> /dev/null' EXIT
    trap 'stty "${saved}" <&3 2> /dev/null; printf "\n" >&3; exit ${__AK_SH_SECRET_RC_CANCEL}' INT
    trap 'stty "${saved}" <&3 2> /dev/null; printf "\n" >&3; exit ${__AK_SH_SECRET_RC_SIGTERM}' TERM HUP

    stty -echo -icanon min 1 time 0 <&3 || exit 1
    printf '%s' "${promptText}" >&3
    __ak.sh.readSecret.loop 3
    rc=$?
    stty "${saved}" <&3
    printf '\n' >&3
    exit "${rc}"
  )
}

#
# Search in the Shell history, highlighting matches, sorting results, limitate output
#
# @param {string}  *phrase          phrase to search
# @param {integer}  limit           number of results to show (default is 50)
#                                   (should be bigger 0)
# @param {boolean}  isCaseSensitive true/false or 0/1 (default is false)
#
# TODO: Use boolean convertion function for type casting
#
function ak.sh.history() {
  local -r phrase="${1}"
  local -r limit="${2:-50}"
  local -r isCaseSensitive=${3:-false}

  if [[ -z "${phrase}" ]]; then
      echo 'ArgError: No search phrase' >&2
      return 1
  fi

  if [[ "${limit}" -le 0 ]]; then
      echo 'ArgError: limit should greater then 0' >&2
      return 2
  fi

  local grepParams=()
  if [[ "${isCaseSensitive}" != "true" ]] && [[ "${isCaseSensitive}" != "1" ]]; then
      grepParams+='-i'
  fi

  # Notice: 'awk' used for trimming leading and trailing space.
  # See: https://unix.stackexchange.com/questions/102008/how-do-i-trim-leading-and-trailing-whitespace-from-each-line-of-some-output/205854
  history \
    | grep "${grepParams[@]}" "${phrase}" \
    | awk '{$1=$1};1' \
    | sort -r -k2 -u \
    | sort -k1 \
    | tail -n ${limit} \
    | grep "${grepParams[@]}" --color=auto "${phrase}"
}

#
# @example
#
#   if ! ak.sh.commandExists node; then
#     echo 'NodeJS should be installed' >&2
#     exit 1s
#   fi
#
function ak.sh.commandExists() {
  local -r __command="${1}";

  if ! command -v "$__command" > /dev/null; then
    false
  fi
}

function ak.sh.showConfig() {
  cat "${AK_SCRIPT_PATH}/config.sh" | tail -n +3
}

#
# Create a directory path and execute 'cd' to this path.
#
# @param {string} *dirPath relative or absolute path to the creatable directory
#
# @example
#
#   ak.sh.mkdirAndCd my/super/directory
#
function ak.sh.mkdirAndCd() {
  local -r _dirPath="$1"
  if [[ -f "$_dirPath" ]]; then
    echo "ERROR: Path '$_dirPath' already exists and it is not a directory! Do nothing." >&2
    return 1
  fi
  [[ ! -d "$_dirPath" ]] && mkdir -p "$_dirPath"
  cd "$_dirPath" || return 2
}

##
# Check the current user is root or not
#
# @example
#
#   ak.sh.isRoot && iptables -L # Notice: iptables is available only under the root
#   ak.sh.isRoot || exit 1
#   if ak.sh.isRoot; then ...; fi
#
##
function ak.sh.isRoot() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  return 1
}

function ak.sh.ok() {
  local -r msg="$1"
  # NB: do NOT name this 'status' — it is a read-only special var in zsh (alias of $?).
  local -r _status="${2:-OK}"
  echo -e "${AK_COLOR_BGreen}[$_status] ${AK_COLOR_Green}${msg}${AK_COLOR_NC}" >&2
}

function ak.sh.warn() {
  local -r msg="$1"
  echo -e "${AK_COLOR_BYellow}Warning! ${AK_COLOR_Yellow}${msg}${AK_COLOR_NC}" >&2
}

function ak.sh.err() {
  local -r msg="$1"
  echo -e "${AK_COLOR_BRed}ERROR: ${AK_COLOR_Red}${msg}${AK_COLOR_NC}" >&2
}

declare __AK_SHELL_DIE_DEFAULT_MSG="Something went wrong!"

##
# Print a red error with error code and exit script with the same error code
#
# @param {string} errorText
# @param {int} [errorCode=1]
#
# @example
#
#   ak.sh.die "My Error" 123
#
##
function ak.sh.die() {
  local -r errorText="${1:-$__AK_SHELL_DIE_DEFAULT_MSG}"
  local -r -i errorCode="${2:-1}"

  echo -e "${AK_COLOR_BRed}Die ($errorCode): ${AK_COLOR_Red}${errorText}${AK_COLOR_NC}" >&2
  exit $errorCode
}

declare __AK_SHELL_PARAM_REQUIRED_DEFAULT_MSG="shouldn't be empty!"

##
# Check if an arg of a param isn't empty value.
# If empty: print a red error with error code and exit script with the same error code
#
# @param {string} name         Variable name
# @param {string} [errorText]
# @param {int} [errorCode=1]
#
# @example
#
#   local myVar=$1
#   ak.sh.param.required 'myVar'
#
##
function ak.sh.param.required() {
  local -r paramName=$1
  local -r value=${!paramName}
  [[ -n "$value" ]] && return 0

  local -r errorText="${2:-$__AK_SHELL_PARAM_REQUIRED_DEFAULT_MSG}"
  local -r -i errorCode="${3:-1}"

  echo -e "${AK_COLOR_BRed}Param Error ($errorCode): ${AK_COLOR_Red}'$paramName' ${errorText}${AK_COLOR_NC}" >&2
  exit $errorCode
}

##
# Clear 1 or multiple lines
#
# @example
#
#   ak.sh.clear-line     # clears last line
#   ak.sh.clear-line 5   # clears last 5 lines
#
# @example
#
#   echo 'Extracting ...'
#   unzip -q ...
#   ak.sh.clear-line
#   echo 'Done!'
#
##
function ak.sh.clear-line() {
  local -i n=${1:-1}

  for _i in $(seq 1 $n); do
    tput cuu1 # move cursor up by one line
    tput el # clear the line
  done
}

##
# Re-Echo last line.
# 'echo' that clears previous line befor printing. All native 'echo' arguments and options are supported.
#
# @example
#
#   ak.sh.recho 'Hello'
#
##
function ak.sh.recho() {
  ak.sh.clear-line 1
  echo "$@"
}

##
# Checks if the current shell is interactive.
# Returns true when shell options include 'i' and $PS1 is not empty.
#
# @example
#
#   if ak.sh.isInteractive; then
#     echo "Interactive shell."
#   else
#     echo "Non-interactive shell."
#   fi
##
function ak.sh.isInteractive() {
  return [[ $- == *i* ]] && [ -n "$PS1" ]
}

##
# Debounces & groups input from stdin during specified time interval.
# Then, transforms the grouped input, executes a command from `-c` argument and passes the grouped input to the command.
#
# Usage: command | ak.sh.debounce [-t time_interval_sec] [-c command] [-h]
#
#   -t time_interval_sec : time interval in seconds to debounce and group input from stdin. Default is 0.5 sec
#   -c command           : command to execute with the grouped input. Default is 'cat -'
#   -h                   : display help message
#
# Example: command | ak.sh.debounce
# Example: command | ak.sh.debounce -t 2 -c 'sort -u -r -'
##
function ak.sh.debounce() {
  "$AK_SCRIPT_PATH/sdk/shell.debounce.sh" "$@" <&0
}

declare -r __AK_SH_TIMEOUT_KILL_AFTER_SEC=5   # ak.sh.timeout: TERM → KILL grace period

##
# Run a command with a time limit.
# Uses `timeout`/`gtimeout` when available; otherwise falls back to a
# background run + watchdog subshell (stock macOS ships no `timeout`).
#
# @param {integer} *seconds time limit in whole seconds
# @param {string}  *command command with its arguments
#
# @returns 124 when the limit fired (GNU timeout convention) — also when the
#          command ignored SIGTERM and had to be SIGKILLed after
#          __AK_SH_TIMEOUT_KILL_AFTER_SEC — otherwise the command's own exit code
#
# @example
#
#   ak.sh.timeout 15 ssh -T host uptime
#
##
function ak.sh.timeout() {
  local -r seconds="${1:-}"
  if [[ ! "${seconds}" =~ ^[0-9]+$ ]] || (( $# < 2 )); then
    ak.sh.err "Usage: ak.sh.timeout <seconds> <command> [args...]"
    return 1
  fi
  shift

  # SIGTERM first, SIGKILL after a grace period: a command that ignores TERM
  # (an interactive bash does) or sits stopped must never outlive its deadline
  # — a caller polling for completion would wait forever. GNU timeout reports
  # such a KILL as 137, not 124; normalise it, callers test for 124.
  local -r startedAt="$(date +%s)"
  local rc=0
  local timeoutBin=''
  ak.sh.commandExists gtimeout && timeoutBin='gtimeout'
  ak.sh.commandExists timeout && timeoutBin='timeout'
  if [[ -n "${timeoutBin}" ]]; then
    "${timeoutBin}" -k "${__AK_SH_TIMEOUT_KILL_AFTER_SEC}" "${seconds}" "$@"
    rc=$?
    (( rc == 128 + 9 )) && (( $(date +%s) - startedAt >= seconds )) && rc=124
    return ${rc}
  fi

  # Fallback: run in background, watchdog kills it at the deadline.
  "$@" &
  local -r cmdPid=$!
  (
    sleep "${seconds}"
    kill -TERM "${cmdPid}" 2> /dev/null || exit 0
    sleep "${__AK_SH_TIMEOUT_KILL_AFTER_SEC}"
    kill -KILL "${cmdPid}" 2> /dev/null
  ) &
  local -r watchdogPid=$!

  wait "${cmdPid}"
  rc=$?
  kill "${watchdogPid}" 2> /dev/null
  wait "${watchdogPid}" 2> /dev/null

  # Death by signal at/after the deadline is attributed to the watchdog. This
  # heuristic can mislabel a command that dies from its OWN signal after the
  # deadline — acceptable for a fallback path.
  if (( rc > 128 )) && (( $(date +%s) - startedAt >= seconds )); then
    rc=124
  fi
  return ${rc}
}

##
# Test all features that a terminal should support
# @See https://hellricer.github.io/2019/10/05/test-drive-your-terminal.html
##
function ak.sh.test-drive() {
  echo "# 24-bit (true-color)"
  # based on: https://gist.github.com/XVilka/8346728
  term_cols="$(tput cols || echo 80)"
  cols=$(echo "2^((l($term_cols)/l(2))-1)" | bc -l 2> /dev/null)
  # cols=$(echo "$term_cols * 0.8" | bc -l 2> /dev/null)
  rows=$(( cols / 2 ))
  echo $cols $rows
  awk -v cols="$cols" -v rows="$rows" 'BEGIN{
      s="  ";
      m=cols+rows;
      for (row = 0; row<rows; row++) {
        for (col = 0; col<cols; col++) {
            i = row+col;
            r = 255-(i*255/m);
            g = (i*510/m);
            b = (i*255/m);
            if (g>255) g = 510-g;
            printf "\033[48;2;%d;%d;%dm", r,g,b;
            printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b;
            printf "%s\033[0m", substr(s,(col+row)%2+1,1);
        }
        printf "\n";
      }
      printf "\n\n";
  }'

  echo "# text decorations"
  printf '\e[1mbold\e[22m\n'
  printf '\e[2mdim\e[22m\n'
  printf '\e[3mitalic\e[23m\n'
  printf '\e[4munderline\e[24m\n'
  printf '\e[4:1mthis is also underline\e[24m\n'
  printf '\e[21mdouble underline\e[24m\n'
  printf '\e[4:2mthis is also double underline\e[24m\n'
  printf '\e[4:3mcurly underline\e[24m\n'
  printf '\e[58;5;10;4mcolored underline\e[59;24m\n'
  printf '\e[5mblink\e[25m\n'
  printf '\e[7mreverse\e[27m\n'
  printf '\e[8minvisible\e[28m <- invisible (but copy-pasteable)\n'
  printf '\e[9mstrikethrough\e[29m\n'
  printf '\e[53moverline\e[55m\n'
  echo

  echo "# magic string (see https://en.wikipedia.org/wiki/Unicode#Web)"
  echo "é Δ Й ק م ๗ あ 叶 葉 말"
  echo

  echo "# emojis"
  echo "😃😱😵"
  echo

  echo "# right-to-left ('w' symbol should be at right side)"
  echo "שרה"
  echo

  echo "# sixel graphics"
  printf '\eP0;0;0q"1;1;64;64#0;2;0;0;0#1;2;100;100;100#1~{wo_!11?@FN^!34~^NB
  @?_ow{~$#0?BFN^!11~}wo_!34?_o{}~^NFB-#1!5~}{o_!12?BF^!25~^NB@??ow{!6~$#0!5?
  @BN^!12~{w_!25?_o{}~~NFB-#1!10~}w_!12?@BN^!15~^NFB@?_w{}!10~$#0!10?@F^!12~}
  {o_!15?_ow{}~^FB@-#1!14~}{o_!11?@BF^!7~^FB??_ow}!15~$#0!14?@BN^!11~}{w_!7?_
  w{~~^NF@-#1!18~}{wo!11?_r^FB@??ow}!20~$#0!18?@BFN!11~^K_w{}~~NF@-#1!23~M!4?
  _oWMF@!6?BN^!21~$#0!23?p!4~^Nfpw}!6~{o_-#1!18~^NB@?_ow{}~wo!12?@BFN!17~$#0!
  18?_o{}~^NFB@?FN!12~}{wo-#1!13~^NB@??_w{}!9~}{w_!12?BFN^!12~$#0!13?_o{}~~^F
  B@!9?@BF^!12~{wo_-#1!8~^NFB@?_w{}!19~{wo_!11?@BN^!8~$#0!8?_ow{}~^FB@!19?BFN
  ^!11~}{o_-#1!4~^NB@?_ow{!28~}{o_!12?BF^!4~$#0!4?_o{}~^NFB!28?@BN^!12~{w_-#1
  NB@???GM!38NMG!13?@BN$#0?KMNNNF@!38?@F!13NMK-\e\'
}

