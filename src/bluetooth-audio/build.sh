#!/bin/bash
# Builds bluetooth-audio into home/.local/bin/bluetooth-audio, which stow links to
# ~/.local/bin/bluetooth-audio. Run it from anywhere:
#
#   src/bluetooth-audio/build.sh
#
# install.sh runs this too.

# Stop at the first command that fails
set -e

# This script's folder (src/bluetooth-audio), whatever folder it's run from
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The repo root, two folders up
repo=$(cd "$here/../.." && pwd)

# -trimpath leaves your folder paths out of the binary; -s -w drops debug
# info, which makes it smaller
go build -C "$here" -trimpath -ldflags='-s -w' -o "$repo/home/.local/bin/bluetooth-audio" .

echo "Built $repo/home/.local/bin/bluetooth-audio"
