import AppKit
import CoreAudio
import Darwin
import Foundation

// Watches CoreAudio's process object list and each object's IsRunningOutput flag,
// folds helper processes into their responsible app, and publishes the visible app list:
// apps playing now, apps heard within `recentWindow`, and configured apps (keepAliveKeys)
// while their process still exists. Fully listener-driven — no polling.

@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []

    /// Config keys AudioController wants kept visible even when silent (apps with saved configs).
    var keepAliveKeys: Set<String> = []

    /// Seconds an app stays listed after it stops playing.
    var recentWindow: TimeInterval = 300

    /// Fired (on main) after `apps` changes — AudioController reconciles engines here.
    var onChange: (() -> Void)?

    private var listToken: ListenerToken?
    private var outputTokens: [AudioObjectID: ListenerToken] = [:]
    private var lastHeard: [String: Date] = [:]
    private var previouslyPlaying: Set<String> = []
    private var expiryCheck: DispatchWorkItem?

    private typealias ResponsibleForPID = @convention(c) (pid_t) -> pid_t
    // Private libsystem symbol; resolves on current macOS but treated as optional.
    private static let responsibleForPID: ResponsibleForPID? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsibleForPID.self)
    }()

    func start() {
        guard listToken == nil else { return }
        listToken = AudioObjectID.system.watch(kAudioHardwarePropertyProcessObjectList) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let objects = (try? AudioObjectID.system.readObjectIDList(kAudioHardwarePropertyProcessObjectList)) ?? []
        syncOutputListeners(objects)

        struct ProcessEntry {
            let objectID: AudioObjectID
            let pid: pid_t
            let bundleID: String?
            let isRunningOutput: Bool
        }

        var entries: [ProcessEntry] = []
        entries.reserveCapacity(objects.count)
        for object in objects {
            var pid: pid_t = -1
            do {
                try object.read(kAudioProcessPropertyPID, into: &pid)
            } catch {
                continue // object vanished mid-enumeration
            }
            guard pid > 0 else { continue }
            let rawBundleID = try? object.readString(kAudioProcessPropertyBundleID)
            let isRunningOutput = ((try? object.readUInt32(kAudioProcessPropertyIsRunningOutput)) ?? 0) != 0
            entries.append(ProcessEntry(
                objectID: object,
                pid: pid,
                bundleID: rawBundleID.flatMap { $0.isEmpty ? nil : $0 },
                isRunningOutput: isRunningOutput
            ))
        }

        let ownPids: Set<pid_t> = [getpid(), ProcessInfo.processInfo.processIdentifier]
        var groups: [pid_t: [ProcessEntry]] = [:]
        for entry in entries {
            var responsible = Self.responsibleForPID?(entry.pid) ?? entry.pid
            if responsible <= 0 { responsible = entry.pid }
            guard !ownPids.contains(entry.pid), !ownPids.contains(responsible) else { continue }
            groups[responsible, default: []].append(entry)
        }

        var candidates: [AudioApp] = []
        candidates.reserveCapacity(groups.count)
        for (responsiblePid, members) in groups {
            let running = NSRunningApplication(processIdentifier: responsiblePid)
            let bundleID = running?.bundleIdentifier ?? members.compactMap(\.bundleID).first
            candidates.append(AudioApp(
                id: responsiblePid,
                bundleID: bundleID,
                name: Self.displayName(pid: responsiblePid, running: running, bundleID: bundleID),
                objectIDs: members.map(\.objectID).sorted(),
                isPlaying: members.contains { $0.isRunningOutput }
            ))
        }

        let now = Date()
        let playingKeys = Set(candidates.lazy.filter(\.isPlaying).map(\.configKey))
        for app in candidates where app.isPlaying || previouslyPlaying.contains(app.configKey) {
            // The previouslyPlaying case timestamps the moment we observe a stop,
            // so long-playing apps do not expire the instant they go silent.
            lastHeard[app.configKey] = now
        }
        previouslyPlaying = playingKeys
        lastHeard = lastHeard.filter { now.timeIntervalSince($0.value) <= recentWindow }

        var visible = candidates.filter { app in
            app.isPlaying || lastHeard[app.configKey] != nil || keepAliveKeys.contains(app.configKey)
        }

        func bucket(_ app: AudioApp) -> Int {
            if app.isPlaying { return 0 }
            if lastHeard[app.configKey] != nil { return 1 }
            return 2 // configured (keepAlive), currently silent
        }
        visible.sort { a, b in
            let (ba, bb) = (bucket(a), bucket(b))
            if ba != bb { return ba < bb }
            let order = a.name.localizedCaseInsensitiveCompare(b.name)
            if order != .orderedSame { return order == .orderedAscending }
            return a.configKey < b.configKey
        }

        if visible != apps {
            apps = visible
            onChange?()
        }
        scheduleExpiryCheck(now: now)
    }

    // MARK: - Internals

    private func syncOutputListeners(_ objects: [AudioObjectID]) {
        let current = Set(objects)
        for (id, token) in outputTokens where !current.contains(id) {
            token.cancel()
            outputTokens.removeValue(forKey: id)
        }
        for id in current where outputTokens[id] == nil {
            outputTokens[id] = id.watch(kAudioProcessPropertyIsRunningOutput) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Recent-window expiry is the one state change with no CoreAudio event:
    /// arm a single one-shot check for the earliest deadline among recent-only apps.
    private func scheduleExpiryCheck(now: Date) {
        expiryCheck?.cancel()
        expiryCheck = nil
        let deadlines: [Date] = apps.compactMap { app in
            guard !app.isPlaying,
                  !keepAliveKeys.contains(app.configKey),
                  let heard = lastHeard[app.configKey] else { return nil }
            return heard.addingTimeInterval(recentWindow)
        }
        guard let next = deadlines.min() else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        expiryCheck = item
        let delay = max(next.timeIntervalSince(now), 0) + 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private nonisolated static func displayName(pid: pid_t,
                                                running: NSRunningApplication?,
                                                bundleID: String?) -> String {
        if let name = running?.localizedName, !name.isEmpty { return name }
        if let bundleID, let tail = bundleID.split(separator: ".").last, !tail.isEmpty {
            return String(tail)
        }
        var buffer = [CChar](repeating: 0, count: 128)
        if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 {
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            if !bytes.isEmpty { return String(decoding: bytes, as: UTF8.self) }
        }
        return "PID \(pid)"
    }
}
