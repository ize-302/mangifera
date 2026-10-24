#!/bin/bash
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

say() { echo "[+] $*"; }
note() { echo "[!] $*"; }

# What install.sh changed (see remember there)
state="${XDG_STATE_HOME:-$HOME/.local/state}/mangifera/installed"

# Only removes our links; local.conf stays
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME/.config" -D config
stow --no-folding --ignore='\.qmlls\.ini' -v -t "$HOME" -D home

# Put back what install.sh moved aside. Newest first: it's what was there
# right before the last install. Nothing is overwritten; what can't go back
# stays in its backup folder.
stashes=("$HOME"/.mangifera-backup-*)
for ((i = ${#stashes[@]} - 1; i >= 0; i--)); do
  stash=${stashes[i]}
  [ -d "$stash" ] || continue
  say "Restoring your files from $stash"
  while IFS= read -r -d '' f; do
    dest="$HOME/${f#"$stash"/}"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      note "  kept in the backup, $dest already exists"
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$f" "$dest"
  done < <(find "$stash" \( -type f -o -type l \) -print0)
  find "$stash" -depth -type d -empty -delete
done

if [ -e "$state/file-manager" ]; then
  previous=$(cat "$state/file-manager")
  if [ -n "$previous" ]; then
    say "Making $previous the file manager again"
    xdg-mime default "$previous" inode/directory ||
      note "Couldn't set it. Run: xdg-mime default $previous inode/directory"
  else
    say "Removing Thunar as the default file manager"
    sed -i '/^inode\/directory=thunar\.desktop;\{0,1\}$/d' "$HOME/.config/mimeapps.list" 2>/dev/null || true
  fi
fi

if [ -e "$state/filter-chain" ]; then
  say "Turning off the noise-canceling mic"
  systemctl --user disable --now filter-chain ||
    note "Couldn't. From your desktop session, run: systemctl --user disable --now filter-chain"
fi

# The login screen is shared by everyone who installed mangifera (the
# mangifera group), so it's only removed with the last of them
others=
if getent group mangifera >/dev/null; then
  id -nG "$USER" | grep -qw mangifera && sudo gpasswd -d "$USER" mangifera >/dev/null
  others=$(getent group mangifera | cut -d: -f4)
fi

if [ -n "$others" ]; then
  note "Leaving the login screen, other users still use mangifera: $others"
else
  if [ -d /usr/share/sddm/themes/custom ]; then
    echo "[+] Removing SDDM theme..."
    sudo rm -r /usr/share/sddm/themes/custom
    sudo rm -f /etc/sddm.conf.d/custom-theme.conf
    sudo rm -f /etc/sddm/mango.conf /etc/sddm/Xsetup
  fi
  sudo rm -rf /var/lib/sddm-wallpaper
  if getent group mangifera >/dev/null; then
    sudo groupdel mangifera
  fi

  # Not stopped now, so this session keeps running
  if [ -e "$state/sddm" ]; then
    say "Disabling SDDM, which install.sh enabled"
    sudo systemctl disable sddm
    note "From the next boot there's no login screen, only a text login."
    note "To keep SDDM: sudo systemctl enable sddm"
  fi
fi

rm -rf "$state"
say "Uninstalled. Packages and Bluetooth were left as they are."
