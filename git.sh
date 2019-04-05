#!/usr/bin/env bash

function ak::git:replaceCommitsAuthorOrCommitter() {
    local -r oldEmail="${1}"
    local -r correctName="${2}"
    local -r correctEmail="${3}"

    if [[ -z "${oldEmail}" ]]; then
        echo 'ArgError: oldEmail required' >&2
        return 1
    fi
    if [[ -z "${oldEmail}" ]]; then
        echo 'ArgError: correctName required' >&2
        return 1
    fi
    if [[ -z "${oldEmail}" ]]; then
        echo 'ArgError: correctEmail required' >&2
        return 1
    fi

    return git filter-branch -f --env-filter "
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
}
