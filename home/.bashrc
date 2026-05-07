#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

up() {
  if command -v yay >/dev/null 2>&1; then
    yay -Syu "$@"
  else
    echo "yay not installed; updating official packages only" >&2
    sudo pacman -Syu "$@"
  fi
}

upcheck() {
  if command -v checkupdates >/dev/null 2>&1; then
    checkupdates
  else
    echo "checkupdates not installed; showing repo updates from local sync state" >&2
    pacman -Qu
  fi
  if command -v yay >/dev/null 2>&1; then
    yay -Qua
  else
    echo "yay not installed; skipping AUR update check" >&2
  fi
}

_prepend_path() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

_prepend_path "$HOME/.local/bin"
_prepend_path "$HOME/bin"
export PATH
unset -f _prepend_path

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# AI Aliases
alias ai_chat='~/projects/gemma_host/scripts/chat.sh'
alias ai_stop='~/projects/gemma_host/scripts/stop_user_server.sh'
alias ai_start='~/projects/gemma_host/scripts/start_user_server.sh'
alias ai_restart='ai_stop && ai_start'
alias ai_agent='~/projects/gemma_host/scripts/pi.sh'
