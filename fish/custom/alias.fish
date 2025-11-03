if not set -q DOTFILES_DIR
    set -gx DOTFILES_DIR "$HOME/.config"
end
# ============================= Useful Abbreviations ================================


# System utilities
abbr -a ll 'ls -lhG'
abbr -a l 'ls -A'
abbr -a fid 'ls | grep'

# Reload config
abbr -a r 'source $DOTFILES_DIR/fish/config.fish && clear'

# Clear screen
abbr -a c 'clear && clear'


# ============================= Useful Abbreviations - full ================================
if test "$USER" != "docker-dev"
# Git shortcuts
abbr -a gs 'git status'
abbr -a gp 'git push'
abbr -a ga 'git add '
abbr -a gaa 'git add .'
abbr -a gpll 'git pull'
# open config
abbr -a conf "open -a 'Cursor' $DOTFILES_DIR"
abbr -a cur "open -a 'Cursor' ."
# The Fuck
thefuck --alias | source
abbr -a f 'fuck'
# Navigation shortcuts
abbr -a .. 'z ..'
abbr -a ... 'z ../..'
abbr -a .... 'z ../../..'
# Docker
abbr -a ldk 'lazydocker'
# Zoxide
abbr -a cd 'z'
abbr -a cdd 'z -'
# Lazygit
abbr -a lg 'lazygit'  
# Neofetch
abbr -a rcool 'source $DOTFILES_DIR/fish/config.fish && clear  && neofetch'
# spicetify
abbr -a spot 'spicetify restore backup apply && spicetify apply'
# fzf
abbr -a f 'fzf --preview "bat --style=numbers --color=always --line-range :500 {}"'
# bat4cat
abbr -a cat 'bat'
# venv
abbr -a venv 'source venv/bin/activate.fish'
# docker stop all
abbr -a dstop 'docker stop $(docker ps -q)' 
abbr -a dkill 'docker stop $(docker ps -q) | docker system prune -a --volumes -f'
thefuck --alias | source
abbr -a f 'fuck'
abbr -a cat 'bat'
abbr -a lg 'lazygit'

abbr -a nrd 'npm run dev'
abbr -a nrs 'npm run start'
abbr -a rh 'killall Hammerspoon >/dev/null 2>&1; open -a Hammerspoon && open -a Hammerspoon'

abbr -a ff 'fastfetch '

end





