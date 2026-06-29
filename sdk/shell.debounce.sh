#!/usr/bin/env bash

declare -r DATA_FILE="${TMPDIR}ak.sh.debounce_data.txt"
declare -r SNAP_FILE="${TMPDIR}ak.sh.debounce_SNAP.txt"
# declare -r LOCK_FILE="${TMPDIR}ak.sh.debounce_reader.lock"

declare COMMAND
declare INTERVAL_SEC

declare reader_loop_pid=''

function reader() {
  # [[ -e "$LOCK_FILE" ]] && return
  # touch "$LOCK_FILE"

  if [[ -f "$DATA_FILE" ]]; then
    mv "$DATA_FILE" "$SNAP_FILE"
    $COMMAND < "$SNAP_FILE" 
    rm -f "$SNAP_FILE"
  fi

  # rm -f "$LOCK_FILE"
}

function reader_async() {
  reader &
}

function reader_loop() {
  # for ((i = 0; i < 10; i++)); do
  while true; do
    reader_async
    sleep "$INTERVAL_SEC"
  done
}

function writter() {
  while IFS= read -r line; do
    echo "$line" >> "$DATA_FILE"
  done
}

function execute_debouncer() {
  reader_loop &
  reader_loop_pid=${!}

  writter <&0

  if [[ -n "$reader_loop_pid" ]] && ps -p "$reader_loop_pid" > /dev/null; then
    kill "$reader_loop_pid" 
    reader_loop_pid=''
    reader_async
  fi
}

function print_help() {
    cat <<'END'
Debounces & groups input from stdin during specified time interval.
Then, transforms the grouped input, executes a command from `-c` argument and passes the grouped input to the command.

Usage: command | ak.sh.debounce [-t time_interval_sec] [-c command] [-h]

  -t time_interval_sec : time interval in seconds to debounce and group input from stdin. Default is 0.5
  -c command           : command to execute with the grouped input. Default is 'cat -'
  -h                   : display help message

Example: command | ak.sh.debounce
Example: command | ak.sh.debounce -t 2 -c 'sort -u -r -'
END
}

function main() {
  local _time_interval_sec=0.5
  local _command='cat -'

  while getopts ":t:c:h" _opt; do
    case $_opt in
      t) _time_interval_sec="$OPTARG"
      ;;
      c) _command="$OPTARG"
      ;;
      h) print_help; exit 0
      ;;
      \?) echo "Invalid option -$OPTARG" >&2
          _print_help
          exit 1
      ;;
    esac
  done

  COMMAND="$_command"
  INTERVAL_SEC="$_time_interval_sec"

  execute_debouncer
}

main "$@" <&0

