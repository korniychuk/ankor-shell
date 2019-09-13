#!/usr/bin/env bash

function ak.git.replaceCommitsAuthorOrCommitter() {
  local -r oldEmail="${1}"
  local -r correctName="${2}"
  local -r correctEmail="${3}"

  if [[ -z "${oldEmail}" ]]; then
    echo 'ArgError: oldEmail required' >&2
    return 1
  fi
  if [[ -z "${correctName}" ]]; then
    echo 'ArgError: correctName required' >&2
    return 1
  fi
  if [[ -z "${correctEmail}" ]]; then
    echo 'ArgError: correctEmail required' >&2
    return 1
  fi

  git filter-branch -f --env-filter "
    if [ \"\$GIT_COMMITTER_EMAIL\" = \"${oldEmail}\" ]
    then
      export GIT_COMMITTER_NAME=\"${correctName}\"
      export GIT_COMMITTER_EMAIL=\"${correctEmail}\"
    fi
    if [ \"\$GIT_AUTHOR_EMAIL\" = \"${oldEmail}\" ]
    then
      export GIT_AUTHOR_NAME=\"${correctName}\"
      export GIT_AUTHOR_EMAIL=\"${correctEmail}\"
    fi
  " --tag-name-filter cat -- --branches --tags

  return $?
}

function ak.git.replaceCommitsAuthorOrCommitterUsingGlobal() {
  local -r oldEmail="${1}"

  if [[ -z "${oldEmail}" ]]; then
    echo 'ArgError: oldEmail required' >&2
    return 1
  fi

  local -r correctName=$(git config --global user.name)
  local -r correctEmail=$(git config --global user.email)
  if [[ -z "${correctName}" ]]; then
    echo 'Error: can not find user.name in the global GIT config' >&2
    return 1
  fi
  if [[ -z "${correctEmail}" ]]; then
    echo 'Error: can not find user.email in the global GIT config' >&2
    return 1
  fi

  ak.git.replaceCommitsAuthorOrCommitter "${oldEmail}" "${correctName}" "${correctEmail}"
  return $?
}

#
# Examples:
#
# 1. View local info
#   ak.git.auth
#
# 2. View global info
#   ak.git.auth g
#
# 3. Update local info
#   ak.git.auth 'user name' 'user email'
#
# 4. Update global info
#   ak.git.auth g 'user name' 'user email'
#
# TODO: Implement better params parsing
#
function ak.git.auth() {
  if [[ ${#} -eq 1 ]] || [[ ${#} -ge 3 ]]; then
    local -r level="${1:-l}"; shift
  else
    local -r level="l"
  fi

  case "${level}" in
    l)
      local -r baseCommand="git config"
      local -r intro="GIT Local config:"
      ;;
    g)
      local -r baseCommand="git config --global"
      local -r intro="GIT Global config:"
      ;;
    *)
      echo 'ArgError: incorrect level' >&2
      return 1
      ;;
  esac

  if [[ ${#} -eq 2 ]]; then
    local -r updateInfo='(updated)'

    local -r userName="${1}"
    local -r userEmail="${2}"

    if [[ -z "${userName}" ]]; then
      echo 'ArgError: userName required' >&2
      return 1
    fi
    if [[ -z "${userEmail}" ]]; then
      echo 'ArgError: userEmail required' >&2
      return 1
    fi

    eval "${baseCommand}" user.name "'${userName}'"
    eval "${baseCommand}" user.email "'${userEmail}'"
  else
    local -r updateInfo=''
  fi

  echo "${intro}"
  echo "user.name:\t$(eval ${baseCommand} user.name)\t${updateInfo}"
  echo "user.email:\t$(eval ${baseCommand} user.email)\t${updateInfo}"

  return 0
}

#
# Shows current branch name
#
function ak.git.getCurrentBranch() {
  git rev-parse --abbrev-ref HEAD
}

#
# Shows current branch name
#
function ak.git.getCurrentTag() {
  git describe --exact-match --tags $(git log -n1 --pretty='%h')
}

#
# Shows hash of the current HEAD
#
function ak.git.getCurrentHash() {
  git rev-parse HEAD
}

#
# Shows short hash of the current HEAD
#
function ak.git.getCurrentShortHash() {
  git rev-parse --short HEAD
}

function ak.git.log() {
  local -r count="${1:-25}"

  git \
    --no-pager \
    log \
      --pretty=format:"%h | %ad | %<(20)%an | %s" \
      --graph \
      --date=format:'%Y-%m-%d %H:%M:%S' \
      --max-count="${count}" \
    | cut -c 1-140
}

function ak.git.isClean() {
  # TODO: move the logic to normalize boolean function
  local careAboutUnTracked="${1}"
  if   [[ "${careAboutUnTracked}" == "false" ]] \
    || [[ "${careAboutUnTracked}" == "no" ]] \
    || [[ "${careAboutUnTracked}" == "0" ]] \
    || [[ "${careAboutUnTracked}" == "" ]]
  then
    careAboutUnTracked="no"
  else
    careAboutUnTracked="yes"
  fi

  if [[ -z "$(git status --untracked-files=${careAboutUnTracked} --porcelain)" ]]; then
    # Working directory clean excluding untracked files
    return 0;
  else
    # Uncommitted changes in tracked files
    return 1;
  fi
}

#
# If remote version of the local branch exists (origin/{local-branch-name}) executes
# 'git push "${@}"' otherwise 'git push --set-upstream origin ${branch} "${@}"'
#
# TODO: remove Perl dependency
# TODO: use mac notificator
#
# Examples:
#
# 1. Just push
#   ak.git.push
#
# 2. Without git hooks
#   ak.git.push --no-verify
#
# Helpful info: in ZSH you can type 'git.p' press TAB and it'll be transformed to 'ak.git.push'
#
function ak.git.push() {
  local hasOrigins=$(git status -sb | head -n 1 | grep origin | wc -l | perl -pe 's/\s//g')

  if [[ "${hasOrigins}" == "1" ]]; then
    git push "${@}"

    echo "Pushed"
    ak.bash.commandExists osascript && osascript -e 'display notification "Pushed"'
  else
    local branch=$(git branch --list | grep "^\* " | perl -pe 's/^\* //g')
    git push --set-upstream origin ${branch} "${@}"

    echo "Pushed with --set-upstream"
    ak.bash.commandExists osascript && osascript -e 'display notification "Pushed with --set-upstream"'
  fi
}

function ak.git.commitForDate() {
  export Y=2012
  export M=12
  export D=20
  export GIT_COMMITTER_DATE="$Y-$M-$D 12:00:00"
  export GIT_AUTHOR_DATE="$Y-$M-$D 12:00:00"
  git commit --date="$Y-$M-$D 12:00:00" -m "Committed on $M $D $Y"
}
