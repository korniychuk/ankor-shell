#!/usr/bin/env bash

####################################################################################################
# CaLS = Custom and Local Scripts
# Powerful environment to write custom private scripts
#
# aks. means AnKor Custom Scripts
# akl. means AnKor Local Scripts
####################################################################################################

if [[ -z ${AK_CALS_CUSTOM_SCRIPTS_PATH+x} ]]; then
  declare -r AK_CALS_CUSTOM_SCRIPTS_PATH="${AK_SCRIPT_PATH}/custom-scripts"
  export AK_CALS_CUSTOM_SCRIPTS_PATH
fi

if [[ -z ${AK_CALS_LOCAL_SCRIPTS_PATH+x} ]]; then
  declare -r AK_CALS_LOCAL_SCRIPTS_PATH="${AK_SCRIPT_PATH}/local-scripts"
  export AK_CALS_LOCAL_SCRIPTS_PATH
fi

declare __AK_CALS_BINS_PATH="${AK_SCRIPT_PATH}/.bin"

function __ak.cals.loadScriptsDir() {
  local -r scriptsPath="${1}"
  local -r prefix="${2}"
  if [[ -z "${scriptsPath}" ]]; then
    echo "ERROR! argument 'scriptsPath' is srequired" >&2
    return 1
  fi
  if [[ -z "${prefix}" ]]; then
      echo "ERROR! argument 'prefix' is required" >&2
  fi

  if [[ ! -d "${scriptsPath}" ]]; then
    mkdir -p "${scriptsPath}"
  fi

  PATH="${PATH}:${__AK_CALS_BINS_PATH}"

  local -a commandList=()
  local commandFullPath
  local fileFullPath
  local folderFullPath

  # Linking single-file commands
  for fileFullPath in $(find "${scriptsPath}" -name "*.sh" -type f -maxdepth 1); do
    local fileName=$(basename "${fileFullPath%.sh}")
    local commandName="${prefix}${fileName}"
    local commandFullPath="${__AK_CALS_BINS_PATH}/${commandName}"

    commandList=("${commandList[@]}" "${commandName}")

    __ak.cals.checkCommandLink "${fileFullPath}" "${commandFullPath}"
  done

  # Linking folder commands
  for folderFullPath in $(find "${scriptsPath}" -name "*" -type d -maxdepth 1); do
    local fileName=$(basename "${folderFullPath}")
    local commandName="${prefix}${fileName}"
    local commandFullPath="${__AK_CALS_BINS_PATH}/${commandName}"

    fileFullPath="${folderFullPath}/index.sh"
    if [[ -f "${fileFullPath}" ]]; then
      commandList=("${commandList[@]}" "${commandName}")
      __ak.cals.checkCommandLink "${fileFullPath}" "${commandFullPath}"
    fi
  done

  # Clear old links
 for commandFullPath in $(find "${__AK_CALS_BINS_PATH}" -name "${prefix}*" -type f); do
    if ! ak.array.inArray "$(basename "${commandFullPath}")" "${commandList[@]}"; then
      rm -f "${commandFullPath}"
    fi
  done
}

function __ak.cals.checkCommandLink() {
  local -r fileFullPath="${1}"
  local -r commandFullPath="${2}"
  local -r fileName=$(basename "${fileFullPath}")
  local -r command=$(basename "${commandFullPath}")

  if   [[ ! -f "${commandFullPath}" ]]; then
    {
      echo "#!/usr/bin/env bash"
      echo
      echo "declare -r AK_CALS_PATH=\"${fileFullPath}\""
      # shellcheck disable=SC2016
      echo 'declare -r AK_CALS_DIR=$(dirname "${AK_CALS_PATH}")'
      echo "declare -r AK_CALS_COMMAND=\"${command}\""
      echo
      echo "source \"${AK_SCRIPT_PATH}/index.sh\""
      echo "source \"${fileFullPath}\" \"\${@}\""
    } > "${commandFullPath}"

    chmod +x "${commandFullPath}"
  fi
}

__ak.cals.loadScriptsDir "${AK_CALS_CUSTOM_SCRIPTS_PATH}" "aks."
__ak.cals.loadScriptsDir "${AK_CALS_LOCAL_SCRIPTS_PATH}" "akl."

unset __AK_CALS_BINS_PATH
