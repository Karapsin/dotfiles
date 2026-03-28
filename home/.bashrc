#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

up() {
  yay -Syu "$@"
}

upcheck() {
  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates
  else
    echo "checkupdates not installed; showing repo updates from local sync state" >&2
    pacman -Qu
  fi
  yay -Qua
}

# Created by `pipx` on 2026-02-02 16:56:09
export PATH="$PATH:/home/kardinal/.local/bin"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH="$HOME/bin:$PATH"
