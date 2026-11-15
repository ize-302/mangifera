# Changelog

Versions follow [SemVer](https://semver.org). Before 1.0, a minor bump
(0.x.0) can break your setup: its **Breaking** section says what to do.
Patch bumps (0.x.y) are fixes and tweaks.

To update:

```sh
cd ~/mangifera
git pull
./install.sh
```

## [Unreleased]

### Breaking

- alacritty is no longer the terminal, and its config is gone from
  mangifera. Your terminal is `$TERMINAL`: add `env=TERMINAL,alacritty` (or
  foot, kitty, wezterm, ghostty) to `~/.config/mango/local.conf`. Unset, the
  first installed of foot, kitty, alacritty, wezterm and ghostty opens.
  install.sh now installs foot, not alacritty.
- The `~/.config/alacritty/alacritty.toml` link breaks. To keep that config
  as your own file, remove the link first, then write it out:

  ```sh
  rm ~/.config/alacritty/alacritty.toml
  git -C ~/mangifera show b43af82:config/alacritty/alacritty.toml > ~/.config/alacritty/alacritty.toml
  ```
- Run `./install.sh` after `git pull`: until then, Super+Return, terminal
  apps from the launcher, Thunar's Open Terminal Here and Open in Neovim, and
  btop do nothing.

### Added

- `terminal` (`~/.local/bin/terminal`, built from `src/terminal`) opens
  `$TERMINAL`, with `--cwd DIR`, `--class NAME` and a command to run. It
  knows each terminal's flags for these. Super+Return, the launcher, Thunar
  and btop-toggle open terminals through it.
- mango passes `$TERMINAL` on to apps started by D-Bus, so Thunar's actions
  use it when another app opened Thunar.

## [0.12.0] - 2026-11-15

### Added

- Notes: Super+M (or Notes in the toolbox) opens a panel listing every
  Markdown note in `~/Notes`, subfolders too, newest first, beside an editor.
  It saves as you type, and a note's first line is its title. Ctrl+N starts a
  new note, the search box (Ctrl+F) looks through titles and text, Alt+Up/Down
  switches notes, and Ctrl+Shift+Backspace moves one to the trash after
  asking. Run `./install.sh` after `git pull` to link the new panel.

## [0.11.0] - 2026-11-15

### Breaking

- `focus-window`, `move-window` and `focus-urgent` are built from source:
  until `./install.sh` runs after `git pull`, Super+H/L, Super+Shift+H/L
  (and with the arrows) do nothing, and urgent windows aren't focused. Then
  remove the leftover link with `rm ~/.local/lib/mangifera/window-edge.sh`.
- So are `primary-output` and `laptop-screen`: until `./install.sh` runs,
  logging in doesn't open a terminal on the external display, and closing
  the lid doesn't turn the laptop's screen off.
- So is `clock-status`: until `./install.sh` runs, the bar's clock is blank.
- So is `bluetooth-audio`: until `./install.sh` runs, a Bluetooth device's
  page in the control panel shows no audio profiles to pick.
- So is `gtk-radius`: run `./install.sh` before rerunning it after an
  adw-gtk-theme update.
- So are `bar-anchor` and `bar-watchdog`: until `./install.sh` runs, popups
  from the bar open where the pointer is instead of over their module, and
  nothing restarts waybar when it spins.
- So is `mango-reload`: until `./install.sh` runs, Super+Shift+R does
  nothing.

### Changed

- `focus-window`, `move-window` (Super+H/L, Super+Shift+H/L) and
  `focus-urgent` are written in Go instead of bash, as one program, and no
  longer run `jq`.
- `primary-output` (focuses the external display at login and as displays
  are plugged in and out) and `laptop-screen` (the laptop's screen on the lid
  switch) are written in Go instead of bash, as one program, and no longer
  run `jq`.
- `clock-status` (the bar's two-line clock) is written in Go instead of sh.
- `bluetooth-audio` (the audio profiles on a Bluetooth device's page in the
  control panel) is written in Go instead of bash.
- `gtk-radius` (caps adw-gtk3's corner radii at 4px in
  `~/.config/gtk-3.0/radius.css`) is written in Go instead of bash and awk.
- `bar-anchor` (places popups over the bar module they're for) and
  `bar-watchdog` (restarts waybar when it spins) are written in Go instead
  of bash and awk, and the watchdog no longer runs `pgrep` or `top`.
- `mango-reload` (Super+Shift+R) is written in Go instead of bash.

### Fixed

- `gtk-radius` writes the repo's `config/gtk-3.0/radius.css` through stow's
  link, instead of replacing the link with a file of its own.
- GTK3 apps' corners like the ends of linked buttons and entries are capped
  at 4px too: `gtk-radius` now copies `border-top-left-radius` and the other
  corners, which it missed. `config/gtk-3.0/radius.css` has 40 more rules.
- `bar-watchdog`'s log lists the threads that used over half a core during
  the minute, measured from `/proc`. It listed lines of `top`'s header
  instead (`top(user,%) Threads:(d-sleep,%) ...`).

## [0.10.0] - 2026-11-14

### Breaking

- `screenshot` is built from source: until `./install.sh` runs after
  `git pull`, Super+S and the toolbox's Screenshot do nothing.
- `cam-toggle` is built from source too: until `./install.sh` runs, it
  doesn't show, hide, rotate or zoom the webcam bubble.
- So is `wallpaper`: until `./install.sh` runs, the desktop has no wallpaper
  after logging in, and Super+Shift+W and the toolbox's Random Wallpaper do
  nothing.
- And so are `record-toggle` and `record-status`: until `./install.sh` runs,
  screen recording doesn't start or stop, and the bar shows no recording
  timer. After it, restart waybar (Super+Shift+R) so the bar uses the new
  `record-status`.

### Added

- Copying a screenshot in satty (Ctrl+C) shows a "Screenshot copied"
  notification. Before, only saving one did.

### Changed

- `screenshot` (Super+S and the toolbox's Screenshot) is written in Go
  instead of bash.
- `wallpaper` (sets the wallpaper at login, on Super+Shift+W and from the
  toolbox, and again on each display that turns on) is written in Go instead
  of bash.
- Screen recording (`record-toggle`, the bar's timer, `record-status`, and
  `cam-toggle`, which shows, hides, rotates and zooms the webcam bubble) is
  written in Go instead of bash, as one program. While recording, the bar's
  timer no longer starts `pgrep` and `ps` every second. If `record-toggle` is
  stopped mid-recording, it still removes the Recording sound device it made.

## [0.9.0] - 2026-11-14

### Breaking

- `btop-toggle` is built from source: until `./install.sh` runs after
  `git pull`, clicking the bar's CPU or memory module doesn't open btop.

### Changed

- `btop-toggle` (btop as a scratchpad, from the bar's CPU and memory
  modules) is written in Go instead of bash, and opens btop in `$TERMINAL`
  when that's alacritty, kitty, foot, wezterm or ghostty. Without `$TERMINAL`, it
  uses the first of them that's installed (alacritty, as before).

## [0.8.0] - 2026-11-14

### Breaking

- The control panel's Wi-Fi helper is now built from source, so run
  `./install.sh` after `git pull`. Until then, network details, connecting
  with a password and joining a hidden network don't work. With
  `--no-packages`, install `go` first.
- The commands that open menus and lock the screen are built from source
  too: until `./install.sh` runs after `git pull`, menu key bindings and bar
  clicks do nothing, and the screen doesn't lock, not even when idle.

### Changed

- The Wi-Fi helper behind the control panel (`network-info`) is written in
  Go instead of bash. `./install.sh` installs `go` and builds it.
- The Bluetooth pairing agent's source moved to `src/bluetooth-agent/`.
- The commands that open the launcher's menus (`app-menu`, `control-panel`,
  `power-menu`, `lock-screen` and the rest) are one Go program instead of
  bash scripts, so a key press reaches the menu about twice as fast.
  `./install.sh` no longer installs `socat`.
- `lock-screen` counts the screen as already locked only when the locker
  itself is running, not any program whose command line mentions it.

## [0.7.1] - 2026-11-13

### Changed

- The bar shows each app's icon once per tag, with a dot under it for each
  window when it has more than one (up to three).
- The bar's scratchpad shows the icons of the apps parked in it, stacked and
  set apart from the tags in a bordered pill, instead of dots. Hovering it
  spreads them out into a row.

## [0.7.0] - 2026-11-12

### Added

- Switching tag briefly shows its number on the bar, in place of its icons.

### Changed

- The bar shows a tag's number only when the tag is empty; a tag with windows
  shows just their icons. Picture-in-picture windows no longer count as being
  on a tag.
- The bar is more opaque.
- The key mode badge on the bar (e.g. "scroll") is white instead of red.
- The bar no longer blurs what's behind it.

### Fixed

- A window brought back from the scratchpad menu tiles again, instead of
  floating at the scratchpad's size.

## [0.6.1] - 2026-10-28

### Changed

- The bar, its tooltips, the launcher's panels and popups, and the login
  screen's menu are black instead of dark grey. The bar is also slightly
  more opaque.

## [0.6.0] - 2026-10-28

### Added

- Pomodoro key bindings: Super+P starts or pauses the timer, Super+Shift+P
  skips to the next phase and Super+Ctrl+P resets it.

## [0.5.0] - 2026-10-28

### Added

- Scratchpad overview: the scratchpad as a full-screen grid of previews over
  the dimmed desktop, like macOS Mission Control. h/j/k/l or the arrows move
  through it. `scratchpadStyle` in the launcher's `Theme.qml` switches
  between it (`"overview"`) and the strip (`"strip"`).
- Backspace closes the selected scratchpad window, like Delete.

### Changed

- The focused window's border is white instead of orange, and so is the
  selected scratchpad card's.
- Unfocused windows are dimmed more.
- The scratchpad menu has a header with its window count, and centres its
  cards while they don't fill the strip.
- The scratchpad's close button is a tab in a hovered card's top right
  corner, white while hovered. In the overview it's a larger square, white
  with a dark ✕ while its card is hovered.
- Hovering a scratchpad card no longer moves the selection; clicking still
  brings it out.
- Scratchpad previews are grabbed about 3× faster, take less memory, and are
  retried when a grab fails instead of staying blank.
- Lighter blur (2 passes instead of 3).

## [0.4.0] - 2026-10-28

### Breaking

- Super+H/L no longer always switch tags: they move the focus left or right,
  and switch to the previous or next tag only from the edge of this one.
  Super+Ctrl+H/J/K/L are gone; use Super+H/J/K/L.

### Changed

- Super+J/K move the focus down and up.
- After Super+H/L (or Super+Left/Right) switch tags, the focus lands on the
  window at the edge you came in from.
- Super+Shift+H/L (and Super+Shift+Left/Right) move a window that's already
  at the left or right edge of its tag to the previous or next tag, and
  follow it. Away from the edge they still swap it with its neighbour.

## [0.3.0] - 2026-10-28

### Breaking

- `~/.local/bin/bar-tags` is gone. Remove its leftover link with
  `rm ~/.local/bin/bar-tags`.
- The launcher's Quickshell files are grouped into folders by feature (bar,
  osd, control panel, date panel, notifications, record, menus, prompts,
  services, widgets). After `./install.sh`, remove the old broken links with
  `find ~/.config/quickshell/launcher -xtype l -delete`.

### Changed

- The bar's tags show each window's real app icon instead of a Nerd Font
  glyph. Tags, the scratchpad count and the key mode are now drawn by
  Quickshell over the left end of waybar.
- Quickshell watches mango's windows once instead of twice, and skips updates
  when only a window's title, position or size changed.
- The bar has a light blur behind it, and is a little more see-through.
- Super+Shift+R also restarts waybar, so bar config changes show up.
- The volume control comes before the toolbox in the bar.

## [0.2.1] - 2026-10-25

- Fix the laptop screen having no wallpaper after unplugging an external
  display.
- Fix the power menu, launcher, keybind and record menus not opening after
  every display turned off at once (as when unplugging with the lid closed).
- Super+Shift+R no longer restarts Quickshell, so reloading takes a fraction
  of a second instead of several. Quickshell still reloads its own files when
  they change.

## [0.2.0] - 2026-10-25

- Record menu redesign.
- FPS (30, 60, 120 and max fps) options.
- Camera choice selection.
- Modify settings during recording.

## [0.1.4] - 2026-10-25

### Changed

- README shows the screen recorder and lock screen.

## [0.1.3] - 2026-10-25

### Changed

- Simpler README with screenshots of the features.

## [0.1.2] - 2026-10-25

- Release script

## [0.1.1] - 2026-10-25

### Added

- MIT license (LICENSE).

## [0.1.0] - 2026-10-25

First release.

### Added

- mango desktop with a frosted-glass waybar and a Quickshell shell
  (launcher, notifications, toolbox, camera widget).
- Screenshots with satty; screen recording with wf-recorder, optionally
  with the camera.
- Random persistent wallpapers with awww (Super+Shift+W), shared with the
  SDDM login screen.
- Bluetooth pairing agent; audio switches to a Bluetooth device once it
  connects.
- Noise-canceling mic (RNNoise filter chain).
- Laptop screen turns off when the lid is closed.
- Trackpad gesture for the scratchpad; extra mouse button bindings.
- Notification on mango config reload.
- `install.sh` with `--dry-run`, `--no-packages` and `--yes`: backs up
  conflicting files and records what it changed.
- `uninstall.sh` undoes only what the installer changed and restores
  backed-up files.

[Unreleased]: https://github.com/ize-302/mangifera/compare/v0.12.0...HEAD
[0.12.0]: https://github.com/ize-302/mangifera/releases/tag/v0.12.0
[0.11.0]: https://github.com/ize-302/mangifera/releases/tag/v0.11.0
[0.10.0]: https://github.com/ize-302/mangifera/releases/tag/v0.10.0
[0.9.0]: https://github.com/ize-302/mangifera/releases/tag/v0.9.0
[0.8.0]: https://github.com/ize-302/mangifera/releases/tag/v0.8.0
[0.7.1]: https://github.com/ize-302/mangifera/releases/tag/v0.7.1
[0.7.0]: https://github.com/ize-302/mangifera/releases/tag/v0.7.0
[0.6.1]: https://github.com/ize-302/mangifera/releases/tag/v0.6.1
[0.6.0]: https://github.com/ize-302/mangifera/releases/tag/v0.6.0
[0.5.0]: https://github.com/ize-302/mangifera/releases/tag/v0.5.0
[0.4.0]: https://github.com/ize-302/mangifera/releases/tag/v0.4.0
[0.3.0]: https://github.com/ize-302/mangifera/releases/tag/v0.3.0
[0.2.1]: https://github.com/ize-302/mangifera/releases/tag/v0.2.1
[0.2.0]: https://github.com/ize-302/mangifera/releases/tag/v0.2.0
[0.1.4]: https://github.com/ize-302/mangifera/releases/tag/v0.1.4
[0.1.3]: https://github.com/ize-302/mangifera/releases/tag/v0.1.3
[0.1.2]: https://github.com/ize-302/mangifera/releases/tag/v0.1.2
[0.1.1]: https://github.com/ize-302/mangifera/releases/tag/v0.1.1
[0.1.0]: https://github.com/ize-302/mangifera/releases/tag/v0.1.0
