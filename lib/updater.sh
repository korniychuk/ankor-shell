#!/usr/bin/env bash

function ak.updater.update() {
  local -r updateLogPath="${AK_SCRIPT_PATH}/.last-update.log"

  echo "$(date +'%Y-%m-%d %H:%M:%S')" > "${updateLogPath}"
  echo "${AK_SCRIPT_PATH}" >> "${updateLogPath}"
  echo -e "--------------------------------------------------------------------------------" >> "${updateLogPath}"
  __ak.updater.internal 2>&1 | tee -a "${updateLogPath}"
}

function __ak.updater.internal() {
  local currentDir="$(pwd)"
  cd "${AK_SCRIPT_PATH}"

  if ak.git.isClean; then
      echo -e '\nRepository is clean\n'
      git pull --no-edit origin master
  else
      echo -e '\nRepository is NOT clean\n'
      git stash && \
      git pull --no-edit origin master && \
      git stash pop
  fi

  cd "${currentDir}"

  echo -e "\nAnKor Shell updated."
}

function ak.updater.installCrontabJob() {
  local -r refreshPeriodHours="${1:-12}"
  if [[ "${refreshPeriodHours}" -lt 1 ]] || [[ "${refreshPeriodHours}" -gt 24 ]]; then
      echo "Error: \$refreshPeriodHours should in range [1, 24]. Job was not installed" >&2
      return 1
  fi

  local -r cronTmpFilePath="/tmp/__ak.updater.installCrontabJob.txt"
  local -r cronUpdaterPath="${AK_SCRIPT_PATH}/.crontab-updater.sh"
  local -r cronID="AnKor Shell :: Update"
  local -r cronSchedule="0 */${refreshPeriodHours} * * *"

  echo "#!/usr/bin/env bash" > "${cronUpdaterPath}"
  echo "" >> "${cronUpdaterPath}"
  echo "source \"${AK_SCRIPT_PATH}/index.sh\"" >> "${cronUpdaterPath}"
  echo "ak.updater.update" >> "${cronUpdaterPath}"
  chmod +x "${cronUpdaterPath}"
  echo "File '.crontab-updater.sh' refreshed."

  local -r installedCronJob="$(crontab -l | grep "${cronID}")"
  local -r correctCronJob="${cronSchedule} \"${cronUpdaterPath}\" # ${cronID}"

  if [[ -z "${installedCronJob}" ]]; then
    crontab -l > "${cronTmpFilePath}"
    echo "${correctCronJob}" >> "${cronTmpFilePath}"
    crontab "${cronTmpFilePath}"
    rm -f "${cronTmpFilePath}"

    echo 'The cron job installed.'
  elif [[ "${installedCronJob}" != "${correctCronJob}" ]]; then
    crontab -l | grep -v "${cronID}" > "${cronTmpFilePath}"
    echo "${correctCronJob}" >> "${cronTmpFilePath}"
    crontab "${cronTmpFilePath}"
    rm -f "${cronTmpFilePath}"

    echo 'The cron job re-installed because old job is outdated'
  else
    echo 'The cron job already installed. Do nothing.'
  fi
}
