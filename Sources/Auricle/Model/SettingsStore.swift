import Foundation

// AGENT-TODO(proc): implement persistence.
// Location: ~/Library/Application Support/Auricle/settings.json (create directory as needed).
// save() must debounce (~1s) on an internal serial queue; write atomically.
// load() tolerates missing/corrupt files by returning the default state (never crash on bad JSON).

struct PersistedState: Codable {
    var appConfigs: [String: AppAudioConfig] = [:]
    var masterConfig = AppAudioConfig()
    var rememberConfigs = true
    var customPresets: [EQPreset] = []
}

final class SettingsStore {
    func load() -> PersistedState {
        PersistedState() // AGENT-TODO(proc)
    }

    func save(_ state: PersistedState) {
        // AGENT-TODO(proc)
    }
}
