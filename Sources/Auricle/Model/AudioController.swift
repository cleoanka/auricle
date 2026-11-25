import AppKit
import Combine
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
    /// Object-ID set an engine had when it failed: a different set (app relaunched,
    /// helpers changed) is a fresh attempt, so the recorded error does not pin it forever.
    private var failedObjectIDs: [String: [AudioObjectID]] = [:]
    /// Output-device UIDs as of the last device-list event. Every chain build/teardown
    /// creates/destroys a private aggregate, which also fires the HAL device-list
    /// listener; only a change in the (aggregate-filtered) output list retries failed
    /// engines, so an engine that fails after creating its aggregate cannot re-trigger
    /// its own retry in a build/fail loop.
    private var knownOutputUIDs: Set<String> = []
    private var terminateObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var serviceRestartToken: ListenerToken?

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

        // Views observe only this controller; forward the nested objects' invalidations
        // so the app list, device lists, and volumes stay live while the popover is open.
        devices.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        processes.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        serviceRestartToken = AudioObjectID.system.watch(kAudioHardwarePropertyServiceRestarted) { [weak self] in
            MainActor.assumeIsolated { self?.serviceRestarted() }
        }

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [store] _ in
            store.flush()
        }

        devices.start()
        knownOutputUIDs = Set(devices.outputDevices.map(\.uid))
        processes.start()
        reconcileEngines()
        runPermissionProbe()
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
        // A config change is a fresh attempt for this app's engine. The global permission
        // flag is only cleared by an explicit retry, so slider drags while consent is
        // missing cannot spawn build/fail cycles or flicker the banner.
        clearEngineError(forKey: key)

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
            } else if !permissionIssue {
                startEngine(for: app, config: config)
            }
        } else {
            removeEngine(forKey: key)
        }
        updateMasterExclusions()
        persist()
    }

    func resetConfig(for app: AudioApp) {
        appConfigs.removeValue(forKey: app.configKey)
        clearEngineError(forKey: app.configKey)
        removeEngine(forKey: app.configKey)
        processes.keepAliveKeys = Set(appConfigs.keys)
        updateMasterExclusions()
        persist()
    }

    /// Explicit retry after the user granted System Audio Recording consent.
    func retryPermission() {
        guard permissionIssue else { return }
        runPermissionProbe()
    }

    /// Triggers the System Audio Recording consent prompt at launch (first run) instead of
    /// waiting for the first slider touch, and keeps `permissionIssue` truthful either way.
    private func runPermissionProbe() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let granted = ProcessTapEngine.permissionProbe()
            DispatchQueue.main.async {
                guard let self else { return }
                let hadIssue = self.permissionIssue
                self.permissionIssue = !granted
                if granted && hadIssue {
                    self.reconcileEngines()
                }
            }
        }
    }

    // MARK: Master chain

    func setMasterConfig(_ config: AppAudioConfig) {
        masterConfig = config
        engineErrors.removeValue(forKey: Self.masterErrorKey)
        reconcileMasterEngine()
        persist()
    }

    /// Master-chain engine failure, if any (non-permission).
    var masterEngineError: String? { engineErrors[Self.masterErrorKey] }

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

        for key in Self.retriableErrorKeys(errors: engineErrors,
                                           failedObjectIDs: failedObjectIDs,
                                           currentObjectIDs: appsByKey.mapValues(\.objectIDs)) {
            clearEngineError(forKey: key)
        }

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

        updateMasterExclusions()
        reconcileMasterEngine()
    }

    private func reconcileMasterEngine() {
        if masterConfig.needsMasterEngine {
            if masterEngine == nil {
                guard !permissionIssue, engineErrors[Self.masterErrorKey] == nil else { return }
                let engine = ProcessTapEngine(source: .systemWide)
                attachFailureHandler(engine, key: Self.masterErrorKey)
                engine.updateSource(objectIDs: perAppTappedObjectIDs())
                masterEngine = engine
            }
            // Master always follows the system default output device.
            masterEngine?.apply(config: masterConfig, targetDeviceUID: nil)
        } else if let engine = masterEngine {
            engine.stop()
            masterEngine = nil
        }
    }

    /// Processes owned by per-app engines must be excluded from the master tap, or their
    /// audio would be captured (and replayed) twice: .mutedWhenTapped only silences the
    /// device mix, not what other taps hear.
    private func perAppTappedObjectIDs() -> [AudioObjectID] {
        var seen = Set<AudioObjectID>()
        var ids: [AudioObjectID] = []
        for list in engineObjectIDs.values {
            for id in list where seen.insert(id).inserted {
                ids.append(id)
            }
        }
        return ids.sorted()
    }

    private func updateMasterExclusions() {
        masterEngine?.updateSource(objectIDs: perAppTappedObjectIDs())
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
        engine.onFailure = { [weak self, weak engine] message in
            guard let self, let engine else { return }
            self.handleEngineFailure(key: key, engine: engine, message: message)
        }
    }

    /// Recorded per-app failures that no longer apply because the app is present with a
    /// different process-object set than when it failed (relaunched, helpers changed).
    /// An app that is absent stays gated; the master key has no object IDs and is cleared
    /// by device changes instead.
    nonisolated static func retriableErrorKeys(errors: [String: String],
                                               failedObjectIDs: [String: [AudioObjectID]],
                                               currentObjectIDs: [String: [AudioObjectID]]) -> [String] {
        errors.keys.filter { key in
            guard let current = currentObjectIDs[key] else { return false }
            return failedObjectIDs[key] != current
        }.sorted()
    }

    private func clearEngineError(forKey key: String) {
        engineErrors.removeValue(forKey: key)
        failedObjectIDs.removeValue(forKey: key)
    }

    /// A device appeared/vanished or the default changed: earlier failures (typically
    /// "no usable output device") may no longer hold, so give every gated engine one retry.
    private func retryFailedEnginesAfterDeviceChange() {
        guard !engineErrors.isEmpty else { return }
        engineErrors.removeAll()
        failedObjectIDs.removeAll()
        reconcileEngines()
    }

    private func handleEngineFailure(key: String, engine: ProcessTapEngine, message: String) {
        // A stale delivery (the engine at this key was already replaced or removed)
        // must not tear down the live engine or pin a spurious error.
        let current = key == Self.masterErrorKey ? masterEngine : engines[key]
        guard current === engine else { return }
        if message.hasPrefix("permission:") {
            permissionIssue = true
        } else {
            engineErrors[key] = message
            failedObjectIDs[key] = engineObjectIDs[key]
        }
        // Drop the failed engine; the failure record gates recreation until a config change,
        // a device change, or the app reappearing with different process objects.
        if key == Self.masterErrorKey {
            masterEngine?.stop()
            masterEngine = nil
        } else {
            removeEngine(forKey: key)
            updateMasterExclusions()
        }
    }

    private func defaultOutputChanged() {
        engineLog.debug("controller: defaultOutputChanged")
        // Re-apply every engine, routed ones included: the engine keeps a pinned device
        // that still exists, while an engine in unplugged-fallback follows the new default
        // immediately instead of staying on the old one until the next unrelated event.
        for (key, engine) in engines {
            guard let config = appConfigs[key] else { continue }
            engine.apply(config: config, targetDeviceUID: config.outputDeviceUID)
        }
        if let masterEngine {
            masterEngine.apply(config: masterConfig, targetDeviceUID: nil)
        }
        retryFailedEnginesAfterDeviceChange()
    }

    private func deviceListChanged() {
        engineLog.debug("controller: deviceListChanged")
        // Routed engines re-resolve their UID: a vanished device falls back to the default
        // (routing is kept), a returning device is picked up again. Never surfaced as an error.
        for (key, engine) in engines {
            guard let config = appConfigs[key], let uid = config.outputDeviceUID else { continue }
            engine.apply(config: config, targetDeviceUID: uid)
        }
        let outputUIDs = Set(devices.outputDevices.map(\.uid))
        if outputUIDs != knownOutputUIDs {
            knownOutputUIDs = outputUIDs
            retryFailedEnginesAfterDeviceChange()
        }
    }

    private func serviceRestarted() {
        // coreaudiod restarted: every HAL object ID (devices, taps, aggregates, per-chain
        // listeners) is dead while device UIDs stay the same, so apply() alone would never
        // rebuild. Refresh the world and force-rebuild every live engine.
        // Order matters: the refreshes below synchronously queue updateSource/apply on the
        // engines, which would otherwise build a new chain that a later discard leaks
        // (doubled audio, a stray IOProc writing into freed levels). So: forget the dead
        // chains first, refresh (new process IDs reach the engines), then rebuild.
        for engine in engines.values {
            engine.discardChainAfterServiceRestart()
        }
        masterEngine?.discardChainAfterServiceRestart()
        devices.serviceRestarted()
        processes.serviceRestarted()
        for engine in engines.values {
            engine.rebuildAfterServiceRestart()
        }
        masterEngine?.rebuildAfterServiceRestart()
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
