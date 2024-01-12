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
  local -r status="${2:-OK}"
  echo -e "${AK_COLOR_BGreen}[$status] ${AK_COLOR_Green}${msg}${AK_COLOR_NC}" >&2
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
# If emptay: print a red error with error code and exit script with the same error code
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

  local -r errorText="${3:-$__AK_SHELL_PARAM_REQUIRED_DEFAULT_MSG}"
  local -r -i errorCode="${4:-1}"

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
  "$AK_SCRIPT_PATH/lib/shell.debounce.sh" "$@" <&0
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

