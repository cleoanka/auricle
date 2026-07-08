## Environment
- **SDK**: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` (CommandLineTools, macOS 26.5 / build 25F80). Host OS macOS 26.5.1, Apple Silicon.
- Everything below verified against real headers in `CoreAudio.framework/Versions/A/Headers/`. `taptest.swift` typechecks clean with `swiftc -typecheck -target arm64-apple-macos14.4`. `probe.swift`/`respcheck.swift` compiled and RAN.
- Deliverables live in `/tmp/auricle-recon/`: `taptest.swift`, `probe.swift` (+ built `probe`), `respcheck.swift` (+ built `respcheck`).

## Process Tap creation (AudioHardwareTapping.h) — Objective-C ONLY header
- The header is wrapped in `#ifdef __OBJC__`. **It is unavailable from a pure C / non-ObjC context.** From Swift it is fine (Swift imports the ObjC clang module). If you ever bridge from C++, you need an ObjC++ shim.
- `func AudioHardwareCreateProcessTap(_ inDescription: CATapDescription!, _ outTapID: UnsafeMutablePointer<AudioObjectID>!) -> OSStatus` — **`API_AVAILABLE(macos(14.2))`** (NOT 14.4 — safe for your 14.4 target). Takes a `CATapDescription*` (the live object, not a dict).
- `func AudioHardwareDestroyProcessTap(_ inTapID: AudioObjectID) -> OSStatus` — `macos(14.2)`.
- Both are throwing-free OSStatus C functions (no Swift `throws` variant).

## CATapDescription (CATapDescription.h) — availability & EXACT Swift spellings
- Class `API_AVAILABLE(macos(12.0))`; the enum + the mixdown inits you need are usable on 14.4.
- **Enum `CATapMuteBehavior`** `API_AVAILABLE(macos(13.0))`. ObjC cases `CATapUnmuted / CATapMuted / CATapMutedWhenTapped` import to Swift as **`.unmuted`, `.muted`, `.mutedWhenTapped`**. Confirmed `.mutedWhenTapped` compiles.
- **Initializers are `NS_REFINED_FOR_SWIFT`** but the refined Swift signatures take **`[AudioObjectID]` (i.e. `[UInt32]`), NOT `[NSNumber]`**. This was the #1 correction. Use:
  - `CATapDescription(stereoMixdownOfProcesses: [AudioObjectID])`
  - `CATapDescription(stereoGlobalTapButExcludeProcesses: [AudioObjectID])`
  - (also available: `initMonoMixdownOfProcesses:`, `initMonoGlobalTapButExcludeProcesses:`, `initWithProcesses:andDeviceUID:withStream:`, `initExcludingProcesses:andDeviceUID:withStream:`)
  - Passing `[NSNumber]` FAILS to compile ("cannot convert value of type '[NSNumber]' to expected argument type '[AudioObjectID]'"). The AudioObjectIDs must be **process object IDs** (from `kAudioHardwarePropertyProcessObjectList` / TranslatePID), NOT raw pids.
- **Properties (verified Swift names):**
  - `.name: String` (ObjC `name`).
  - `.uuid: UUID` — ObjC property is `UUID` typed `NSUUID*`; imports to Swift as **`uuid` returning a Foundation `UUID` value type** (NOT `NSUUID`). Correction: I initially typed `NSUUID` and it failed. This `uuid` string (`.uuid.uuidString`) is what you put in the aggregate `kAudioSubTapUIDKey`.
  - `.muteBehavior: CATapMuteBehavior` (settable; ObjC getter is `isMuted`, Swift still exposes `muteBehavior`).
  - `.isPrivate: Bool` (ObjC `privateTap`, getter `isPrivate`, setter `setPrivate:`) — set `true` for a private tap only visible to your process.
  - `.isExclusive: Bool` (ObjC `exclusive`) — true means "tap everything EXCEPT the listed processes" (this is what the global-exclude init sets).
  - Other props present: `.isMono`, `.isMixdown`, `.deviceUID: String?`, `.processes` (refined), `.stream` (refined). `bundleIDs` and `isProcessRestoreEnabled` exist but are **`macos(26.0)` — do NOT use on 14.4**.

## Aggregate device (AudioHardware.h)
- `func AudioHardwareCreateAggregateDevice(_ inDescription: CFDictionary, _ outDeviceID: UnsafeMutablePointer<AudioObjectID>) -> OSStatus` (macOS 10.9+).
- `func AudioHardwareDestroyAggregateDevice(_ inDeviceID: AudioObjectID) -> OSStatus` (async teardown; may complete after return).
- **Dict keys are `#define`d C string literals** (Swift imports them as `String` constants — usable directly as `[String: Any]` keys, then cast the whole dict `as CFDictionary`). Verified spellings + underlying literal:
  - `kAudioAggregateDeviceNameKey` = "name"
  - `kAudioAggregateDeviceUIDKey` = "uid"
  - `kAudioAggregateDeviceIsPrivateKey` = "private" (CFNumber 0/1; 1 = private, not persistent)
  - `kAudioAggregateDeviceIsStackedKey` = "stacked" (0 = all outputs fed same data = what you want for replay)
  - `kAudioAggregateDeviceMainSubDeviceKey` = "master" (CFString = the sub-device UID that is time source)
  - `kAudioAggregateDeviceSubDeviceListKey` = "subdevices" (CFArray of CFDictionary)
  - `kAudioSubDeviceUIDKey` = "uid"
  - `kAudioSubDeviceDriftCompensationKey` = "drift"
  - `kAudioAggregateDeviceTapListKey` = "taps" (CFArray of CFDictionary)
  - `kAudioAggregateDeviceTapAutoStartKey` = "tapautostart" (CFNumber; nonzero = wait for first tapped audio. **Docs REQUIRE the private key also be set when using tapautostart.**)
  - `kAudioSubTapUIDKey` = "uid" (this is the tap's UUID string, from `CATapDescription.uuid.uuidString` or `kAudioTapPropertyUID`)
  - `kAudioSubTapDriftCompensationKey` = "drift"
- Note the raw literals collide ("uid","drift" are reused across sub-device/sub-tap) — always key them inside the correct sub-dictionary. Also note `kAudioAggregateDeviceClockDeviceKey` = "clock" exists if you want an explicit clock device.
- **Post-creation settable tap list:** `kAudioAggregateDevicePropertyTapList` = `'tap#'` (`AudioObjectPropertySelector`). Header says it is **"A CFArray of CFStrings that contain the UUIDs of all the tap objects"** — so its data type for AudioObject get/set is a `CFArray` of tap-UUID CFStrings, at scope Global / element Main. Companion read-only `kAudioAggregateDevicePropertySubTapList` = `'atap'` returns active sub-tap AudioObjectIDs. (`kAudioAggregateDevicePropertyComposition`='acom', `...FullSubDeviceList`='grup', `...ActiveSubDeviceList`='agrp', `...MainSubDevice`='amst' also available.)

## IOProc (AudioHardware.h)
- `func AudioDeviceCreateIOProcIDWithBlock(_ outIOProcID: UnsafeMutablePointer<AudioDeviceIOProcID?>, _ inDevice: AudioObjectID, _ inDispatchQueue: dispatch_queue_t?, _ inIOBlock: AudioDeviceIOBlock) -> OSStatus`.
  - **`inDispatchQueue` is nullable — passing `nil` IS allowed; header states "If this value is NULL, then the IOBlock will be directly invoked"** (i.e. on the HAL's own realtime IO thread). Pass `nil` for lowest-latency realtime EQ processing.
  - `outIOProcID` is `AudioDeviceIOProcID?` (optional). Declare `var procID: AudioDeviceIOProcID? = nil` and pass `&procID`.
- **`AudioDeviceIOBlock` Swift type** = `(UnsafePointer<AudioTimeStamp>, UnsafePointer<AudioBufferList>, UnsafePointer<AudioTimeStamp>, UnsafeMutablePointer<AudioBufferList>, UnsafePointer<AudioTimeStamp>) -> Void` — params `(inNow, inInputData, inInputTime, outOutputData, inOutputTime)`. Tap audio arrives in `inInputData`; write processed audio to `outOutputData`. Marked `CA_REALTIME_API` (no allocation/locks inside).
- `AudioDeviceStart(_ inDevice: AudioObjectID, _ inProcID: AudioDeviceIOProcID?) -> OSStatus` (procID nullable).
- `AudioDeviceStop(_ inDevice: AudioObjectID, _ inProcID: AudioDeviceIOProcID?) -> OSStatus`.
- `AudioDeviceDestroyIOProcID(_ inDevice: AudioObjectID, _ inIOProcID: AudioDeviceIOProcID) -> OSStatus` — **`inIOProcID` is NON-optional**; you must unwrap the optional from creation before destroying (correction #3: `if let procID = procID { AudioDeviceDestroyIOProcID(...) }`).
- Note the `@convention(c)` **AudioDeviceIOProcID** function-pointer type is distinct and carries 7 params incl. a client-data ptr — but with the *block* API you never see it; you only hold the opaque `AudioDeviceIOProcID?`.

## Process objects (AudioHardware.h)
- Selectors on `kAudioObjectSystemObject`, scope Global, element Main:
  - `kAudioHardwarePropertyProcessObjectList` = 'prs#' (array of AudioObjectID).
  - `kAudioHardwarePropertyTranslatePIDToProcessObject` = 'id2p' — **qualifier IN = `pid_t` (4 bytes), data OUT = AudioObjectID**. Returns `kAudioObjectUnknown` (0) with `status==noErr` when the pid has no audio process object (does NOT error).
- Per-process-object selectors (scope Global): `kAudioProcessPropertyPID` = 'ppid' (pid_t/Int32), `kAudioProcessPropertyBundleID` = 'pbid' (CFString), `kAudioProcessPropertyIsRunning` = 'pir?' (UInt32 bool), `kAudioProcessPropertyIsRunningInput` = 'piri', `kAudioProcessPropertyIsRunningOutput` = 'piro'.

## Tap object properties (AudioHardware.h)
- `kAudioTapPropertyUID` = 'tuid' (CFString persistent tap UID).
- `kAudioTapPropertyDescription` = 'tdsc' (the CATapDescription; gettable AND settable to modify an existing tap).
- `kAudioTapPropertyFormat` = 'tfmt' (**AudioStreamBasicDescription** — read this after creating the tap to learn the sample rate / channel count / format the aggregate will expose; drives your EQ setup + buffer sizing). Scope Global, element Main.

## Accelerate / vDSP EQ (vDSP.h)
- `vDSP_biquadm_CreateSetup(_ __coeffs: UnsafePointer<Double>, _ __M: vDSP_Length /*sections*/, _ __N: vDSP_Length /*channels*/) -> vDSP_biquadm_Setup?` (returns optional; nil on failure). Coefficient buffer layout = **5 doubles per section per channel** in order (b0,b1,b2,a1,a2), i.e. `5 * M * N` doubles. macОС 10.9+.
- `vDSP_biquadm(_ setup, _ __X: UnsafePointer<UnsafePointer<Float>>, _ __IX: vDSP_Stride, _ __Y: UnsafePointer<UnsafeMutablePointer<Float>>, _ __IY: vDSP_Stride, _ __N: vDSP_Length)` — **per-channel array of pointers** (X and Y are `Float**`, one row per channel; `_ __nonnull`). This is the FLOAT (single-precision) processing call — process float audio through a Double-coefficient setup.
- `vDSP_biquadm_SetTargetsDouble(_ setup, _ __targets: UnsafePointer<Double>, _ __interp_rate: Float, _ __interp_threshold: Float, _ __start_sec: vDSP_Length, _ __start_chn: vDSP_Length, _ __nsec: vDSP_Length, _ __nchn: vDSP_Length)` — smoothly ramps coefficients to new targets (use this to change EQ bands without clicks; interp_rate ~0.99x, small threshold). macOS 10.11+. (Sibling `vDSP_biquadm_SetCoefficientsDouble` for instantaneous set.)
- `vDSP_biquadm_DestroySetup(_ setup: vDSP_biquadm_Setup)`. macOS 10.9+.
- `vDSP_vrampmul2(_ __I0, _ __I1: UnsafePointer<Float>, _ __IS: vDSP_Stride, _ __Start: UnsafeMutablePointer<Float>, _ __Step: UnsafePointer<Float>, _ __O0, _ __O1: UnsafeMutablePointer<Float>, _ __OS: vDSP_Stride, _ __N: vDSP_Length)` — **stereo (2-channel) ramped gain multiply**: applies a linear gain ramp (Start, incremented by Step) to two channels at once; `Start` is updated in place. Ideal for click-free gain changes on your L/R replay buffers. macOS 10.6+.
- Note: there are `...D` double-precision twins for all of these (`vDSP_biquadm_CreateSetupD`, `vDSP_biquadmD`, `vDSP_vrampmul2D`) if you process Float64 audio.

## Runtime probe findings (STEP 3) — sequencing implications
- Process object list works; each app that has touched CoreAudio has an object with pid + bundleID. Note **some process objects have an empty bundleID** (CLI tools, incl. our own probe) — don't assume bundleID is non-empty.
- `isRunningOutput` is a live "currently producing output audio" flag (only CoreSpeech + arkaudiod were `Y` at probe time; Spotify was present but idle `n`). Use it to show "who is making sound now."
- Device enumeration works; `transportType` fourcc examples seen: `'bltn'` built-in, `'blue'` Bluetooth (AirPods), `'ccwd'` Continuity Camera, `'grup'` an aggregate/multi-output. Channel counts via `kAudioDevicePropertyStreamConfiguration` per scope. Default output/input resolved correctly (AirPods).
- **TranslatePIDToProcessObject sequencing (critical for global-tap own-exclusion):**
  - `getpid()` (self) -> **VALID** object. Notably self got a valid object *because the probe had already talked to the HAL*; the translate call itself is enough to register. So to exclude your own process from a global tap, call `TranslatePIDToProcessObject(getpid())` and it returns your process AudioObjectID reliably once your app has initialized CoreAudio.
  - `getppid()` (parent zsh) and `pid 1` (launchd) both return **`kAudioObjectUnknown` (0) with status noErr** — non-audio processes simply have no process object. So: guard for `obj != kAudioObjectUnknown`; a 0 result is "no audio object," not an error. For global-exclude, only pass process-object IDs you actually resolved (dropping any that came back 0).

## STEP 4 — responsibility_get_pid_responsible_for_pid
- **Resolves via `dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")` and WORKS.** It is a private libsystem symbol (no public header) — call through a typed C function pointer `@convention(c) (pid_t) -> pid_t`.
- On the probe (a CLI launched from iTerm2) `responsible_pid(getpid())` returned the **iTerm2 GUI ancestor pid (13941)**, not self. For a normal bundled .app it typically returns its own pid. Use it to map a helper/child pid back to the responsible GUI app when attributing audio to a user-visible application. Since it is private API, wrap it defensively (it resolved here but is not App-Store-guaranteed).

## Corrections I had to make to reach a clean typecheck
1. `CATapDescription(stereoMixdownOfProcesses:)` / `(stereoGlobalTapButExcludeProcesses:)` take **`[AudioObjectID]`, not `[NSNumber]`** (the NS_REFINED_FOR_SWIFT overlay changes the type).
2. `CATapDescription.uuid` is a Foundation **`UUID`**, not `NSUUID`.
3. `AudioDeviceDestroyIOProcID` second arg is a **non-optional** `AudioDeviceIOProcID` — unwrap the optional returned by `AudioDeviceCreateIOProcIDWithBlock` first.
- `.muteBehavior = .mutedWhenTapped`, `nil` dispatch queue, the `Float**`/`UnsafeMutablePointer<Float>` array marshaling for `vDSP_biquadm`, and all key/selector spellings compiled correctly on the first structured attempt.
