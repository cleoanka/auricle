import CoreAudio
import Foundation

// AGENT-TODO(core): implement this class fully.
// - Enumerate devices (kAudioHardwarePropertyDevices), classify input/output by stream/channel counts.
// - Track default output/input (kAudioHardwarePropertyDefaultOutputDevice / DefaultInputDevice) with listeners.
// - Track per-device volume & mute (kAudioDevicePropertyVolumeScalar / kAudioDevicePropertyMute on the
//   output/input scope; try main element first, fall back to channels 1&2 averaged) with listeners.
// - Exclude private aggregates Auricle itself creates (their UID contains AudioDeviceManager.auricleAggregatePrefix).
// - All @Published mutations on the main actor; CoreAudio listeners must hop to main.

@MainActor
final class AudioDeviceManager: ObservableObject {
    /// UID prefix for Auricle-private aggregate devices, so they can be filtered out of device lists.
    nonisolated static let auricleAggregatePrefix = "io.github.cleoanka.Auricle.aggregate"

    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioObjectID = .unknown
    @Published private(set) var defaultInputID: AudioObjectID = .unknown
    /// Volume scalar (0...1) per device, kept fresh via listeners.
    @Published private(set) var volumes: [AudioObjectID: Float] = [:]
    @Published private(set) var mutes: Set<AudioObjectID> = []

    /// Hooks for AudioController (set before start()).
    var onDefaultOutputChanged: (() -> Void)?
    var onDeviceListChanged: (() -> Void)?

    var defaultOutput: AudioDevice? { outputDevices.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { inputDevices.first { $0.id == defaultInputID } }

    func start() {
        // AGENT-TODO(core)
    }

    func setDefaultOutput(_ device: AudioDevice) {
        // AGENT-TODO(core)
    }

    func setDefaultInput(_ device: AudioDevice) {
        // AGENT-TODO(core)
    }

    func setVolume(_ volume: Float, for device: AudioDevice) {
        // AGENT-TODO(core)
    }

    func setMuted(_ muted: Bool, for device: AudioDevice) {
        // AGENT-TODO(core)
    }

    func volume(for id: AudioObjectID) -> Float { volumes[id] ?? 0 }
    func isMuted(_ id: AudioObjectID) -> Bool { mutes.contains(id) }

    func device(forUID uid: String) -> AudioDevice? {
        outputDevices.first { $0.uid == uid } ?? inputDevices.first { $0.uid == uid }
    }
}
