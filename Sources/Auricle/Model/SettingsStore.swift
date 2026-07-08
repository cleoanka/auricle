import Foundation

struct PersistedState: Codable {
    var appConfigs: [String: AppAudioConfig] = [:]
    var masterConfig = AppAudioConfig()
    var rememberConfigs = true
    var customPresets: [EQPreset] = []
}

// All mutable state is confined to `queue`, hence the unchecked Sendable.
final class SettingsStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.cleoanka.Auricle.settings")
    private var pending: PersistedState?
    private var scheduledWrite: DispatchWorkItem?

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Auricle", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }()

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save(_ state: PersistedState) {
        queue.async {
            self.pending = state
            self.scheduledWrite?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.writePending() }
            self.scheduledWrite = item
            self.queue.asyncAfter(deadline: .now() + 1, execute: item)
        }
    }

    /// Synchronously writes any pending state; safe to call from any thread except `queue` itself.
    func flush() {
        queue.sync { self.writePending() }
    }

    deinit {
        queue.sync { self.writePending() }
    }

    private func writePending() {
        scheduledWrite?.cancel()
        scheduledWrite = nil
        guard let state = pending else { return }
        pending = nil
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; never take the app down over settings I/O.
        }
    }
}
