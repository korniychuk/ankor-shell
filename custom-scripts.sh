#!/usr/bin/env bash

if [[ -z ${AK_CUSTOM_SCRIPTS_PATH+x} ]]; then
  declare -r AK_CUSTOM_SCRIPTS_PATH="${AK_SCRIPT_PATH}/custom-scripts"
fi

function __ak.cs.init() {

  local -r binsPath="${AK_SCRIPT_PATH}/.bin"

  if [[ ! -d "${AK_CUSTOM_SCRIPTS_PATH}" ]]; then
      mkdir -p "${AK_CUSTOM_SCRIPTS_PATH}"
  fi

  PATH="${PATH}:${binsPath}"

  local -a commandsList=()
  local commandFullPath
  local fileFullPath
  local folderFullPath

  # Linking single-file commands
  for fileFullPath in $(find "${AK_CUSTOM_SCRIPTS_PATH}" -name "*.sh" -type f -maxdepth 1 ); do
    local fileName=$(basename "${fileFullPath%.sh}")
    local commandName="aks.${fileName}"
    local commandFullPath="${binsPath}/${commandName}"
    commandsList=("${commandsList[@]}" "${commandName}")

    __ak.cs.checkCommandLink "${fileFullPath}" "${commandFullPath}"
  done

  # Linking folder commands
  for folderFullPath in $(find "${AK_CUSTOM_SCRIPTS_PATH}" -name "*" -type d -maxdepth 1 ); do
    local fileName=$(basename "${folderFullPath}")
    local commandName="aks.${fileName}"
    local commandFullPath="${binsPath}/${commandName}"

    fileFullPath="${folderFullPath}/index.sh"
    if [[ -f "${fileFullPath}" ]]; then
      commandsList=("${commandsList[@]}" "${commandName}")
      __ak.cs.checkCommandLink "${fileFullPath}" "${commandFullPath}"
    fi
  done

  # Clear old links
  for commandFullPath in $(find "${binsPath}" -name "aks.*" -type f ); do
      if ! ak.array.inArray "$(basename "${commandFullPath}")" "${commandsList[@]}"; then
          rm -f "${commandFullPath}"
      fi
  done
}

function __ak.cs.checkCommandLink() {
    local -r fileFullPath="${1}";
    local -r commandFullPath="${2}";
    local -r fileName=$(basename "${fileFullPath}")
    local -r command=$(basename "${commandFullPath}")

    if [[ ! -f "${commandFullPath}" ]]; then
      echo "#!/usr/bin/env bash" > "${commandFullPath}"
      echo "" >> "${commandFullPath}"
      echo "declare -r AK_CS_PATH=\"${fileFullPath}\"" >> "${commandFullPath}"
      echo 'declare -r AK_CS_DIR=$(dirname "${AK_CS_PATH}")' >> "${commandFullPath}"
      echo "declare -r AK_CS_COMMAND=\"${command}\"" >> "${commandFullPath}"
      echo "" >> "${commandFullPath}"
      echo "source \"${AK_SCRIPT_PATH}/index.sh\"" >> "${commandFullPath}"
      echo "source \"${fileFullPath}\" \"\${@}\"" >> "${commandFullPath}"


      chmod +x "${commandFullPath}"
    fi
}
__ak.cs.init

