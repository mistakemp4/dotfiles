source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
export PATH="$HOME/.local/bin:$PATH"

zoxide init fish | source
fzf --fish | source
# noctalia's fzf theme file appends to a universal var every time it's sourced, so just pull its colors
if test -f ~/.config/fzf/themes/noctalia.fish
    set -gx FZF_DEFAULT_OPTS (string match -r -a -- '--color=[^"\\\\]+' < ~/.config/fzf/themes/noctalia.fish)
end
starship init fish | source
