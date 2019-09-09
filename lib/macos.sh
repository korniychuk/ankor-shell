#!/usr/bin/env bash

#
# Mac OS X specific scripts
#

#
# Create a separate Chrome launcher
#
# @param {string}  profileName         suffix of the new Chrome instance
# @param {integer} remoteDebuggingPort enable remote debugging on the port (optional)
# @returns {void}
#
# @example <caption>A new Chrome instance with name 'Google Chrome Research'</caption>
#   ak.macos.createChromeEnvironment Research
#
# @example <caption>A new Chrome instance with name 'Google Chrome Development' and debugging port 9222</caption>
#   ak.macos.createChromeEnvironment Development 9222
#
# Notice:
#   - Depends of perl
#
# Helpful links:
#   - https://apple.stackexchange.com/questions/66670/is-there-a-simple-way-to-have-separate-dock-icons-for-different-chrome-profiles
#
function ak.macos.createChromeEnvironment() {
  local -r profileName="${1}"
  local -r remoteDebuggingPort="${2}"

  if [[ -z "${profileName}" ]]; then
    echo "ERROR: Please provide the name for the new Chrome Instance" >&2
    return 1
  fi

  ak.doc.heading "Chrome Environment Generator"
  echo;

  echo "Name: 'Google Chrome ${profileName}'"
  echo -n "Remote Debugging Port: "
  if [[ ! -z "${remoteDebuggingPort}" ]]; then
     echo "${remoteDebuggingPort}"
  else
    echo "Disabled"
  fi
  echo;

  echo "1. Automation part:"

  #
  # 1. Preparing
  #
  echo "  * Preparing..."

  #
  # 1.1. Looking for the Google Chrome
  #
  local chromeAppDir=$(mdfind 'kMDItemCFBundleIdentifier == "com.google.Chrome"' | head -1)
  local -r chromeBin="$chromeAppDir/Contents/MacOS/Google Chrome"
  if [[ ! -e "${chromeBin}" ]]; then
    echo "ERROR: Can not find Google Chrome. Exiting." >&2
    return 1
  fi
  echo "    * Checking Google Chrome installed - OK"

  #
  # 1.2. Checking name uniqueness
  #
  local -r customAppDir="/Applications/Google Chrome ${profileName}.app"
  local -r profileDir="/Users/${USER}/Library/Application Support/Google/Chrome/${profileName}"
  if [[ -e "${customAppDir}" ]]; then
    echo "ERROR: Chrome instance with this name already exists. Exiting." >&2
    return 2
  fi
  echo "    * Checking name uniqueness - OK"

  #
  # 2. Creating a Chrome wrapper
  #
  echo "  * Creating a Chrome wrapper ..."


  #
  # 2.1. Directory creation
  #
  local -r wrapperDir="${customAppDir}/Contents/MacOS"
  mkdir -p "${wrapperDir}"
  echo "    * Directory created: ${wrapperDir}"

  #
  # 2.2. Wrapper generation
  #
  local -r wrapperFileName="wrapper.sh"
  local -r wrapperShFilePath="${wrapperDir}/${wrapperFileName}"

  cat > "$wrapperShFilePath" <<\EOF
#!/usr/bin/env bash

#
# Google Chrome for Mac with additional profile.
#

# Name your profile:
EOF

  echo "declare -r profileName='${profileName}'\n" >> "$wrapperShFilePath"

  cat >> "$wrapperShFilePath" <<\EOF

# Store the profile here:
declare -r profileDir="/Users/${USER}/Library/Application Support/Google/Chrome/${profileName}"

# Find the Google Chrome binary:
# todo: try declare -r
declare chromeApp=$(mdfind 'kMDItemCFBundleIdentifier == "com.google.Chrome"' | head -1)
declare -r chromeBin="$chromeApp/Contents/MacOS/Google Chrome"
if [[ ! -e "${chromeBin}" ]]; then
  echo "ERROR: Can not find Google Chrome. Exiting."
  exit -1
fi

# Start me up!
EOF

  local command='exec "$chromeBin" --enable-udd-profiles --user-data-dir="$profileDir"'
  if [[ ! -z "${remoteDebuggingPort}" ]]; then
    command="${command} --remote-debugging-port=${remoteDebuggingPort}"
  fi
  echo "${command}\n" >> "$wrapperShFilePath"

  echo "    * Wrapper generated: ${wrapperShFilePath}"

  #
  # 2.3. Make the wrapper executable
  #
  chmod +x "$wrapperShFilePath"
  echo "    * Add execution permission for the wrapper - OK"

  #
  # 3. Info.plist file
  #
  echo "  * Generating Info.plist file ..."

  #
  # 3.1. Copy Item.plist from the original Chrome
  #
  cp "${chromeAppDir}/Contents/Info.plist" "${customAppDir}/Contents/"
  echo "    * Info.plist copy-pasted from the original Google Chrome app"

  #
  # 3.2. Update Info.plist -> items
  #
  local -r targetItemPlistPath="${customAppDir}/Contents/Info.plist"

  _ak.macos.chromeInstanceAddSuffixPlistKey "${targetItemPlistPath}" "CFBundleDisplayName" " ${profileName}"
  echo "    * CFBundleDisplayName updated to 'Google Chrome ${profileName}'"

  _ak.macos.chromeInstanceAddSuffixPlistKey "${targetItemPlistPath}" "CFBundleName" " ${profileName}"
  echo "    * CFBundleName updated to 'Chrome ${profileName}'"

  _ak.macos.chromeInstanceAddSuffixPlistKey "${targetItemPlistPath}" "CFBundleIdentifier" ".${profileName}"
  echo "    * CFBundleIdentifier updated to 'com.google.Chrome.${profileName}'"

  _ak.macos.chromeInstanceReplacePlistKey "${targetItemPlistPath}" "CFBundleExecutable" "wrapper.sh"
  echo "    * CFBundleExecutable updated to 'wrapper.sh'"


  #
  # 4. Finish messages and Finder opening
  #

  ak.macos.openFinderAndSelectItem "${customAppDir}"

  echo;
  echo "  The new Chrome Instance is ready:"
  echo "    /Applications/Google Chrome ${profileName}.app"
  echo;

  echo "2. Manual part:"
  echo "  * You can change the app icon"
  echo;

  echo "3. To remove the a Chrome instance (application and profile) execute:"
  echo "   $> ak.macos.removeChromeInstance '${profileName}'"
  echo;
  echo "   or just chrome app (without profile):"
  echo "   $> ak.macos.removeChromeInstance '${profileName}' false"
  echo;

  ak.doc.headingLine "Done ;)"
}

#
# TODO: normalize falsy value
# Remove a separate Chrome launcher
#
# @param {string}  profileName   suffix of the new Chrome instance
# @param {boolean} removeProfile if 'false' profile will not be removed. Only app. Default: true
# @returns {void}
#
# @example <caption>A new Chrome instance with name 'Google Chrome Research'</caption>
#   ak.macos.removeChromeEnvironment Research
#
function ak.macos.removeChromeInstance() {
  local -r profileName="${1}"
  local -r removeProfile="${2:-true}"

  if [[ -z "${profileName}" ]]; then
    echo "ERROR: Please provide the name for the new Chrome Instance" >&2
    return 1
  fi

  ak.doc.heading "Chrome Environment Generator"
  echo;

  local -r customAppDir="/Applications/Google Chrome ${profileName}.app"
  local -r profileDir="/Users/${USER}/Library/Application Support/Google/Chrome/${profileName}"

  if [[ -e "${customAppDir}" ]]; then
    rm -rf "${customAppDir}"
    if [[ $? -eq 0 ]]; then
      echo " * Application deleted at: '${customAppDir}'"
    fi
  else
      echo " * Application not found at: '${customAppDir}'"
  fi

  if [[ "${removeProfile}" == "true" ]]; then
    if [[ -e "${profileDir}" ]]; then
      rm -rf "${profileDir}"
      if [[ $? -eq 0 ]]; then
        echo " * Profile deleted at: '${profileDir}'"
      fi
    else
        echo " * Profile not found at: '${profileDir}'"
    fi
  fi

  echo;
  ak.doc.headingLine "Done ;)"
}

function _ak.macos.chromeInstanceAddSuffixPlistKey() {
  local -r filePath="${1}"
  local -r key="${2}"
  local -r suffix="${3}"

  if [[ ! -f "${filePath}" ]]; then
    echo "ERROR: Info.plist file is not exists or is unwritable." >&2
    return 1
  fi

  perl -0777 -p -i -e "s/(<key>${key}<\/key>\n\s+<string>.+?)(<\/string>)/\$1${suffix}\$2/" -- "${filePath}"
  return $?
}

function _ak.macos.chromeInstanceReplacePlistKey() {
  local -r filePath="${1}"
  local -r key="${2}"
  local -r suffix="${3}"

  if [[ ! -f "${filePath}" ]]; then
    echo "ERROR: Info.plist file is not exists or is unwritable." >&2
    return 1
  fi

  perl -0777 -p -i -e "s/(<key>${key}<\/key>\n\s+<string>).+?(<\/string>)/\$1${suffix}\$2/" -- "${filePath}"
  return $?
}

#
# Helpful links:
#   - https://stackoverflow.com/questions/39214539/opening-finder-from-terminal-with-file-selected
#
function ak.macos.openFinderAndSelectItem() {
  local -r itemPath="${1}"

  if [[ -z "${itemPath}" ]]; then
      echo "ERROR: Please specify item path. Can not open Finder." >&2
      return 1
  fi
  if [[ ! -e "${itemPath}" ]]; then
      echo "ERROR: The item is not exists. Can not open Finder. (${itemPath})" >&2
  fi

  osascript -e "tell application \"Finder\"" -e activate -e "reveal POSIX file \"${itemPath}\"" -e end tell > /dev/null

  return 0
}