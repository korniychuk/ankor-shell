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
  local fileFullPath
  local commandFullPath
  for fileFullPath in $(find "${AK_CUSTOM_SCRIPTS_PATH}" -name "*.sh" -type f ); do
    local fileName=$(basename "${fileFullPath%.sh}")
    local commandName="aks.${fileName}"
    local commandFullPath="${binsPath}/${commandName}"
    commandsList=("${commandsList[@]}" "${commandName}")

    if [[ ! -f "${commandFullPath}" ]]; then
      echo "#!/usr/bin/env bash" > "${commandFullPath}"
      echo "" >> "${commandFullPath}"
      echo "source \"${AK_SCRIPT_PATH}/index.sh\"" >> "${commandFullPath}"
      echo "source \"${fileFullPath}\" \"\${@}\"" >> "${commandFullPath}"

      chmod +x "${commandFullPath}"
    fi
  done

  for commandFullPath in $(find "${binsPath}" -name "aks.*" -type f ); do
      if ! ak.array.inArray "$(basename "${commandFullPath}")" "${commandsList[@]}"; then
          rm -f "${commandFullPath}"
      fi
  done

}

__ak.cs.init
