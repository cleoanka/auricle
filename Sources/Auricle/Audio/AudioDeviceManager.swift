import CoreAudio
import Foundation
import os

/// Which side of a (possibly duplex) device a volume/mute control belongs to. AirPods and
/// USB interfaces are one device with independent controls per scope, so every control API
/// and cache is keyed by (device, scope) — never by device alone.
enum DeviceControlScope: Hashable {
    case output
    case input

    var propertyScope: AudioObjectPropertyScope {
        switch self {
        case .output: return kAudioDevicePropertyScopeOutput
        case .input: return kAudioDevicePropertyScopeInput
        }
    }
}

struct DeviceControlKey: Hashable {
    let id: AudioObjectID
    let scope: DeviceControlScope
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    /// UID prefix for Auricle-private aggregate devices, so they can be filtered out of device lists.
    nonisolated static let auricleAggregatePrefix = "io.github.cleoanka.Auricle.aggregate"

    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioObjectID = .unknown
    @Published private(set) var defaultInputID: AudioObjectID = .unknown
    /// Volume scalar (0...1) per device control, kept fresh via listeners.
    @Published private(set) var volumes: [DeviceControlKey: Float] = [:]
    @Published private(set) var mutes: Set<DeviceControlKey> = []

    /// Hooks for AudioController (set before start()).
    var onDefaultOutputChanged: (() -> Void)?
    var onDeviceListChanged: (() -> Void)?

    var defaultOutput: AudioDevice? { outputDevices.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { inputDevices.first { $0.id == defaultInputID } }

    private let log = Logger(subsystem: AppInfo.bundleID, category: "AudioDeviceManager")
    private var systemTokens: [ListenerToken] = []
    private var deviceTokens: [ListenerToken] = []

    func start() {
        refreshDeviceList()
        refreshDefaults(notify: false)

        systemTokens = [
            AudioObjectID.system.watch(kAudioHardwarePropertyDevices) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshDeviceList()
                    self.refreshDefaults(notify: true)
                    self.onDeviceListChanged?()
                }
            },
            AudioObjectID.system.watch(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshDefaults(notify: true)
                }
            },
            AudioObjectID.system.watch(kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshDefaults(notify: true)
                }
            },
        ]
    }

    func setDefaultOutput(_ device: AudioDevice) {
        do {
            try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, value: device.id)
        } catch {
            log.error("setDefaultOutput(\(device.name, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    func setDefaultInput(_ device: AudioDevice) {
        do {
            try AudioObjectID.system.write(kAudioHardwarePropertyDefaultInputDevice, value: device.id)
        } catch {
            log.error("setDefaultInput(\(device.name, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    func setVolume(_ volume: Float, for device: AudioDevice, scope: DeviceControlScope) {
        let clamped = min(max(volume, 0), 1)
        let propertyScope = scope.propertyScope
        var wrote = false
        for element in device.id.controlElements(for: kAudioDevicePropertyVolumeScalar, scope: propertyScope)
        where device.id.isPropertySettable(kAudioDevicePropertyVolumeScalar, scope: propertyScope, element: element) {
            do {
                try device.id.write(kAudioDevicePropertyVolumeScalar, scope: propertyScope,
                                    element: element, value: clamped)
                wrote = true
            } catch {
                log.error("setVolume(\(device.name, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
        if wrote {
            volumes[DeviceControlKey(id: device.id, scope: scope)] = clamped
        }
    }

    func setMuted(_ muted: Bool, for device: AudioDevice, scope: DeviceControlScope) {
        let propertyScope = scope.propertyScope
        var wrote = false
        for element in device.id.controlElements(for: kAudioDevicePropertyMute, scope: propertyScope)
        where device.id.isPropertySettable(kAudioDevicePropertyMute, scope: propertyScope, element: element) {
            do {
                try device.id.write(kAudioDevicePropertyMute, scope: propertyScope, element: element,
                                    value: UInt32(muted ? 1 : 0))
                wrote = true
            } catch {
                log.error("setMuted(\(device.name, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
        if wrote {
            let key = DeviceControlKey(id: device.id, scope: scope)
            if muted { mutes.insert(key) } else { mutes.remove(key) }
        }
    }

    func volume(for id: AudioObjectID, scope: DeviceControlScope) -> Float {
        volumes[DeviceControlKey(id: id, scope: scope)] ?? 0
    }

    func isMuted(_ id: AudioObjectID, scope: DeviceControlScope) -> Bool {
        mutes.contains(DeviceControlKey(id: id, scope: scope))
    }

    func device(forUID uid: String) -> AudioDevice? {
        outputDevices.first { $0.uid == uid } ?? inputDevices.first { $0.uid == uid }
    }

    // MARK: - Refresh

    private var allDevices: [AudioDevice] {
        var seen = Set<AudioObjectID>()
        return (outputDevices + inputDevices).filter { seen.insert($0.id).inserted }
    }

    private func refreshDeviceList() {
        let ids = (try? AudioObjectID.system.readObjectIDList(kAudioHardwarePropertyDevices)) ?? []
        var outputs: [AudioDevice] = []
        var inputs: [AudioDevice] = []
        for id in ids {
            guard let device = Self.describeDevice(id) else { continue }
            if device.hasOutput { outputs.append(device) }
            if device.hasInput { inputs.append(device) }
        }
        outputDevices = outputs
        inputDevices = inputs
        rebuildDeviceListeners()
        refreshVolumesAndMutes()
    }

    private func refreshDefaults(notify: Bool) {
        let newOutput = (try? AudioObjectID.system.readObjectID(kAudioHardwarePropertyDefaultOutputDevice)) ?? .unknown
        let newInput = (try? AudioObjectID.system.readObjectID(kAudioHardwarePropertyDefaultInputDevice)) ?? .unknown
        let outputChanged = newOutput != defaultOutputID
        if outputChanged { defaultOutputID = newOutput }
        if newInput != defaultInputID { defaultInputID = newInput }
        if notify && outputChanged {
            onDefaultOutputChanged?()
        }
    }

    /// coreaudiod restarted: device object IDs changed wholesale; re-read everything.
    func serviceRestarted() {
        refreshDeviceList()
        refreshDefaults(notify: true)
    }

    private func refreshVolumesAndMutes() {
        var newVolumes: [DeviceControlKey: Float] = [:]
        var newMutes: Set<DeviceControlKey> = []
        for device in allDevices {
            for scope in Self.controlScopes(of: device) {
                let key = DeviceControlKey(id: device.id, scope: scope)
                if let volume = device.id.volumeScalar(scope: scope.propertyScope) {
                    newVolumes[key] = volume
                }
                if device.id.muteState(scope: scope.propertyScope) == true {
                    newMutes.insert(key)
                }
            }
        }
        volumes = newVolumes
        mutes = newMutes
    }

    private func refreshControls(for id: AudioObjectID) {
        guard let device = allDevices.first(where: { $0.id == id }) else { return }
        for scope in Self.controlScopes(of: device) {
            let key = DeviceControlKey(id: id, scope: scope)
            if let volume = id.volumeScalar(scope: scope.propertyScope) {
                volumes[key] = volume
            } else {
                volumes.removeValue(forKey: key)
            }
            if id.muteState(scope: scope.propertyScope) == true {
                mutes.insert(key)
            } else {
                mutes.remove(key)
            }
        }
    }

    private func rebuildDeviceListeners() {
        for token in deviceTokens { token.cancel() }
        deviceTokens.removeAll()
        let selectors: [AudioObjectPropertySelector] = [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute]
        for device in allDevices {
            let id = device.id
            for scope in Self.controlScopes(of: device) {
                for selector in selectors {
                    for element in id.controlElements(for: selector, scope: scope.propertyScope) {
                        deviceTokens.append(id.watch(selector, scope: scope.propertyScope, element: element) { [weak self] in
                            MainActor.assumeIsolated {
                                self?.refreshControls(for: id)
                            }
                        })
                    }
                }
            }
        }
    }

    // MARK: - Classification

    private nonisolated static func controlScopes(of device: AudioDevice) -> [DeviceControlScope] {
        var scopes: [DeviceControlScope] = []
        if device.hasOutput { scopes.append(.output) }
        if device.hasInput { scopes.append(.input) }
        return scopes
    }

    private nonisolated static func describeDevice(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = try? id.readString(kAudioDevicePropertyDeviceUID) else { return nil }
        guard !uid.hasPrefix(auricleAggregatePrefix) else { return nil }
        let transport = (try? id.readUInt32(kAudioDevicePropertyTransportType)) ?? 0
        if transport == kAudioDeviceTransportTypeAggregate, id.isPrivateAggregate { return nil }
        let outputChannels = id.channelCount(scope: kAudioDevicePropertyScopeOutput)
        let inputChannels = id.channelCount(scope: kAudioDevicePropertyScopeInput)
        guard outputChannels > 0 || inputChannels > 0 else { return nil }
        let name = (try? id.readString(kAudioObjectPropertyName)) ?? uid
        return AudioDevice(id: id,
                           uid: uid,
                           name: name,
                           transportType: transport,
                           hasOutput: outputChannels > 0,
                           hasInput: inputChannels > 0)
    }
}

private extension AudioObjectID {
    var isPrivateAggregate: Bool {
        var address = AudioObjectPropertyAddress(kAudioAggregateDevicePropertyComposition)
        guard AudioObjectHasProperty(self, &address) else { return false }
        var value: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return false }
        let composition = value.takeRetainedValue() as NSDictionary
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }
}
