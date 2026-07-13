import XCTest
@testable import Auricle

final class EQSettingsTests: XCTestCase {
    func testDefaultIsFlat() {
        XCTAssertTrue(EQSettings().isFlat)
    }

    func testNonZeroGainIsNotFlat() {
        var settings = EQSettings()
        settings.gains[3] = 4
        XCTAssertFalse(settings.isFlat)
    }

    func testNonZeroPreampIsNotFlat() {
        var settings = EQSettings()
        settings.preampDB = -2
        XCTAssertFalse(settings.isFlat)
    }

    func testEnabledFlagDoesNotAffectFlatness() {
        // isFlat describes the curve, not whether the EQ is switched on.
        var settings = EQSettings()
        settings.enabled = true
        XCTAssertTrue(settings.isFlat)
    }

    func testBandLabels() {
        // 10 bands: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k.
        XCTAssertEqual(EQSettings.bandLabel(0), "32")
        XCTAssertEqual(EQSettings.bandLabel(1), "64")
        XCTAssertEqual(EQSettings.bandLabel(2), "125")
        XCTAssertEqual(EQSettings.bandLabel(3), "250")
        XCTAssertEqual(EQSettings.bandLabel(4), "500")
        XCTAssertEqual(EQSettings.bandLabel(5), "1k")
        XCTAssertEqual(EQSettings.bandLabel(6), "2k")
        XCTAssertEqual(EQSettings.bandLabel(7), "4k")
        XCTAssertEqual(EQSettings.bandLabel(8), "8k")
        XCTAssertEqual(EQSettings.bandLabel(9), "16k")
    }

    func testBandFrequenciesMatchBandCount() {
        XCTAssertEqual(EQSettings.bandFrequencies.count, GraphicEQ.bandCount)
        XCTAssertEqual(EQSettings().gains.count, GraphicEQ.bandCount)
    }
}

final class AppAudioConfigTests: XCTestCase {
    func testDefaultConfigNeedsNoEngine() {
        let config = AppAudioConfig()
        XCTAssertFalse(config.needsEngine)
        XCTAssertFalse(config.needsMasterEngine)
    }

    func testVolumeChangeNeedsEngineButNotMaster() {
        var config = AppAudioConfig()
        config.volume = 0.5
        XCTAssertTrue(config.needsEngine)
        // Master chain ignores per-app volume — the device volume covers it.
        XCTAssertFalse(config.needsMasterEngine)
    }

    func testMuteNeedsEngineButNotMaster() {
        var config = AppAudioConfig()
        config.isMuted = true
        XCTAssertTrue(config.needsEngine)
        XCTAssertFalse(config.needsMasterEngine)
    }

    func testRoutingNeedsEngineButNotMaster() {
        var config = AppAudioConfig()
        config.outputDeviceUID = "SomeDeviceUID"
        XCTAssertTrue(config.needsEngine)
        XCTAssertFalse(config.needsMasterEngine)
    }

    func testBoostNeedsBothEngines() {
        var config = AppAudioConfig()
        config.boostDB = 6
        XCTAssertTrue(config.needsEngine)
        XCTAssertTrue(config.needsMasterEngine)
    }

    func testEnabledEQNeedsBothEngines() {
        var config = AppAudioConfig()
        config.eq.enabled = true
        XCTAssertTrue(config.needsEngine)
        XCTAssertTrue(config.needsMasterEngine)
    }

    func testShapedButDisabledEQNeedsNoEngine() {
        // A non-flat curve that is switched off must not spin up an engine.
        var config = AppAudioConfig()
        config.eq.gains[0] = 6
        config.eq.enabled = false
        XCTAssertFalse(config.needsEngine)
        XCTAssertFalse(config.needsMasterEngine)
    }
}

final class AppInfoTests: XCTestCase {
    /// Locate the repository root VERSION file relative to this source file so the
    /// test works regardless of the current working directory used by `swift test`.
    private func repositoryVersionString() throws -> String {
        // Tests/AuricleTests/ModelsTests.swift -> repo root is three levels up.
        let versionURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AuricleTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("VERSION")
        let raw = try String(contentsOf: versionURL, encoding: .utf8)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAppInfoVersionMatchesVersionFile() throws {
        // Guards the version-drift footgun: the VERSION file is the single source of
        // truth for releases, and AppInfo.version must never disagree with it.
        let fileVersion = try repositoryVersionString()
        XCTAssertEqual(AppInfo.version, fileVersion,
                       "AppInfo.version (\(AppInfo.version)) must match the VERSION file (\(fileVersion))")
    }

    func testAppInfoConstants() {
        XCTAssertEqual(AppInfo.name, "Auricle")
        XCTAssertEqual(AppInfo.bundleID, "io.github.cleoanka.Auricle")
    }
}
