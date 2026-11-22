#!/bin/bash
# Builds drive-watch into home/.local/bin/drive-watch, which stow links to
# ~/.local/bin/drive-watch. Run it from anywhere:
#
#   src/drive-watch/build.sh
#
# install.sh runs this too.

# Stop at the first command that fails
set -e

# This script's folder (src/drive-watch), whatever folder it's run from
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The repo root, two folders up
repo=$(cd "$here/../.." && pwd)

# -trimpath leaves your folder paths out of the binary; -s -w drops debug
# info, which makes it smaller
go build -C "$here" -trimpath -ldflags='-s -w' -o "$repo/home/.local/bin/drive-watch" .

echo "Built $repo/home/.local/bin/drive-watch"
