#!/usr/bin/env bash
# disk-aliases.sh: default code dir name and the optional 2nd argument (zsh only: the file uses `export -r`).
set -euo pipefail
script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/disk-aliases.sh
check() {
  local want=$1 got; shift
  # shellcheck disable=SC2016 # expanded by the child zsh
  got=$(env -u AK_DA_CODE zsh -c 'source "$1" "${@:2}"; printf %s "$AK_DA_CODE"' _ "$script" "$@")
  [[ "$got" == "$want" ]] || { printf 'FAIL %s: got %s, want %s\n' "$*" "$got" "$want" >&2; exit 1; }
}
check /Volumes/code /Volumes
check /home/deploy/Code /home/deploy Code
printf 'ok disk-aliases\n'
