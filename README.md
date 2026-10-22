# Mangifera

A clean [mango](https://github.com/DreamMaoMao/mangowc) desktop for Arch Linux

A frosted-glass [waybar](https://github.com/Alexays/Waybar), plus a
[Quickshell](https://quickshell.org) shell for everything else.

## Install

Needs Arch Linux and a user with sudo. Packages come from the official repos
(listed in `install.sh`).

```sh
git clone <this repo> ~/mangifera
cd ~/mangifera
./install.sh --dry-run   # preview
./install.sh
```

The installer installs packages, links the configs, installs the SDDM theme,
and enables SDDM and Bluetooth. It's safe to rerun.

- Another login manager already enabled is left alone; it prints how to
  switch.
- NetworkManager isn't enabled for you; it warns if it's off.
- Existing files in the way stop the install. `--backup` moves them to
  `~/.mangifera-backup-<time>/`.
- `--no-packages` skips packages.
- An existing `~/.config/tmux` is kept.

## Wallpapers

Put images in `~/Pictures/wallpapers`. Super+Shift+W picks a random one,
which persists across logins. Without any, the bundled
`home/.local/share/mangifera/default-wallpaper.jpg` is used.

## Your own settings

Displays, keyboard layout and extra bindings go in
`~/.config/mango/local.conf`, which mango reads last:

```
monitor_rule=name:DP-2,x:0,y:0
monitor_rule=name:eDP-1,x:1920,y:0,scale:1.4
xkb_rules_layout=us,de
```

`mmsg get all-monitors` lists output names.

The login screen runs its own mango (`/etc/sddm/mango.conf`) and ignores
these scales. To scale it, add e.g. `/etc/sddm.conf.d/scale.conf`:

```
[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=eDP-1=1.4;DP-2=1
```

## Uninstall

```sh
~/mangifera/uninstall.sh
```

Removes the links and the login theme; `local.conf` stays.
