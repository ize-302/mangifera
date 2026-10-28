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

[Unreleased]: https://github.com/ize-302/mangifera/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/ize-302/mangifera/releases/tag/v0.3.0
[0.2.1]: https://github.com/ize-302/mangifera/releases/tag/v0.2.1
[0.2.0]: https://github.com/ize-302/mangifera/releases/tag/v0.2.0
[0.1.4]: https://github.com/ize-302/mangifera/releases/tag/v0.1.4
[0.1.3]: https://github.com/ize-302/mangifera/releases/tag/v0.1.3
[0.1.2]: https://github.com/ize-302/mangifera/releases/tag/v0.1.2
[0.1.1]: https://github.com/ize-302/mangifera/releases/tag/v0.1.1
[0.1.0]: https://github.com/ize-302/mangifera/releases/tag/v0.1.0
