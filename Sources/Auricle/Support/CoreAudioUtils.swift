import CoreAudio
import Foundation

// AGENT-TODO(core): implement all of this file. Keep the public surface below intact —
// other modules compile against it.

enum CoreAudioError: LocalizedError {
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status, let what):
            return "\(what) failed (OSStatus \(status))"
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

    // MARK: Reads (AGENT-TODO(core): implement)

    func readUInt32(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> UInt32 {
        throw CoreAudioError.osStatus(-1, "readUInt32 not implemented")
    }

    func readObjectID(_ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> AudioObjectID {
        throw CoreAudioError.osStatus(-1, "readObjectID not implemented")
    }

    func readFloat32(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> Float32 {
        throw CoreAudioError.osStatus(-1, "readFloat32 not implemented")
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        throw CoreAudioError.osStatus(-1, "readString not implemented")
    }

    func readObjectIDList(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> [AudioObjectID] {
        throw CoreAudioError.osStatus(-1, "readObjectIDList not implemented")
    }

    /// Read a fixed-size POD value.
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 into value: inout T) throws {
        throw CoreAudioError.osStatus(-1, "read(into:) not implemented")
    }

    // MARK: Writes (AGENT-TODO(core): implement)

    func write<T>(_ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                  value: T) throws {
        throw CoreAudioError.osStatus(-1, "write not implemented")
    }

    // MARK: Introspection (AGENT-TODO(core): implement)

    func hasProperty(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        false
    }

    func isPropertySettable(_ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        false
    }

    // MARK: Listeners (AGENT-TODO(core): implement)

    /// Watch a property; `handler` is invoked on `queue` whenever it changes.
    func watch(_ selector: AudioObjectPropertySelector,
               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
               queue: DispatchQueue = .main,
               handler: @escaping () -> Void) -> ListenerToken {
        ListenerToken(onCancel: {})
    }
}
