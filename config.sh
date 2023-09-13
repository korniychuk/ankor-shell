#!/usr/bin/env bash

# variables
export PATH="$PATH:$HOME/.local/bin"

# cd aliases
alias cdh="cd ~"
alias cdhd="cd ~/Downloads"
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'
alias mdc="ak.sh.mkdirAndCd"

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

if [[ -x "$(command -v 'gdu')" ]]; then
  alias duof='gdu --max-depth=1 -h'
else
  alias duof='du --max-depth=1 -h'
fi

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
if [[ -x "$(command -v 'nvim')" ]]; then
  alias v='nvim'
  alias vv='v ~/.config/nvim/init.vim'
else
  alias v='vim'
  alias vv='v ~/.vimrc'
fi
alias vz="v ~/.zshrc"
alias gpn="ak.git.push --no-verify"  # Git Push with No verify
alias gpnf="gpn --force"             # Git Push with "No verify" & "Force"
alias gln="git pull --no-edit"       # Git puLl with No edit
alias gpp='gln && gpn'               # Git Pull & Push
alias gcb='echo "Git Branch: $(ak.git.getCurrentBranch) (copied)" && ak.git.copyCurrentBranch' # Git Copy Branch
alias lg="lazygit"
alias akhelp="ak.sh.showConfig"

alias h1='head -n 10'
alias h='head -n 25'
alias h5='head -n 50'
alias h0='head -n 100'

alias t1='tail -n 10'
alias t='tail -n 25'
alias t5='tail -n 50'
alias t0='tail -n 100'

# Inet
alias ic="ak.inet.check; echo; ak.inet.ping.DNS"
alias myip='echo -e "IPv4: $(ak.inet.getExternalIPv4)\nIPv6: $(ak.inet.getExternalIPv6)"'

if [[ -x "${PWD}/.ak-init.sh" ]] && [[ -z "${LOCAL_AK_SHELL_INITIALIZED}" ]]; then
  export LOCAL_AK_SHELL_INITIALIZED=true
  # shellcheck source=/dev/null
  source "${PWD}/.ak-init.sh"
  echo "Loaded: ./.ak-init.sh"
fi
