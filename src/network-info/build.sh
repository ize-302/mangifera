#!/bin/bash
# Builds network-info into home/.local/bin/network-info, which stow links to
# ~/.local/bin/network-info. Run it from anywhere:
#
#   src/network-info/build.sh
#
# install.sh runs this too.

# Stop at the first command that fails
set -e

# This script's folder (src/network-info), whatever folder it's run from
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The repo root, two folders up
repo=$(cd "$here/../.." && pwd)

# -trimpath leaves your folder paths out of the binary; -s -w drops debug
# info, which makes it smaller
go build -C "$here" -trimpath -ldflags='-s -w' -o "$repo/home/.local/bin/network-info" .

echo "Built $repo/home/.local/bin/network-info"
