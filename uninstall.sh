#!/bin/bash
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

# Only mangifera's own links go; ~/.config/mango/local.conf and anything else
# beside them stays
stow --no-folding -v -t "$HOME/.config" -D config
