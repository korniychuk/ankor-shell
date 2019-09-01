#!/usr/bin/env bash

#
# Mac OS X specific scripts
#

#
# Create separate Chrome launcher
# https://apple.stackexchange.com/questions/66670/is-there-a-simple-way-to-have-separate-dock-icons-for-different-chrome-profiles
# TODO: Implement plist generation
#
function ak.macos.createChromeEnvironment() {
  local -r profileName="${1}"
  local -r remoteDebuggingPort="${2}"

  mkdir -p "/Applications/Google Chrome $1.app/Contents/MacOS"

  local F="/Applications/Google Chrome $1.app/Contents/MacOS/Google Chrome $1"
  cat > "$F" <<\EOF
#!/usr/bin/env bash

#
# Google Chrome for Mac with additional profile.
#

# Name your profile:
EOF

  echo "declare -r profileName='${profileName}'\n" >> "$F"

  cat >> "$F" <<\EOF

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
  echo "${command}\n" >> "$F"

  # TODO: try without sudo
  chmod +x "$F"
}
