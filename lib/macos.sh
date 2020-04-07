#!/usr/bin/env bash

# TODO: Implement Notifier
#       https://github.com/ohoachuck/notify/blob/master/notify
#       https://stackoverflow.com/questions/48856158/change-icon-of-notification-when-using-osascript-e-display-notification/49079025#49079025
#
# TODO: Implement dialogs https://scriptingosx.com/2018/08/user-interaction-from-bash-scripts/
#

#
# Mac OS X specific scripts
#

##
# Creates a simple Mac OS App from a bash script
#
# Script source: https://gist.github.com/oubiwann/453744744da1141ccc542ff75b47e0cf
# Another helpful link: https://gist.github.com/mathiasbynens/674099
##
function ak.macos.appify() {
  local _appName="My App"
  local _appIcons="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
  local appScript

  while :; do
    case $1 in
      -h | --help )    _ak.macos.appify.usage; return;;
      -s | --script )  appScript="$2"; shift ;;
      -n | --name )    _appName="$2"; shift ;;
      -i | --icons )   _appIcons="$2"; shift ;;
      -v | --version ) _ak.macos.appify.version; return;;
      -- )             shift; break ;;
      * )              break ;;
    esac
    shift
  done

  if [[ -z ${appScript+nil} ]]; then
    _ak.macos.appify.error "the script to appify must be provided!"
    return 1
  fi

  if [[ ! -f "$appScript" ]]; then
    _ak.macos.appify.error "the can't find the script '$appScript'"
    return 2
  fi

  if [[ -a "$_appName.app" ]]; then
    _ak.macos.appify.error "the bundle '$PWD/$_appName.app' already exists"
    return 3
  fi

  local -r _appDir="$_appName.app/Contents"

  mkdir -vp "$_appDir"/{MacOS,Resources}
  cp -v "$_appIcons" "$_appDir/Resources/$_appName.icns"
  cp -v "$appScript" "$_appDir/MacOS/$_appName"
  chmod +x "$_appDir/MacOS/$_appName"

  cat <<EOF > "$_appDir/Info.plist"
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>$_appName</string>
      <key>CFBundleGetInfoString</key>
      <string>$_appName</string>
      <key>CFBundleIconFile</key>
      <string>$_appName</string>
      <key>CFBundleName</key>
      <string>$_appName</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleSignature</key>
      <string>4242</string>
    </dict>
  </plist>
EOF

  echo "Application bundle created at '$PWD/$_appName.app'"
  echo
}

function _ak.macos.appify.version() {
  local -r _version=4.0.1
  echo "${_version}"
}

function _ak.macos.appify.error {
  echo
  echo "ERROR: $1" >&2
  echo
  _ak.macos.appify.usage
}

function _ak.macos.appify.usage() {
  local -r _script='ak.macos.appify.usage'
  local -r _appIcons="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"

  cat <<EOF
Appify v$(_ak.macos.appify.version) for Mac OS X - https://gist.github.com/oubiwann/453744744da1141ccc542ff75b47e0cf

Usage:
  $_script [options]

Options:
  -h, --help      Prints this help message, then exits
  -s, --script    Name of the script to 'appify' (required)
  -n, --name      Name of the application (default "$_appName")
  -i, --icons     Name of the icons file to use when creating the app
                        (defaults to $_appIcons)
  -v, --version   Prints the version of this script, then exits

Description:
  Creates the simplest possible Mac app from a shell script.
  Appify has one required parameter, the script to appify:
    $_script --script my-app-script.sh
  Note that you cannot rename appified apps. If you want to give your app
  a custom name, use the '--name' option
    $_script --script my-app-script.sh --name "Sweet"

Copyright:
  Copyright (c) Thomas Aylott <http://subtlegradient.com/>
  Modified by Mathias Bynens <http://mathiasbynens.be/>
  Modified by Andrew Dvorak <http://OhReally.net/>
  Rewritten by Duncan McGreggor <http://github.com/oubiwann/>
EOF
}

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
