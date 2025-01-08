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

function ak.git.copyCurrentBranch() {
  ak.git.getCurrentBranch | ak.str.trimFinalNewLine | pbcopy
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

function ak.git.copyCurrentHash() {
  ak.git.getCurrentHash | ak.str.trimFinalNewLine | pbcopy
}

#
# Shows short hash of the current HEAD
#
function ak.git.getCurrentShortHash() {
  git rev-parse --short HEAD
}

function ak.git.copyCurrentShortHash() {
  ak.git.getCurrentShortHash | ak.str.trimFinalNewLine | pbcopy
}

##
# Display formatted git log with optional count and additional git arguments
#
# Usage:
#   ak.git.log [<count>] [-- <git-log-args>...]
#
# Parameters:
#   count         : Number of commits to show (default: 25)
#   git-log-args  : Additional arguments passed directly to git log
#
# Output format:
#   <hash> | <date> | <author> | <subject>
#
# Examples:
#   ak.git.log                     # Show last 25 commits
#   ak.git.log 10                  # Show last 10 commits
#   ak.git.log -- libs/features    # Show commits for specific path
#   ak.git.log 10 -- --author="John" --since="1 week ago"
#
# Notes:
#   - Output is limited to 140 characters per line
#   - Date format: YYYY-MM-DD HH:MM:SS
#   - Author name is padded to 20 characters
#
# Output example:
#   * 21c8b15b516 | 2024-12-16 07:43:58 | Anton Kor     | Settings → Email branding: update Pendo event & link (#45074)
#   * c015e2d33b3 | 2024-11-21 10:53:25 | Anton Kor     | Settings → Branding → Email: "Use display name" checkbox (#44234)
#   * 5a1cbf8542e | 2024-11-20 19:53:24 | Metier        | Angular18 5 (#44204)
#   * e7db97e9a2f | 2024-11-08 11:25:56 | John Neo      | GitPod improvements (#43806)
#
##
function ak.git.log() {
    local count=25  # default count
    local -a extra_args=()

    # If first arg isn't -- and is a number, use it as count
    if [[ "${1:-}" != "--" && -n "${1:-}" ]]; then
        count="$1"
        shift
    fi

    # Collect all args after --
    if [[ "${1:-}" == "--" ]]; then
        shift
        extra_args+=("$@")
    fi

    git \
        --no-pager \
        log \
            --pretty=format:"%h | %ad | %<(20)%an | %s" \
            --graph \
            --date=format:'%Y-%m-%d %H:%M:%S' \
            --max-count="${count}" \
            "${extra_args[@]}" \
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
    ak.sh.commandExists osascript && osascript -e 'display notification "Pushed"'
  else
    local branch=$(git branch --list | grep "^\* " | perl -pe 's/^\* //g')
    git push --set-upstream origin ${branch} "${@}"

    echo "Pushed with --set-upstream"
    ak.sh.commandExists osascript && osascript -e 'display notification "Pushed with --set-upstream"'
  fi
}

#
# Revert N last commits(in the local history) with preserve changed files
#
# Examples:
#
# 1. Just the last commit
#
#   ak.git.uncommit
#
# 2. 3 last commits
#
#   ak.git.uncommit 3
#
# Notice: in ZSH you can type '.un' and press TAB and it'll be transformed to 'ak.git.uncommit'
#
function ak.git.uncommit() {
  local -r count="${1:-1}"

  git reset --soft "HEAD~${count}"
}

#
# Edit the last commit message
# Notice: in ZSH you can type '.ree' and press TAB and it'll be transformed to 'ak.git.reedit'
#
function ak.git.reedit() {
  git commit --allow-empty --amend
}

#
# Reset all uncommited changes to HEAD
#
function ak.git.reset() {
  git reset --hard HEAD
}

#
# Reset all uncommited changes to origin/{current-branch}
#
function ak.git.reset-remote() {
    git reset --hard "origin/$(ak.git.getCurrentBranch)"
}

#
# TODO: finish it, add validation, and simplify date specification
# Example:
#
#   ak.git.commit "2019-07-22 13:46:55" -m "My Commit"
#
function ak.git.commit() {
  local -r dateTime="${1}"; shift

  export GIT_COMMITTER_DATE="${dateTime}"
  export GIT_AUTHOR_DATE="${dateTime}"
  git commit --date="${dateTime}" "${@}"
}

# TODO: add description
# TODO: add errors handling
function ak.git.getNextCommitId() {
  local -r commitId="${1}"
  local -r targetBranchName="${2:-HEAD}"

  git rev-list "${commitId}..${targetBranchName}" | tail -n 1
}

# TODO: add description
# TODO: add errors handling
function ak.git.getParentCommitId() {
  local -r commitId="${1}"
  git rev-list -n 1 "${commitId}^"
}

# TODO: add description
# TODO: add errors handling
# TODO: notify if commit not found
function ak.git.changeCommitDate() {
  local -r commitId="${1}"
  local -r dateTime="${2}"
  local -r targetBranchName="HEAD"

  local parentCommitId
  parentCommitId=$(ak.git.getParentCommitId "${commitId}")

  git filter-branch -f --env-filter \
    "if [ \"\$GIT_COMMIT\" = \"${commitId}\" ]
     then
            export GIT_AUTHOR_DATE=\"${dateTime}\"
         export GIT_COMMITTER_DATE=\"${dateTime}\"
     fi" "${parentCommitId}..${targetBranchName}" > /dev/null

  ak.git.getNextCommitId "${parentCommitId}"
}

# TODO: add description
# TODO: add errors handling
# TODO: notify if commit not found
function ak.git.changeCommitAuthor() {
  local -r commitId="${1}"
  local -r newName="${2}"
  local -r newEmail="${3}"
  local -r targetBranchName="HEAD"

  local parentCommitId
  parentCommitId=$(ak.git.getParentCommitId "${commitId}")

  git filter-branch -f --env-filter \
    "if [ \"\$GIT_COMMIT\" = \"${commitId}\" ]; then
          export GIT_COMMITTER_NAME=\"${newName}\"
          export GIT_COMMITTER_EMAIL=\"${newEmail}\"
          export GIT_AUTHOR_NAME=\"${newName}\"
          export GIT_AUTHOR_EMAIL=\"${newEmail}\"
     fi" "${parentCommitId}..${targetBranchName}" > /dev/null
}

function ak.git.showCommitsNumberStatistic() {
  git shortlog -s -n --all --no-merges
}

# TODO: add description
# TODO: add errors handling
# TODO: move format to somewhere
function ak.git.getCommitDateTime() {
  local -r commitId="${1}"

  git --no-pager show -s --format=%cd --date=format:'%Y-%m-%d %H:%M:%S' "${commitId}"
}
