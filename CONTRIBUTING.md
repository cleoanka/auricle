# Contributing to Auricle

Thanks for your interest in improving Auricle. This is a small, dependency-free
Swift/SwiftUI menu bar app built on macOS 14.4+ Core Audio process taps.

## Requirements

- macOS **14.4** or later.
- **Full Xcode** (not just the Command Line Tools). SwiftPM linking of an executable
  target can fail against the bare CLT toolchain, so point at Xcode:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```

## Build, test, run

```sh
# Build the package
swift build

# Run the unit tests (pure logic — no audio hardware needed)
swift test

# Headless diagnostics (dumps devices/defaults/processes as JSON, creates no taps)
swift run Auricle --probe

# Package a signed .app bundle into dist/
./scripts/build-app.sh
```

## Coding conventions

- Formatting follows [`.editorconfig`](.editorconfig): UTF-8, LF, 4-space indent,
  final newline, no trailing whitespace, 120-column soft limit for Swift.
- [SwiftLint](https://github.com/realm/SwiftLint) is an optional local aid,
  configured in [`.swiftlint.yml`](.swiftlint.yml). It does not gate CI.
- Keep the app dependency-free. No third-party packages.

## Tests

- New logic that can be tested without audio hardware should get a unit test in
  `Tests/AuricleTests`. To reach package-internal symbols from tests, use
  `@testable import Auricle`.
- CI runs `swift build -c release` and `swift test` on macOS 14. Keep it green.

## Versioning

- [`VERSION`](VERSION) is the single source of truth for the release number.
  `AppInfo.version` must match it — a unit test and a CI step both enforce this.
  When bumping the version, update `VERSION`, `AppInfo.version`, and `CHANGELOG.md`
  together.

## Commits & pull requests

- Write focused commits with clear messages. Update `CHANGELOG.md` under
  `[Unreleased]` for user-facing changes.
- Match the existing language and style of the file you are editing.
