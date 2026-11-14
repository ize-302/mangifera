#!/bin/bash
# Builds launcher-call into home/.local/bin/launcher-call, which stow links
# to ~/.local/bin/launcher-call. app-menu, control-panel, power-menu and the
# rest are symlinks to it there. Run it from anywhere:
#
#   src/launcher/build.sh
#
# install.sh runs this too.

# Stop at the first command that fails
set -e

# This script's folder (src/launcher), whatever folder it's run from
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# The repo root, two folders up
repo=$(cd "$here/../.." && pwd)

# -trimpath leaves your folder paths out of the binary; -s -w drops debug
# info, which makes it smaller
go build -C "$here" -trimpath -ldflags='-s -w' -o "$repo/home/.local/bin/launcher-call" .

echo "Built $repo/home/.local/bin/launcher-call"
