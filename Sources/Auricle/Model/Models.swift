import AppKit
import CoreAudio
import Foundation

enum AppInfo {
    static let name = "Auricle"
    static let version = "0.2.1"
    static let bundleID = "io.github.cleoanka.Auricle"
    static let repoURL = URL(string: "https://github.com/cleoanka/auricle")!
}

// MARK: - Devices

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportType: UInt32
    let hasOutput: Bool
    let hasInput: Bool
}

extension AudioDevice {
    /// SF Symbol representing the device's transport type.
    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplay.audio"
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "hifispeaker"
        }
    }
}

// MARK: - Apps

struct AudioApp: Identifiable, Hashable {
    /// Responsible (top-level) pid — helper processes are folded into their parent app.
    let id: pid_t
    let bundleID: String?
    let name: String
    /// CoreAudio process objects belonging to this app (may be several helpers).
    let objectIDs: [AudioObjectID]
    /// True when any of the process objects is currently running output.
    let isPlaying: Bool

    /// Stable key used for config persistence.
    var configKey: String { bundleID ?? name }
}

extension AudioApp {
    var icon: NSImage? { NSRunningApplication(processIdentifier: id)?.icon }
}

// MARK: - EQ

struct EQSettings: Codable, Equatable {
    var enabled: Bool = false
    /// Per-band gain in dB, range -12...+12. Always exactly `GraphicEQ.bandCount` entries.
    var gains: [Float] = Array(repeating: 0, count: 10)
    /// Pre-EQ gain in dB, range -12...+12.
    var preampDB: Float = 0

    static let bandFrequencies: [Double] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static func bandLabel(_ index: Int) -> String {
        let f = bandFrequencies[index]
        return f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    var isFlat: Bool { gains.allSatisfy { $0 == 0 } && preampDB == 0 }
}

// Tolerant decoding: a key missing from settings.json (e.g. a field added in a later
// version) falls back to its default instead of failing the whole file, which
// SettingsStore would otherwise replace with defaults and overwrite on the next save.
extension EQSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = EQSettings()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        gains = try container.decodeIfPresent([Float].self, forKey: .gains) ?? defaults.gains
        preampDB = try container.decodeIfPresent(Float.self, forKey: .preampDB) ?? defaults.preampDB
    }
}

// MARK: - Per-app / master configuration

struct AppAudioConfig: Codable, Equatable {
    /// 0...1. (Ignored for the master chain — the device volume covers it.)
    var volume: Float = 1.0
    /// Extra gain in dB, 0...+12.
    var boostDB: Float = 0
    var isMuted: Bool = false
    var eq = EQSettings()
    /// nil = follow the system default output device.
    var outputDeviceUID: String? = nil

    /// Whether this config requires a live tap engine.
    var needsEngine: Bool {
        volume != 1 || boostDB != 0 || isMuted || eq.enabled || outputDeviceUID != nil
    }

    /// Master-chain variant: volume/mute/routing are handled by the device itself.
    var needsMasterEngine: Bool {
        boostDB != 0 || eq.enabled
    }
}

extension AppAudioConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppAudioConfig()
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? defaults.volume
        boostDB = try container.decodeIfPresent(Float.self, forKey: .boostDB) ?? defaults.boostDB
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? defaults.isMuted
        eq = try container.decodeIfPresent(EQSettings.self, forKey: .eq) ?? defaults.eq
        outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
    }
}

// MARK: - Presets

struct EQPreset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var gains: [Float]
    var preampDB: Float = 0
    var isBuiltin: Bool = false

    static let builtins: [EQPreset] = [
        EQPreset(name: "Flat", gains: Array(repeating: 0, count: 10), isBuiltin: true),
        EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0], isBuiltin: true),
        EQPreset(name: "Bass Reducer", gains: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0], isBuiltin: true),
        EQPreset(name: "Vocal", gains: [-2, -3, -3, 1, 4, 4, 3, 1.5, 0, -1.5], isBuiltin: true),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6], isBuiltin: true),
        EQPreset(name: "Loudness", gains: [6, 4, 0, 0, -2, 0, -1, -5, 5, 1], isBuiltin: true),
        EQPreset(name: "Electronic", gains: [4, 3.5, 1, 0, -2, 2, 0.5, 1, 4, 4.5], isBuiltin: true),
        EQPreset(name: "Rock", gains: [5, 4, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 4.5], isBuiltin: true),
        EQPreset(name: "Podcast", gains: [-3, -2, 0, 2, 4, 4, 3, 1, 0, -1], isBuiltin: true),
    ]
}

extension EQPreset {
    /// `name` and `gains` stay required: a preset without them is not meaningful.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        gains = try container.decode([Float].self, forKey: .gains)
        preampDB = try container.decodeIfPresent(Float.self, forKey: .preampDB) ?? 0
        isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
    }
}
