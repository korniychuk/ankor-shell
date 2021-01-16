#!/usr/bin/env bash

##
# .m3u8 videos downloader
#
# @param {string}     url      full URL beginning from http/https
# @param {string}     fileName output file name without extension
# @param {string=mkv} fileExt  output file extension (format)
#
# @example <caption>Saves the video in 'My Video.mkv' file in the current directory</caption>
#
#   $ ak.downloader.m3u8 "http://....com/..../asdfasdfwef.m3u8" "My Video"
#
# Notice: depends on ffmpeg
# Helpful Links:
# - https://apple.stackexchange.com/questions/158360/how-to-download-m3u8-stream-to-local-hd-in-os-x
##
function ak.downloader.m3u8() {
  local -r _url="${1}"
  local -r _fileName="${2}"
  local -r _fileExt="${3:-mkv}"

  if [[ -z "${_url}" ]] || [[ -z "${_fileName}" ]]; then
    echo 'Invalid arguments' >&2
    return 1
  fi

  local _preparedUrl; _preparedUrl="$(perl -pe 's/(?<=m3u8).*$//g' <<< "$_url")"

  # Notice: "User Agent" is important key for many online cinema.
  ffmpeg \
    -user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/601.7.8 (KHTML, like Gecko) Version/9.1.3 Safari/537.86.7" \
    -i "${_preparedUrl}" \
    -c copy "${_fileName}.${_fileExt}"
}
