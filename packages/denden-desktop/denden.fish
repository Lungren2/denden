# Den Den's setup for fish, the shell in Ghostty. fish loads this before
# ~/.config/fish/config.fish, so anything set there wins.

# PATH and the rest of the environment come from the bash login shell that
# starts fish (see Ghostty's config); a fish started some other way gets
# Den Den's own additions here.
fish_add_path --global --move --path \
    $HOME/.local/bin (set -q MISE_DATA_DIR; and echo $MISE_DATA_DIR; or echo $HOME/.local/share/mise)/shims

status is-interactive; or return

set --global fish_greeting                  # no welcome text

# The prompt: folder, git branch and state, and the language a project
# pins, in Den Den's colours. ~/.config/starship.toml replaces it.
if command -q starship
    set -q STARSHIP_CONFIG; or test -e $HOME/.config/starship.toml
    or set --global --export STARSHIP_CONFIG /usr/share/denden/starship.toml
    starship init fish | source
end

# `z <part of a folder name>` jumps to a folder you've been in.
command -q zoxide; and zoxide init fish | source

# Ctrl+R searches history and Ctrl+T finds files, both as fuzzy lists.
command -q fzf; and fzf --fish | source

# Habits from PowerShell and Windows.
abbr --add --global cls clear
abbr --add --global ii xdg-open             # Invoke-Item: open in its app
