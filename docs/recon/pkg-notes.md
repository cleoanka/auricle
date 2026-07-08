# Auricle packaging verification — all steps done for real in /tmp/auricle-pkg

Environment: macOS 26.5.1, Swift 6.3.2, arm64. Dummy package at `/tmp/auricle-pkg/Hello`, tested script at `/tmp/auricle-pkg/build-app.sh`, template at `/tmp/auricle-pkg/Info-template.plist`.

## Verification results

1. **Build — CRITICAL toolchain finding.** `swift build -c release` with the default `xcode-select` (=/Library/Developer/CommandLineTools) **fails to even compile Package.swift**: `Undefined symbols for architecture arm64: PackageDescription.Package.__allocating_init(...)` — a CLT/PackageDescription mismatch on this machine. With `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` it builds in ~4 s. The build script auto-exports DEVELOPER_DIR when Xcode.app exists; keep this or Auricle builds will fail on this Mac.
2. **Bundle assembly**: Contents/MacOS/<exe> + Contents/Info.plist is sufficient; `plutil -lint` OK. No PkgInfo needed.
3. **Codesign**: `codesign --force --deep --sign -` succeeds; verify reports "valid on disk / satisfies its Designated Requirement". Also verified **after zip roundtrip** (`ditto -c -k --keepParent` → extract → verify: OK).
4. **Launch test: SUCCESS.** `open Hello.app` → `pgrep -x Hello` found the process after 3 s, app ran as accessory (menu-bar-only, LSUIElement + `.accessory` policy), killed cleanly. Repeated with the script-assembled `dist/Hello.app` (icon embedded): also launched OK.
5. **Universal build: FEASIBLE.** `swift build -c release --arch arm64 --arch x86_64` works (needs DEVELOPER_DIR=Xcode). Binary lands at **`.build/apple/Products/Release/<name>`** (NOT `.build/release/`), confirmed fat: `x86_64 arm64`. Script prefers universal with fallback to native.
6. **Icon pipeline: fully available.** python3 has **PIL 11.0.0**; `iconutil` and `sips` both present at /usr/bin. Verified flow: PIL renders 1024px PNG → `sips -z S S` for 16/32/128/256/512 + @2x into `AppIcon.iconset/icon_SxS[@2x].png` → `iconutil -c icns AppIcon.iconset -o AppIcon.icns` → valid icns (ic12 type). If PIL were absent, pure-sips fallback works: generate base art any way (even `sips` on a screenshot or a solid PNG via AppKit/Swift), then the same sips-resize loop — sips alone covers all resizing; only the 1024 source needs another origin.
7. **SMAppService.mainApp with ad-hoc signing outside /Applications — caveats:**
   - launchd records the login item by **path + code-signing identity**. Ad-hoc signatures have no Team ID and a per-build cdhash, so **every rebuild invalidates the registered identity** → item can show as broken/"unidentified developer" in System Settings > General > Login Items, or silently fail at login. Mitigation: call `register()` (idempotent) on every app launch when the user preference says enabled.
   - **App Translocation**: if the user runs the quarantined app straight from ~/Downloads, it executes from a randomized read-only /private/var path; registering from there records a path that won't exist next boot. Mitigation: detect translocation (bundle path contains `/AppTranslocation/`) and refuse to register, prompting the user to move the app to /Applications first.
   - Moving/renaming the .app after registration orphans the entry.
   - Graceful handling prescription: wrap in do/catch; inspect `SMAppService.mainApp.status` — on `.requiresApproval` call `SMAppService.openSystemSettingsLoginItems()` and show a hint; on thrown error (e.g. Operation not permitted / internal failure) keep the "Launch at login" toggle OFF, show a non-blocking message ("Couldn't enable launch at login — move Auricle to /Applications and try again"), never crash or block core functionality. Treat login-item as best-effort.

## Gatekeeper reality for zip downloaders (ad-hoc signed)

- `spctl --assess` on the ad-hoc app: **rejected** (verified). Locally built apps run fine because they carry no quarantine xattr — that's why the launch test passed.
- A user downloading `Auricle-<v>.zip` via a browser gets `com.apple.quarantine` on the extracted app → Gatekeeper blocks with "cannot be opened because Apple cannot check it / from an unidentified developer".
- Escape hatches to document in the README:
  - **Right-click (Ctrl-click) → Open → Open** (on macOS 15+/Sequoia this may take: attempt open, then System Settings > Privacy & Security > "Open Anyway", then open again).
  - Or terminal: `xattr -dr com.apple.quarantine /Applications/Auricle.app`
- `ditto -c -k --keepParent` is the right archiver — preserves the signature/resource fork (verified by post-extract codesign).
- The **NSAudioCaptureUsageDescription** TCC prompt fires independently of Gatekeeper once the app runs and touches Core Audio taps; the key is in the plist template. Note: with ad-hoc signing, the TCC grant is keyed to the signature — rebuilds may re-prompt users.
- Real fix long-term: Developer ID signing + notarization; ad-hoc + quarantine-strip instructions are acceptable for a GitHub-releases hobby distribution.

## Deliverable usage

Place `build-app.sh` and the `Info.plist` template (as `Info.plist`) in the package root next to `Package.swift`, optional icon at `Resources/AppIcon.icns`, optional `VERSION` file. Output: `dist/Auricle.app` + `dist/Auricle-<version>.zip`. The exact script+template were run end-to-end against the dummy with `APP_NAME=Hello` and produced a working, signed, launchable universal app.
