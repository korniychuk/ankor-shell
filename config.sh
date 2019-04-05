#!/usr/bin/env bash

# cd aliases
alias cdh="cd ~"
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../../'

# fs info aliases
alias l="ls -lhG"
alias ll="ls -lhAG"
alias l.="ls -lhAGd .*"
alias duof='du --max-depth=1 -h'

# Search
alias f='find . -iname'
alias ff='find . -type f -iname'
alias fd='find . -type d -iname'

# Other
alias hh='ak.bash.history'
alias j='jobs -l'
alias rr="rm -rf"
alias e="exit"
alias v="vim"
