# Auricle — Implementation Contract

This repository is being implemented by four parallel agents on **disjoint file sets**. The
skeleton already compiles; every public type/signature in it is a **locked contract** — do not
rename or change signatures. Fill in the `AGENT-TODO(<owner>)` bodies for the files you own.

## Ownership

| Owner  | Files |
|--------|-------|
| `core` | `Support/CoreAudioUtils.swift`, `Audio/AudioDeviceManager.swift`, `Support/Probe.swift` |
| `proc` | `Audio/AudioProcessMonitor.swift`, `Model/AudioController.swift`, `Model/SettingsStore.swift` |
| `dsp`  | `Audio/ProcessTapEngine.swift`, `Audio/GraphicEQ.swift` |
| `ui`   | everything under `UI/` |

`Model/Models.swift`, `AuricleApp.swift`, `Package.swift` are shared and **frozen**. If you
believe a contract change is unavoidable, do NOT make it — finish what you can and report the
needed change in your final message; the integrator reconciles.

## Rules

1. Touch only your files. Other agents edit theirs concurrently in the same checkout.
2. IMPORTANT: the default CommandLineTools SwiftPM is broken on this machine. ALWAYS build with
   `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.
   Check your work with `swift build --scratch-path /tmp/auricle-b-<owner> 2>&1 | tail -40`.
   Ignore errors in files you don't own (they may be mid-edit); iterate until **your** files
   produce zero errors and zero warnings.
3. No third-party dependencies. Frameworks allowed: CoreAudio, AudioToolbox, Accelerate,
   AppKit, SwiftUI, ServiceManagement, os.
4. Threading: all `@Published` mutations on the main actor. CoreAudio listener callbacks hop to
   main via their dispatch queue. Engine control work runs on per-engine serial queues.
5. Realtime (IO block) rules: no allocation, no ObjC dispatch, no logging, no unbounded locks.
   Parameter snapshots via `os_unfair_lock_trylock` (keep last snapshot on contention) or
   pre-swapped pointers. Level meters may use plain aligned Float stores.
6. Errors: never crash on CoreAudio failures. Devices/processes can vanish at any moment;
   degrade gracefully. Engine failures go through `onFailure` ("permission:" prefix for TCC).
7. Style: 4-space indent, no header comments, comments only where the code can't speak.

## Key facts (verified on this machine — see the recon findings passed in your prompt)

- macOS 26.5, Swift 6.3.2 (language mode 5), SDK = CommandLineTools. Min target macOS 14.4.
- Per-process capture via `CATapDescription` + `AudioHardwareCreateProcessTap` + private
  aggregate device with the tap in its tap list; `muteBehavior = .mutedWhenTapped` silences the
  original app audio while Auricle replays it processed.
- System-wide (master) chain MUST follow the exclusion sequence documented at the top of
  `ProcessTapEngine.swift` to avoid a feedback loop.
- Aggregate UIDs must start with `AudioDeviceManager.auricleAggregatePrefix` so the device
  manager can filter them out of user-visible lists.
