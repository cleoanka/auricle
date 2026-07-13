# Changelog

All notable changes to Auricle are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- XCTest unit-test target (`Tests/AuricleTests`) covering the EQ coefficient
  generator, model logic, and settings round-tripping — no audio hardware required.
- GitHub Actions CI (`swift build -c release` + `swift test` on macOS 14) with a
  version-consistency check between the `VERSION` file and `AppInfo.version`.
- `.editorconfig`, `.swiftlint.yml`, `CONTRIBUTING.md`, and this changelog.

## [0.2.1] — 2026-07-08

### Changed
- Apps routed to a specific device are now pinned: switching the top-level output
  device no longer affects them in any state.
- An engine in unplugged-fallback follows default-output changes immediately and
  snaps back the moment its device returns.

### Added
- Routing badge on app rows (→ device name) showing which apps are pinned; it turns
  into a warning while the routed device is unplugged.
- Drag-to-Applications DMG packaging with in-window install instructions (TR + EN).

## [0.2.0] — 2026-07-08

### Changed
- UI redesign: Output and Input devices are always-visible stacked lists with
  one-click selection (Control Center style) — no more dropdown pickers.
- The per-app overflow menu is gone; each app row has a single disclosure chevron
  that expands an inline drawer (routing, Boost slider, 10-band EQ, Reset).

### Added
- A routed device that gets unplugged shows an honest inline warning row (settings
  kept; audio falls back to System Default until it returns).

## [0.1.1] — 2026-07-08

### Fixed
- Popover collapsed to an empty sliver inside the MenuBarExtra window (ScrollView
  reported no intrinsic height); the scroll region is now sized from measured content.

### Changed
- System Audio Recording permission is probed at launch (immediate prompt/banner)
  instead of waiting for the first slider touch.
- The audio engine logs chain-up and failures to the unified log.

## [0.1.0] — 2026-07-08

### Added
- First release: per-app volume, mute, boost (+12 dB), 10-band EQ, and output-device
  routing.
- System-wide master Boost + EQ, device and input control, EQ presets, and per-app
  settings memory.
- Universal binary (Apple Silicon + Intel), macOS 14.4+.

[Unreleased]: https://github.com/cleoanka/auricle/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/cleoanka/auricle/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/cleoanka/auricle/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/cleoanka/auricle/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/cleoanka/auricle/releases/tag/v0.1.0
