#!/usr/bin/env bash

# cd aliases
alias cdh="cd ~"
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../../'

# fs info aliases
if ls --color=auto &> /dev/null; then
  unalias ls &> /dev/null # remove default alias
  alias ls="ls --color=auto"
elif gls --color=auto &> /dev/null; then # OS: Mac OS X, default ls doesn't support coloring. But GNU version available
  alias ls="gls --color=auto"
fi
alias l="ls -lhF"
alias ll="ls -lhAF"
alias l.="ls -lhAFd .*" # shows only hidden files (started from .)
alias duof='du --max-depth=1 -h'

# Search
alias f='find . -iname'
alias ff='find . -type f -iname'
alias fd='find . -type d -iname'
alias g='grep . -ri -e'

# Other
alias hh='ak.sh.history'
alias j='jobs -l'
alias rr="rm -rf"
alias e="exit"
alias v="vim"
alias vz="v ~/.zshrc"
alias gpn="ak.git.push --no-verify"  # Git Push with No verify
alias gln="git pull --no-edit"       # Git puLl with No edit
alias gpp='gln && gpn'               # Git Pull & Push
alias gcb='echo "Git Branch: $(ak.git.getCurrentBranch) (copied)" && ak.git.copyCurrentBranch' # Git Copy Branch
alias akhelp="ak.sh.showConfig"

# Inet
alias ic="ak.inet.check; echo; ak.inet.ping.DNS"
alias myip='echo -e "IPv4: $(ak.inet.getExternalIPv4)\nIPv6: $(ak.inet.getExternalIPv6)"'

if [[ -x "${PWD}/.ak-init.sh" ]] && [[ -z "${LOCAL_AK_SHELL_INITIALIZED}" ]]; then
  export LOCAL_AK_SHELL_INITIALIZED=true
  # shellcheck source=/dev/null
  source "${PWD}/.ak-init.sh"
  echo "Loaded: ./.ak-init.sh"
fi
