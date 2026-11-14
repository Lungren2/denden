# Den Den's shell environment, for login shells (terminals open login shells
# on Den Den, and T3 Code resolves agent tools through one).

# Tools the user installs (~/.local/bin) come first, then mise's shims, so a
# project's mise.toml picks its own Node, Python, … over the system's.
_denden_path_prepend() {
  case ":${PATH}:" in
    *":$1:"*) ;;
    *) PATH="$1:${PATH}" ;;
  esac
}
_denden_path_prepend "${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims"
_denden_path_prepend "${HOME}/.local/bin"
unset -f _denden_path_prepend
export PATH

# Interactive bash: `z` to jump to recent directories, Ctrl+R and Ctrl+T
# through fzf.
if [ -n "${BASH_VERSION:-}" ] && [[ $- == *i* ]]; then
  command -v zoxide >/dev/null && eval "$(zoxide init bash)"
  [ -r /usr/share/fzf/key-bindings.bash ] && . /usr/share/fzf/key-bindings.bash
  [ -r /usr/share/fzf/completion.bash ] && . /usr/share/fzf/completion.bash
fi
