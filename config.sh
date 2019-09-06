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
alias hh='ak.bash.history'
alias j='jobs -l'
alias rr="rm -rf"
alias e="exit"
alias v="vim"
alias gpn="ak.git.push --no-verify"
alias akhelp="ak.bash.showConfig"

# Inet
alias ic="ak.inet.check; echo; ak.inet.ping.DNS"
alias ip='echo -e "IPv4: $(ak.inet.getExternalIPv4)\nIPv6: $(ak.inet.getExternalIPv6)"'
