import CoreAudio
import Foundation

/// "blue" for printable four-char codes, "0x…" hex otherwise.
func fourCCString(_ code: UInt32) -> String {
    let bytes = [UInt8((code >> 24) & 0xFF),
                 UInt8((code >> 16) & 0xFF),
                 UInt8((code >> 8) & 0xFF),
                 UInt8(code & 0xFF)]
    if bytes.allSatisfy({ (0x20...0x7E).contains($0) }),
       let text = String(bytes: bytes, encoding: .ascii) {
        return text
    }
    return String(format: "0x%08X", code)
}

enum CoreAudioError: LocalizedError {
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status, let what):
            return "\(what) failed (OSStatus \(status) [\(fourCCString(UInt32(bitPattern: status)))])"
        }
    }
}

extension AudioObjectPropertyAddress {
    init(_ selector: AudioObjectPropertySelector,
         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

/// Removes a property listener when cancelled (or deinited).
final class ListenerToken {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit { cancel() }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool { self != AudioObjectID(kAudioObjectUnknown) }

    // MARK: Reads

    func readUInt32(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> UInt32 {
        var value: UInt32 = 0
        try read(selector, scope: scope, element: element, into: &value)
        return value
    }

    func readObjectID(_ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> AudioObjectID {
        var value: AudioObjectID = .unknown
        try read(selector, scope: scope, element: element, into: &value)
        return value
    }

    func readFloat32(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> Float32 {
        var value: Float32 = 0
        try read(selector, scope: scope, element: element, into: &value)
        return value
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "read CFString \(fourCCString(selector))")
        }
        guard let value else {
            throw CoreAudioError.osStatus(OSStatus(kAudioHardwareBadObjectError),
                                          "read CFString \(fourCCString(selector)): null result")
        }
        return value.takeRetainedValue() as String
    }

    func readObjectIDList(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw CoreAudioError.osStatus(sizeStatus, "size of \(fourCCString(selector))")
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var list = [AudioObjectID](repeating: .unknown, count: count)
        let status = list.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return OSStatus(kAudioHardwareBadObjectError) }
            return AudioObjectGetPropertyData(self, &address, 0, nil, &size, base)
        }
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "read list \(fourCCString(selector))")
        }
        // The HAL may return fewer entries than the earlier size query promised.
        let returned = Int(size) / MemoryLayout<AudioObjectID>.size
        return returned < count ? Array(list.prefix(returned)) : list
    }

    /// Read a fixed-size POD value.
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 into value: inout T) throws {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "read \(fourCCString(selector))")
        }
    }

    // MARK: Writes

    func write<T>(_ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                  value: T) throws {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafePointer(to: value) { ptr in
            AudioObjectSetPropertyData(self, &address, 0, nil, size, ptr)
        }
        guard status == noErr else {
            throw CoreAudioError.osStatus(status, "write \(fourCCString(selector))")
        }
    }

    // MARK: Introspection

    func hasProperty(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        return AudioObjectHasProperty(self, &address)
    }

    func isPropertySettable(_ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(self, &address, &settable)
        return status == noErr && settable.boolValue
    }

    // MARK: Listeners

    /// Watch a property; `handler` is invoked on `queue` whenever it changes.
    func watch(_ selector: AudioObjectPropertySelector,
               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
               queue: DispatchQueue = .main,
               handler: @escaping () -> Void) -> ListenerToken {
        var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(self, &address, queue, block)
        guard status == noErr else {
            return ListenerToken(onCancel: {})
        }
        let object = self
        return ListenerToken {
            var address = AudioObjectPropertyAddress(selector, scope: scope, element: element)
            _ = AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
    }
}

// MARK: - Device conveniences shared by AudioDeviceManager and Probe

extension AudioObjectID {
    /// Total channel count of the device's stream configuration in `scope`.
    func channelCount(scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(self, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Elements carrying `selector` in `scope`: the main element when present, else channels 1 & 2.
    func controlElements(for selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        if hasProperty(selector, scope: scope) {
            return [kAudioObjectPropertyElementMain]
        }
        let channels: [AudioObjectPropertyElement] = [1, 2]
        return channels.filter { hasProperty(selector, scope: scope, element: $0) }
    }

    /// Volume scalar averaged over available elements; nil when the device exposes no volume control.
    func volumeScalar(scope: AudioObjectPropertyScope) -> Float? {
        let values = controlElements(for: kAudioDevicePropertyVolumeScalar, scope: scope)
            .compactMap { try? readFloat32(kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    /// Mute state over available elements; nil when the device exposes no mute control.
    func muteState(scope: AudioObjectPropertyScope) -> Bool? {
        let values = controlElements(for: kAudioDevicePropertyMute, scope: scope)
            .compactMap { try? readUInt32(kAudioDevicePropertyMute, scope: scope, element: $0) }
        guard !values.isEmpty else { return nil }
        return values.contains { $0 != 0 }
    }
}
