import XCTest
@testable import Auricle

/// Codable round-trip tests for the persisted settings model. These need no audio
/// hardware and no disk access — they encode to JSON and decode back, asserting the
/// value survives unchanged (the contract SettingsStore relies on for persistence).
final class SettingsStoreTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T,
                                                   file: StaticString = #filePath,
                                                   line: UInt = #line) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    func testEQSettingsRoundTrip() throws {
        var settings = EQSettings()
        settings.enabled = true
        settings.gains = [3, -3, 6, -6, 1, -1, 4, -4, 2, -2]
        settings.preampDB = -1.5
        try roundTrip(settings)
    }

    func testAppAudioConfigRoundTrip() throws {
        var config = AppAudioConfig()
        config.volume = 0.42
        config.boostDB = 7
        config.isMuted = true
        config.eq.enabled = true
        config.eq.gains[0] = 5
        config.outputDeviceUID = "BuiltInSpeakerDevice"
        try roundTrip(config)
    }

    func testAppAudioConfigWithNilRoutingRoundTrip() throws {
        // The common case: follow the default output device (outputDeviceUID == nil).
        try roundTrip(AppAudioConfig())
    }

    func testEQPresetRoundTrip() throws {
        let preset = EQPreset(name: "Custom Test",
                              gains: [1, 2, 3, 4, 5, -5, -4, -3, -2, -1],
                              preampDB: 2,
                              isBuiltin: false)
        try roundTrip(preset)
    }

    func testPersistedStateRoundTrip() throws {
        var state = PersistedState()
        state.rememberConfigs = false

        var master = AppAudioConfig()
        master.boostDB = 4
        master.eq.enabled = true
        state.masterConfig = master

        var safari = AppAudioConfig()
        safari.volume = 0.6
        safari.outputDeviceUID = "AirPods"
        state.appConfigs["com.apple.Safari"] = safari

        var music = AppAudioConfig()
        music.eq.enabled = true
        music.eq.gains = [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        state.appConfigs["com.apple.Music"] = music

        state.customPresets = [
            EQPreset(name: "My Bass", gains: [8, 6, 4, 2, 0, 0, 0, 0, 0, 0])
        ]

        // PersistedState is Codable but not Equatable; decode and compare its parts.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)

        XCTAssertEqual(decoded.rememberConfigs, state.rememberConfigs)
        XCTAssertEqual(decoded.masterConfig, state.masterConfig)
        XCTAssertEqual(decoded.appConfigs, state.appConfigs)
        XCTAssertEqual(decoded.customPresets, state.customPresets)
    }

    func testDefaultPersistedStateRoundTrip() throws {
        let state = PersistedState()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded.masterConfig, state.masterConfig)
        XCTAssertEqual(decoded.rememberConfigs, state.rememberConfigs)
        XCTAssertTrue(decoded.appConfigs.isEmpty)
        XCTAssertTrue(decoded.customPresets.isEmpty)
    }

    func testBuiltinPresetsRoundTrip() throws {
        // Every shipped preset must survive persistence unchanged.
        for preset in EQPreset.builtins {
            try roundTrip(preset)
        }
    }

    func testMissingKeysFallBackToDefaults() throws {
        // A settings file from another version lacks some keys: known values must survive
        // instead of the whole file decoding to defaults (and being overwritten on save).
        let json = """
        {
          "appConfigs": { "com.zoom": { "isMuted": true } },
          "customPresets": [ { "name": "Mine", "gains": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] } ]
        }
        """
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))

        var expected = AppAudioConfig()
        expected.isMuted = true
        XCTAssertEqual(decoded.appConfigs["com.zoom"], expected)
        XCTAssertEqual(decoded.masterConfig, AppAudioConfig())
        XCTAssertTrue(decoded.rememberConfigs)
        XCTAssertEqual(decoded.customPresets.count, 1)
        XCTAssertEqual(decoded.customPresets.first?.name, "Mine")
        XCTAssertEqual(decoded.customPresets.first?.preampDB, 0)
        XCTAssertEqual(decoded.customPresets.first?.isBuiltin, false)
    }

    func testPartialEQSettingsDecode() throws {
        let decoded = try JSONDecoder().decode(EQSettings.self, from: Data(#"{"enabled": true}"#.utf8))
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.gains, EQSettings().gains)
        XCTAssertEqual(decoded.preampDB, 0)
    }

    func testUnknownKeysAreIgnored() throws {
        let decoded = try JSONDecoder().decode(AppAudioConfig.self,
                                               from: Data(#"{"volume": 0.5, "balance": -0.2}"#.utf8))
        XCTAssertEqual(decoded.volume, 0.5)
    }
}
