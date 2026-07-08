import CoreAudio
import Foundation

// AGENT-TODO(dsp): implement this class fully. This is the heart of Auricle.
//
// Architecture (per engine instance):
//   CATapDescription (muteBehavior = .mutedWhenTapped)
//     -> AudioHardwareCreateProcessTap
//     -> private aggregate device (kAudioAggregateDeviceIsPrivateKey: true,
//        UID prefixed AudioDeviceManager.auricleAggregatePrefix, sub-device = target output device,
//        tap in kAudioAggregateDeviceTapListKey with drift compensation, TapAutoStart true)
//     -> AudioDeviceCreateIOProcIDWithBlock(nil queue) on the aggregate:
//        input buffers = tapped app audio; process gain ramp (vDSP_vrampmul-style) + GraphicEQ
//        + soft clip to [-1, 1]; write into the aggregate's OUTPUT buffers (channels 0/1, zero the rest);
//        update RMS level atomics for the UI meters.
//
// systemWide mode feedback-avoidance sequence (REQUIRED ORDER):
//   1. create aggregate on the target device with an EMPTY tap list, start the IOProc (outputs silence)
//   2. translate getpid() via kAudioHardwarePropertyTranslatePIDToProcessObject (retry briefly if unknown)
//   3. create CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObject]), create the tap
//   4. attach it via the aggregate's kAudioAggregateDevicePropertyTapList property
// Otherwise Auricle's own replay output would be re-captured -> feedback loop.
//
// Control plane: one private serial DispatchQueue per engine; apply()/stop() enqueue async work and
// never block the main thread. Errors surface via onFailure (dispatched to main). Detect the
// TCC-denied case and prefix the message with "permission:" so AudioController can show the banner.
//
// Teardown order: AudioDeviceStop -> AudioDeviceDestroyIOProcID -> AudioHardwareDestroyAggregateDevice
// -> AudioHardwareDestroyProcessTap. Also listen for target-device death and aggregate sample-rate
// changes (rebuild EQ at the new rate).
//
// Realtime rules inside the IO block: no allocation, no ObjC, no logging, no locks except a single
// os_unfair_lock "try" for parameter snapshots (fall back to last snapshot on contention).

final class ProcessTapEngine {
    enum Source {
        /// Tap a set of process objects belonging to one app.
        case app(objectIDs: [AudioObjectID])
        /// Tap everything except Auricle itself (master chain).
        case systemWide
    }

    let source: Source

    /// Called on the main queue when the engine fails. Messages starting with "permission:"
    /// indicate missing System Audio Recording consent.
    var onFailure: ((String) -> Void)?

    private(set) var isRunning: Bool = false

    init(source: Source) {
        self.source = source
    }

    /// Start / reconfigure / retarget as needed. Diffs internally:
    /// cheap path for gain/EQ/mute changes, full rebuild for device changes.
    /// `targetDeviceUID` nil = follow the current system default output device.
    func apply(config: AppAudioConfig, targetDeviceUID: String?) {
        // AGENT-TODO(dsp)
    }

    /// Update the set of tapped process objects (app gained/lost helper processes).
    func updateSource(objectIDs: [AudioObjectID]) {
        // AGENT-TODO(dsp)
    }

    func stop() {
        // AGENT-TODO(dsp)
    }

    /// Thread-safe RMS levels (0...1) for UI meters.
    var currentLevels: (left: Float, right: Float) {
        (0, 0) // AGENT-TODO(dsp)
    }
}
