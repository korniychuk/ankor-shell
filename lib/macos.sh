#!/usr/bin/env bash

#
# Mac OS X specific scripts
#

#
# Create separate Chrome launcher
# https://apple.stackexchange.com/questions/66670/is-there-a-simple-way-to-have-separate-dock-icons-for-different-chrome-profiles
# Notice:
#   - Depends of perl
#
function ak.macos.createChromeEnvironment() {
  local -r profileName="${1}"
  local -r remoteDebuggingPort="${2}"

  #
  # 0. Looking for the Google Chrome
  #
  # TODO: try -r
  local chromeAppDir=$(mdfind 'kMDItemCFBundleIdentifier == "com.google.Chrome"' | head -1)
  local -r chromeBin="$chromeAppDir/Contents/MacOS/Google Chrome"
  if [[ ! -e "${chromeBin}" ]]; then
    echo "ERROR: Can not find Google Chrome. Exiting."
    exit 1
  fi

  #
  # 1. Directory creation
  #
  local -r customAppDir="/Applications/Google Chrome ${profileName}.app"
  local -r wrapperDir="${customAppDir}/Contents/MacOS"
  mkdir -p "${wrapperDir}"
  echo " * Directory created: ${wrapperDir}"

  #
  # 2. Wrapper generation
  #
  local -r wrapperFileName="wrapper.sh"
  local -r wrapperShFilePath="${wrapperDir}/${wrapperShFilePath}"

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

  echo " * wrapper.sh generated as ${wrapperShFilePath}"
  if [[ ! -z "${remoteDebuggingPort}" ]]; then
    echo " * Remote Debugging enabled on the ${remoteDebuggingPort} port"
  fi

  #
  # 3. Make the wrapper executable
  #
  chmod +x "$wrapperShFilePath"
  echo " * Execution access added to the wrapper"

  #
  # 4. Copy Item.plist from the original Chrome
  #
  cp "${chromeAppDir}/Contents/Info.plist" "${customAppDir}/Contents/"
  echo " * Info.plist copy-pasted"
  cat "${chromeAppDir}/Contents/Info.plist" | perl -0777 -pe "s/(<key>CFBundleDisplayName<\/key>\n\s+<string>.+?)(<\/string>)/\$1 ${profileName}\$2/" | head
  echo " * CFBundleDisplayName updated to 'Google Chrome ${profileName}'"


  echo "Done! /Applications/Google Chrome ${profileName}.app"
  echo "You can change the app icon manually"
}
