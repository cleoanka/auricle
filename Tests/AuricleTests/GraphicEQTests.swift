import XCTest
@testable import Auricle

/// Pure-logic tests for the biquad coefficient generator. No audio hardware, no
/// realtime thread — we only assert numerical properties of the flat coefficient
/// array `[b0, b1, b2, a1, a2]` laid out per section, per channel.
final class GraphicEQTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let bandCount = GraphicEQ.bandCount

    /// Read the five coefficients for a given section (0-based) and channel.
    private func section(_ index: Int,
                         channel: Int,
                         in flat: [Double],
                         channelCount: Int) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        let base = (index * channelCount + channel) * 5
        return (flat[base], flat[base + 1], flat[base + 2], flat[base + 3], flat[base + 4])
    }

    func testFlatInputIsIdentity() {
        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 0, count: bandCount),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: 2)

        XCTAssertEqual(flat.count, 5 * bandCount * 2)

        // A 0 dB peaking biquad has amp == 1, which makes the numerator equal the
        // denominator: b0 == 1 and (b1, b2) == (a1, a2). The transfer function is
        // therefore exactly 1 — a true pass-through — even though the individual
        // coefficients are not zero.
        for index in 0..<bandCount {
            for channel in 0..<2 {
                let c = section(index, channel: channel, in: flat, channelCount: 2)
                XCTAssertEqual(c.b0, 1.0, accuracy: 1e-12, "band \(index) b0")
                XCTAssertEqual(c.b1, c.a1, accuracy: 1e-12, "band \(index) b1 must equal a1")
                XCTAssertEqual(c.b2, c.a2, accuracy: 1e-12, "band \(index) b2 must equal a2")
            }
        }
    }

    func testNyquistGuardKeepsHighBandsIdentity() {
        // At 8 kHz sample rate, bands at/above ~3.9 kHz (>= 0.49 * Fs) must stay
        // identity so the cascade cannot blow up on a low-rate device.
        let lowRate = 8_000.0
        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 10, count: bandCount),
            preampDB: 0,
            sampleRate: lowRate,
            channelCount: 1)

        for index in 0..<bandCount {
            let frequency = EQSettings.bandFrequencies[index]
            let c = section(index, channel: 0, in: flat, channelCount: 1)
            if frequency >= lowRate * 0.49 {
                XCTAssertEqual(c.b0, 1.0, accuracy: 1e-12, "band \(index) should be identity above Nyquist guard")
                XCTAssertEqual(c.b1, 0.0, accuracy: 1e-12)
                XCTAssertEqual(c.b2, 0.0, accuracy: 1e-12)
                XCTAssertEqual(c.a1, 0.0, accuracy: 1e-12)
                XCTAssertEqual(c.a2, 0.0, accuracy: 1e-12)
            } else {
                XCTAssertNotEqual(c.b0, 1.0, accuracy: 1e-12, "band \(index) below guard should be shaped")
            }
        }

        // Non-finite coefficients would indicate an unstable/degenerate filter.
        for value in flat {
            XCTAssertTrue(value.isFinite, "coefficient must be finite")
        }
    }

    func testZeroSampleRateProducesIdentity() {
        // A device that reports Fs == 0 must not divide by zero; the guard forces
        // identity everywhere.
        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 6, count: bandCount),
            preampDB: 0,
            sampleRate: 0,
            channelCount: 1)
        for index in 0..<bandCount {
            let c = section(index, channel: 0, in: flat, channelCount: 1)
            XCTAssertEqual(c.b0, 1.0, accuracy: 1e-12)
        }
    }

    func testGainClampAtPlusTwelveDB() {
        // A wildly out-of-range boost (+40 dB) must clamp to +12 dB. We compare the
        // 32 Hz band coefficients against an explicit +12 dB request; they must match.
        let clamped = GraphicEQ.coefficients(
            gainsDB: [40] + [Float](repeating: 0, count: bandCount - 1),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: 1)
        let atLimit = GraphicEQ.coefficients(
            gainsDB: [12] + [Float](repeating: 0, count: bandCount - 1),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: 1)

        let a = section(0, channel: 0, in: clamped, channelCount: 1)
        let b = section(0, channel: 0, in: atLimit, channelCount: 1)
        XCTAssertEqual(a.b0, b.b0, accuracy: 1e-12)
        XCTAssertEqual(a.b1, b.b1, accuracy: 1e-12)
        XCTAssertEqual(a.b2, b.b2, accuracy: 1e-12)
        XCTAssertEqual(a.a1, b.a1, accuracy: 1e-12)
        XCTAssertEqual(a.a2, b.a2, accuracy: 1e-12)
    }

    func testGainClampAtMinusTwelveDB() {
        let clamped = GraphicEQ.coefficients(
            gainsDB: [-40] + [Float](repeating: 0, count: bandCount - 1),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: 1)
        let atLimit = GraphicEQ.coefficients(
            gainsDB: [-12] + [Float](repeating: 0, count: bandCount - 1),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: 1)

        let a = section(0, channel: 0, in: clamped, channelCount: 1)
        let b = section(0, channel: 0, in: atLimit, channelCount: 1)
        XCTAssertEqual(a.b0, b.b0, accuracy: 1e-12)
        XCTAssertEqual(a.b2, b.b2, accuracy: 1e-12)
    }

    func testPreampAppliedOnlyToSectionZero() {
        // Preamp scales b0/b1/b2 of section 0 only. With flat gains, section 0's b0
        // equals the linear preamp factor and every other section stays identity.
        let preampDB: Float = 6
        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 0, count: bandCount),
            preampDB: preampDB,
            sampleRate: sampleRate,
            channelCount: 1)

        let expected = pow(10.0, Double(preampDB) / 20.0)
        let s0 = section(0, channel: 0, in: flat, channelCount: 1)
        XCTAssertEqual(s0.b0, expected, accuracy: 1e-9, "section 0 b0 should equal linear preamp gain")

        for index in 1..<bandCount {
            let c = section(index, channel: 0, in: flat, channelCount: 1)
            XCTAssertEqual(c.b0, 1.0, accuracy: 1e-12, "preamp must not touch section \(index)")
        }
    }

    func testPreampIsClamped() {
        // +40 dB preamp clamps to +12 dB -> linear factor ~3.98.
        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 0, count: bandCount),
            preampDB: 40,
            sampleRate: sampleRate,
            channelCount: 1)
        let expected = pow(10.0, 12.0 / 20.0)
        let s0 = section(0, channel: 0, in: flat, channelCount: 1)
        XCTAssertEqual(s0.b0, expected, accuracy: 1e-9)
    }

    func testCoefficientsAreFiniteAcrossFullGainSweep() {
        // Every band pushed to both extremes must yield finite, stable coefficients.
        for gain in [Float(-12), 12] {
            let flat = GraphicEQ.coefficients(
                gainsDB: [Float](repeating: gain, count: bandCount),
                preampDB: gain,
                sampleRate: sampleRate,
                channelCount: 2)
            for value in flat {
                XCTAssertTrue(value.isFinite)
            }
        }
    }

    func testChannelRowsAreIdentical() {
        // The same band must produce identical coefficients on every channel.
        let flat = GraphicEQ.coefficients(
            gainsDB: [3, -3, 6, -6, 1, -1, 4, -4, 2, -2],
            preampDB: 2,
            sampleRate: sampleRate,
            channelCount: 2)
        for index in 0..<bandCount {
            let left = section(index, channel: 0, in: flat, channelCount: 2)
            let right = section(index, channel: 1, in: flat, channelCount: 2)
            XCTAssertEqual(left.b0, right.b0, accuracy: 1e-12)
            XCTAssertEqual(left.a2, right.a2, accuracy: 1e-12)
        }
    }
}
