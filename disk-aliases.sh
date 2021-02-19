#!/usr/bin/env bash

# AK_DA <= AnKor DiskAliases
declare -r _AK_DA_ROOT_PREFIX="${1:-''}"

export -r AK_DA_CODE="${_AK_DA_ROOT_PREFIX}/code"
export -r AK_DA_PROJECTS="${_AK_DA_ROOT_PREFIX}/projects"
export -r AK_DA_STORAGE="${_AK_DA_ROOT_PREFIX}/storage"
export -r AK_DA_INFO="${_AK_DA_ROOT_PREFIX}/info"
export -r AK_DA_MEGA_CLOUD="${_AK_DA_ROOT_PREFIX}/mega-cloud"

#
# Custom Aliases
#
alias cdc='cd "${AK_DA_CODE}"'
alias cdp='cd "${AK_DA_PROJECTS}"'
alias cds='cd "${AK_DA_STORAGE}"'
alias cdi='cd "${AK_DA_INFO}"'
alias cdm='cd "${AK_DA_MEGA_CLOUD}"'
