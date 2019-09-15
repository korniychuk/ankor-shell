#!/usr/bin/env bash

#
# The code is taken from this link:
# https://stackoverflow.com/questions/28320134/how-to-list-all-tags-for-a-docker-image-on-a-remote-registry
#
# Notes:
# - Doesn't depends of docker installed
#
function ak.docker.tags() {
  if [[ ${#} -lt 1 ]]; then
    cat << HELP

ak.docker.tags  --  list all tags for a Docker image on a remote registry.

EXAMPLE:
    - list all tags for ubuntu:
       ak.docker.tags ubuntu

    - list all php tags containing apache:
       ak.docker.tags php apache

HELP
  fi

  declare -r image="${1}"
  declare tags=$(wget -q https://registry.hub.docker.com/v1/repositories/${image}/tags -O -  | sed -e 's/[][]//g' -e 's/"//g' -e 's/ //g' | tr '}' '\n'  | awk -F: '{print $3}')

  if [[ -n "${2}" ]]; then
    tags=$(echo "${tags}" | grep "$2")
  fi

  echo "${tags}"
}

#
# Returns long network IDs.
# ID Example: bbffeacb7c532949cfa3a92ab0282627d1986a0b24275ec4d500d730f97fb969
#
# Notes:
#   - You can specify only a part of the name (may not from the beginning)
#   - If by the specified name part multiple networks found, you will get multiple IDs
#
# TODO: Check docker installed
#
function ak.docker.network.searchIDsByPartialName() {
  local -r name="${1}"
  if [[ -z "${name}" ]]; then
    echo   "ERROR! Argument 'name' is required" >&2
    return 1
  fi

  docker network ls --no-trunc --quiet --filter=name="${name}"
}
