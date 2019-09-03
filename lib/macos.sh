#!/usr/bin/env bash

#
# Mac OS X specific scripts
#

#
# Create a separate Chrome launcher
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
  # 0. Looking for the Google Chrome
  #
  local chromeAppDir=$(mdfind 'kMDItemCFBundleIdentifier == "com.google.Chrome"' | head -1)
  local -r chromeBin="$chromeAppDir/Contents/MacOS/Google Chrome"
  if [[ ! -e "${chromeBin}" ]]; then
    echo "ERROR: Can not find Google Chrome. Exiting." >&2
    return 1
  fi
  echo "  * Check Google Chrome installed - OK"

  #
  # 0. Checking name uniqueness
  #
  local -r customAppDir="/Applications/Google Chrome ${profileName}.app"
  local -r profileDir="/Users/${USER}/Library/Application Support/Google/Chrome/${profileName}"
  if [[ -d "${customAppDir}" ]]; then
    echo "ERROR: Chrome instance with this name already exists. Exiting." >&2
    return 2
  fi
  if [[ -d "${profileDir}" ]]; then
    echo "ERROR: Chrome profile with this name already exists. Exiting." >&2
    return 3
  fi
  echo "  * Checking name uniqueness - OK"

  #
  # 1. Directory creation
  #
  local -r wrapperDir="${customAppDir}/Contents/MacOS"
  mkdir -p "${wrapperDir}"
  echo "  * Directory created: ${wrapperDir}"

  #
  # 2. Wrapper generation
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

  echo "  * Wrapper generated: ${wrapperShFilePath}"

  #
  # 3. Make the wrapper executable
  #
  chmod +x "$wrapperShFilePath"
  echo "  * Add execution permission for the wrapper - OK"

  #
  # 4. Copy Item.plist from the original Chrome
  #
  cp "${chromeAppDir}/Contents/Info.plist" "${customAppDir}/Contents/"
#  echo "  * Info.plist copy-pasted"
#  cat "${chromeAppDir}/Contents/Info.plist" | perl -0777 -pe "s/(<key>CFBundleDisplayName<\/key>\n\s+<string>.+?)(<\/string>)/\$1 ${profileName}\$2/" | head
#  echo "  * CFBundleDisplayName updated to 'Google Chrome ${profileName}'"


  echo;
  echo "  New Chrome Instance generated:"
  echo "    /Applications/Google Chrome ${profileName}.app"
  echo;

  echo "2. Manual part:"
  echo "  * You can change the app icon"
  echo;

  echo "3. To remove the new Chrome instance execute:"
  echo "   $> ak.macos.removeChromeInstance '${profileName}'"
  echo;

  ak.doc.headingLine "Done ;)"
}

function ak.macos.removeChromeInstance() {
  local -r profileName="${1}"

  ak.doc.heading "Chrome Environment Generator"
  echo;

  local -r customAppDir="/Applications/Google Chrome ${profileName}.app"
  local -r profileDir="/Users/${USER}/Library/Application Support/Google/Chrome/${profileName}"

  if [[ -d "${customAppDir}" ]]; then
    rm -rf "${customAppDir}"
    if [[ $? -eq 0 ]]; then
      echo " * Application deleted at: '${customAppDir}'"
    fi
  else
      echo " * Application not found at: '${customAppDir}'"
  fi

  if [[ -d "${profileDir}" ]]; then
    rm -rf "${profileDir}"
    if [[ $? -eq 0 ]]; then
      echo " * Profile deleted at: '${profileDir}'"
    fi
  else
      echo " * Profile not found at: '${profileDir}'"
  fi

  echo;
  ak.doc.headingLine "Done ;)"
}
