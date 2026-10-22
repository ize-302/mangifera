#!/bin/bash
# mangifera's installer: links config/ into ~/.config with stow.
#
#   ./install.sh             install
#   ./install.sh --dry-run   say what it would do, change nothing
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

dry=
for arg in "$@"; do
  case "$arg" in
  --dry-run) dry=-n ;;
  -h | --help)
    sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Unknown option: $arg (see --help)" >&2
    exit 1
    ;;
  esac
done

command -v stow >/dev/null || { echo "[!] stow isn't installed: sudo pacman -S stow" >&2; exit 1; }

# Each file linked on its own (--no-folding), so ~/.config/mango stays a real
# folder and ~/.config/mango/local.conf can hold your own settings. Stow stops
# without changing anything if a file is already where one of these goes.
echo "[+] Linking config/ into ~/.config"
mkdir -p "$HOME/.config"
stow $dry -v --no-folding -t "$HOME/.config" config
