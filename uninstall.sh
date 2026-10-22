#!/bin/bash
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

# Only removes our links; local.conf stays
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME/.config" -D config
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME" -D home

if [ -d /usr/share/sddm/themes/custom ]; then
  echo "[+] Removing SDDM theme..."
  sudo rm -r /usr/share/sddm/themes/custom
  sudo rm -f /etc/sddm.conf.d/custom-theme.conf
  sudo rm -f /etc/sddm/mango.conf /etc/sddm/Xsetup
fi
