import AppKit
import CoreAudio
import Foundation

// Single coordination point: owns the device manager, process monitor, settings store and
// every ProcessTapEngine. Reconciles engines against configs whenever apps/devices change,
// persists state (debounced by SettingsStore), and surfaces engine failures.

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
    /// Last object-ID set handed to each engine, to detect helper processes coming/going.
    private var engineObjectIDs: [String: [AudioObjectID]] = [:]
    private var terminateObserver: NSObjectProtocol?

    /// engineErrors key for the master chain — deliberately not a plausible configKey.
    private static let masterErrorKey = "__auricle.master__"

    init() {
        let state = store.load()
        // rememberConfigs == false means saved per-app configs are neither kept nor auto-applied.
        appConfigs = state.rememberConfigs ? state.appConfigs : [:]
        masterConfig = state.masterConfig
        rememberConfigs = state.rememberConfigs
        customPresets = state.customPresets

        devices.onDefaultOutputChanged = { [weak self] in
            self?.defaultOutputChanged()
        }
        devices.onDeviceListChanged = { [weak self] in
            self?.deviceListChanged()
        }
        processes.onChange = { [weak self] in
            self?.reconcileEngines()
        }
        processes.keepAliveKeys = Set(appConfigs.keys)

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [store] _ in
            store.flush()
        }

        devices.start()
        processes.start()
        reconcileEngines()
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    // MARK: Per-app configs

    func config(for app: AudioApp) -> AppAudioConfig {
        appConfigs[app.configKey] ?? AppAudioConfig()
    }

    func setConfig(_ config: AppAudioConfig, for app: AudioApp) {
        let key = app.configKey
        // Any config change is a fresh attempt: clear stale failure state.
        permissionIssue = false
        engineErrors.removeValue(forKey: key)

        if config == AppAudioConfig() {
            appConfigs.removeValue(forKey: key)
        } else {
            appConfigs[key] = config
        }
        processes.keepAliveKeys = Set(appConfigs.keys)

        if config.needsEngine {
            if let engine = engines[key] {
                if engineObjectIDs[key] != app.objectIDs {
                    engineObjectIDs[key] = app.objectIDs
                    engine.updateSource(objectIDs: app.objectIDs)
                }
                engine.apply(config: config, targetDeviceUID: config.outputDeviceUID)
            } else {
                startEngine(for: app, config: config)
            }
        } else {
            removeEngine(forKey: key)
        }
        persist()
    }

    func resetConfig(for app: AudioApp) {
        appConfigs.removeValue(forKey: app.configKey)
        engineErrors.removeValue(forKey: app.configKey)
        permissionIssue = false
        removeEngine(forKey: app.configKey)
        processes.keepAliveKeys = Set(appConfigs.keys)
        persist()
    }

    // MARK: Master chain

    func setMasterConfig(_ config: AppAudioConfig) {
        masterConfig = config
        permissionIssue = false
        engineErrors.removeValue(forKey: Self.masterErrorKey)
        reconcileMasterEngine()
        persist()
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
        let appsByKey = Dictionary(processes.apps.map { ($0.configKey, $0) }) { first, _ in first }

        for (key, engine) in engines {
            let stillNeeded = appConfigs[key]?.needsEngine == true && appsByKey[key] != nil
            if !stillNeeded {
                engine.stop()
                engines.removeValue(forKey: key)
                engineObjectIDs.removeValue(forKey: key)
            }
        }

        for (key, config) in appConfigs where config.needsEngine {
            guard let app = appsByKey[key] else { continue }
            if let engine = engines[key] {
                if engineObjectIDs[key] != app.objectIDs {
                    engineObjectIDs[key] = app.objectIDs
                    engine.updateSource(objectIDs: app.objectIDs)
                }
            } else if !permissionIssue, engineErrors[key] == nil {
                startEngine(for: app, config: config)
            }
        }

        reconcileMasterEngine()
    }

    private func reconcileMasterEngine() {
        if masterConfig.needsMasterEngine {
            if masterEngine == nil {
                guard !permissionIssue, engineErrors[Self.masterErrorKey] == nil else { return }
                let engine = ProcessTapEngine(source: .systemWide)
                attachFailureHandler(engine, key: Self.masterErrorKey)
                masterEngine = engine
            }
            // Master always follows the system default output device.
            masterEngine?.apply(config: masterConfig, targetDeviceUID: nil)
        } else if let engine = masterEngine {
            engine.stop()
            masterEngine = nil
        }
    }

    private func startEngine(for app: AudioApp, config: AppAudioConfig) {
        let key = app.configKey
        let engine = ProcessTapEngine(source: .app(objectIDs: app.objectIDs))
        attachFailureHandler(engine, key: key)
        engines[key] = engine
        engineObjectIDs[key] = app.objectIDs
        engine.apply(config: config, targetDeviceUID: config.outputDeviceUID)
    }

    private func removeEngine(forKey key: String) {
        if let engine = engines.removeValue(forKey: key) {
            engine.stop()
        }
        engineObjectIDs.removeValue(forKey: key)
    }

    private func attachFailureHandler(_ engine: ProcessTapEngine, key: String) {
        // Engines invoke onFailure on the main queue.
        engine.onFailure = { [weak self] message in
            self?.handleEngineFailure(key: key, message: message)
        }
    }

    private func handleEngineFailure(key: String, message: String) {
        if message.hasPrefix("permission:") {
            permissionIssue = true
        } else {
            engineErrors[key] = message
        }
        // Drop the failed engine; the failure record gates recreation until a config change.
        if key == Self.masterErrorKey {
            masterEngine?.stop()
            masterEngine = nil
        } else {
            removeEngine(forKey: key)
        }
    }

    private func defaultOutputChanged() {
        for (key, engine) in engines {
            guard let config = appConfigs[key], config.outputDeviceUID == nil else { continue }
            engine.apply(config: config, targetDeviceUID: nil)
        }
        if let masterEngine {
            masterEngine.apply(config: masterConfig, targetDeviceUID: nil)
        }
    }

    private func deviceListChanged() {
        // Routed engines re-resolve their UID: a vanished device falls back to the default
        // (routing is kept), a returning device is picked up again. Never surfaced as an error.
        for (key, engine) in engines {
            guard let config = appConfigs[key], let uid = config.outputDeviceUID else { continue }
            engine.apply(config: config, targetDeviceUID: uid)
        }
    }

    private func persist() {
        store.save(PersistedState(
            appConfigs: rememberConfigs ? appConfigs : [:],
            masterConfig: masterConfig,
            rememberConfigs: rememberConfigs,
            customPresets: customPresets
        ))
    }
}
