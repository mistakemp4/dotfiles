source /usr/share/cachyos-fish-config/cachyos-config.fish

export PATH="$HOME/.local/bin:$PATH"

zoxide init fish | source
fzf --fish | source
if test -f ~/.config/fzf/themes/noctalia.fish
    set -gx FZF_DEFAULT_OPTS (string match -r -a -- '--color=[^"\\\\]+' < ~/.config/fzf/themes/noctalia.fish)
end
starship init fish | source
