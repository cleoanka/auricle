import AppKit
import Foundation

// AGENT-TODO(proc): implement the engine-reconciliation + persistence logic marked below.
// This class is the single coordination point:
// - owns AudioDeviceManager, AudioProcessMonitor, SettingsStore and all ProcessTapEngine instances
// - decides when an app needs an engine (config.needsEngine) and when the master chain does
//   (masterConfig.needsMasterEngine), creates/updates/tears them down
// - retargets engines when the default output device changes (engines whose config has
//   outputDeviceUID == nil follow the default; master always follows the default)
// - handles engine failures: "permission:" messages set permissionIssue, others land in engineErrors
// - persists state (debounced via SettingsStore) whenever configs/presets/settings change
// - when rememberConfigs is true, saved configs auto-apply as soon as their app appears

@MainActor
final class AudioController: ObservableObject {
    let devices = AudioDeviceManager()
    let processes = AudioProcessMonitor()
    private let store = SettingsStore()

    @Published private(set) var appConfigs: [String: AppAudioConfig] = [:]
    @Published private(set) var masterConfig = AppAudioConfig()
    @Published private(set) var customPresets: [EQPreset] = []
    /// True when a tap failed due to missing System Audio Recording permission.
    @Published private(set) var permissionIssue = false
    /// configKey -> human-readable engine error (non-permission failures).
    @Published private(set) var engineErrors: [String: String] = [:]
    @Published var rememberConfigs = true {
        didSet { persist() }
    }

    private var engines: [String: ProcessTapEngine] = [:]
    private var masterEngine: ProcessTapEngine?

    init() {
        let state = store.load()
        appConfigs = state.appConfigs
        masterConfig = state.masterConfig
        rememberConfigs = state.rememberConfigs
        customPresets = state.customPresets

        // AGENT-TODO(proc): wire callbacks BEFORE starting:
        // devices.onDefaultOutputChanged / onDeviceListChanged -> retarget & re-validate engines
        // processes.onChange -> reconcileEngines()
        // processes.keepAliveKeys = Set(appConfigs.keys)
        devices.start()
        processes.start()
        reconcileEngines()
    }

    // MARK: Per-app configs

    func config(for app: AudioApp) -> AppAudioConfig {
        appConfigs[app.configKey] ?? AppAudioConfig()
    }

    func setConfig(_ config: AppAudioConfig, for app: AudioApp) {
        appConfigs[app.configKey] = config
        // AGENT-TODO(proc): reconcile this app's engine (create/apply/stop), update keepAliveKeys, persist()
    }

    func resetConfig(for app: AudioApp) {
        appConfigs.removeValue(forKey: app.configKey)
        engineErrors.removeValue(forKey: app.configKey)
        // AGENT-TODO(proc): stop+remove engine, update keepAliveKeys, persist()
    }

    // MARK: Master chain

    func setMasterConfig(_ config: AppAudioConfig) {
        masterConfig = config
        // AGENT-TODO(proc): reconcile masterEngine, persist()
    }

    // MARK: Presets

    var allPresets: [EQPreset] { EQPreset.builtins + customPresets }

    func addCustomPreset(named name: String, from settings: EQSettings) {
        customPresets.append(EQPreset(name: name, gains: settings.gains, preampDB: settings.preampDB))
        persist()
    }

    func deleteCustomPreset(_ preset: EQPreset) {
        customPresets.removeAll { $0.id == preset.id }
        persist()
    }

    // MARK: UI helpers

    /// Whether a live engine is running for this app (meters available).
    func isManaged(_ app: AudioApp) -> Bool {
        engines[app.configKey] != nil
    }

    func levels(for app: AudioApp) -> (left: Float, right: Float)? {
        engines[app.configKey]?.currentLevels
    }

    var masterLevels: (left: Float, right: Float)? {
        masterEngine?.currentLevels
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Internals

    private func reconcileEngines() {
        // AGENT-TODO(proc): diff processes.apps x appConfigs against `engines`:
        // - config.needsEngine && app present -> ensure engine exists, engine.apply(config, targetDeviceUID)
        // - app gained/lost helper process objects -> engine.updateSource(objectIDs:)
        // - config gone or app gone -> engine.stop(), remove
        // - master: masterConfig.needsMasterEngine -> ensure masterEngine (source: .systemWide,
        //   target nil = default), else stop it
        // - wire onFailure of every engine (permission: -> permissionIssue = true)
    }

    private func persist() {
        store.save(PersistedState(
            appConfigs: appConfigs,
            masterConfig: masterConfig,
            rememberConfigs: rememberConfigs,
            customPresets: customPresets
        ))
    }
}
