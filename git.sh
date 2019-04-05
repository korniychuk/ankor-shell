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
