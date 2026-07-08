import CoreAudio
import Foundation

/// Headless diagnostics mode (`Auricle --probe`): dumps devices, defaults and audio
/// process objects as JSON. Creates no taps or aggregates, so no TCC prompt.
enum Probe {
    private struct DeviceReport: Codable {
        let id: AudioObjectID
        let uid: String
        let name: String
        let transport: String
        let hasInput: Bool
        let hasOutput: Bool
        let volume: Float?
    }

    private struct DefaultDeviceReport: Codable {
        let id: AudioObjectID
        let uid: String?
        let name: String?
    }

    private struct ProcessReport: Codable {
        let pid: Int32
        let bundleID: String?
        let isRunningOutput: Bool
    }

    private struct Report: Codable {
        let devices: [DeviceReport]
        let defaultOutput: DefaultDeviceReport?
        let defaultInput: DefaultDeviceReport?
        let processes: [ProcessReport]
    }

    static func run() {
        let report = Report(devices: listDevices(),
                            defaultOutput: describeDefault(kAudioHardwarePropertyDefaultOutputDevice),
                            defaultInput: describeDefault(kAudioHardwarePropertyDefaultInputDevice),
                            processes: listProcesses())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report), let json = String(data: data, encoding: .utf8) {
            print(json)
        } else {
            print(#"{"error": "failed to encode probe report"}"#)
        }
        exit(0)
    }

    private static func listDevices() -> [DeviceReport] {
        let ids = (try? AudioObjectID.system.readObjectIDList(kAudioHardwarePropertyDevices)) ?? []
        return ids.compactMap { id in
            guard let uid = try? id.readString(kAudioDevicePropertyDeviceUID) else { return nil }
            let transport = (try? id.readUInt32(kAudioDevicePropertyTransportType)) ?? 0
            let hasOutput = id.channelCount(scope: kAudioDevicePropertyScopeOutput) > 0
            let hasInput = id.channelCount(scope: kAudioDevicePropertyScopeInput) > 0
            let scope = hasOutput ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
            return DeviceReport(id: id,
                                uid: uid,
                                name: (try? id.readString(kAudioObjectPropertyName)) ?? uid,
                                transport: fourCCString(transport),
                                hasInput: hasInput,
                                hasOutput: hasOutput,
                                volume: id.volumeScalar(scope: scope))
        }
    }

    private static func describeDefault(_ selector: AudioObjectPropertySelector) -> DefaultDeviceReport? {
        guard let id = try? AudioObjectID.system.readObjectID(selector), id.isValid else { return nil }
        return DefaultDeviceReport(id: id,
                                   uid: try? id.readString(kAudioDevicePropertyDeviceUID),
                                   name: try? id.readString(kAudioObjectPropertyName))
    }

    private static func listProcesses() -> [ProcessReport] {
        let objects = (try? AudioObjectID.system.readObjectIDList(kAudioHardwarePropertyProcessObjectList)) ?? []
        return objects.compactMap { object in
            var pid: pid_t = 0
            do {
                try object.read(kAudioProcessPropertyPID, into: &pid)
            } catch {
                return nil
            }
            let running = (try? object.readUInt32(kAudioProcessPropertyIsRunningOutput)) ?? 0
            return ProcessReport(pid: pid,
                                 bundleID: try? object.readString(kAudioProcessPropertyBundleID),
                                 isRunningOutput: running != 0)
        }
    }
}
