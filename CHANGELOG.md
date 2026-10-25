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

[Unreleased]: https://github.com/ize-302/mangifera/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/ize-302/mangifera/releases/tag/v0.1.1
[0.1.0]: https://github.com/ize-302/mangifera/releases/tag/v0.1.0
