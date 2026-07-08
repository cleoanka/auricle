import Accelerate
import Foundation

final class GraphicEQ {
    static let bandCount = 10

    let sampleRate: Double
    let channelCount: Int

    private static let sectionQ = 1.41
    private static let gainLimitDB: Float = 12
    private static let chunkCapacity = 4096

    private let setup: vDSP_biquadm_Setup?
    // vDSP.h does not promise in-place operation for vDSP_biquadm, so the cascade
    // renders into this scratch block and the result is copied back to the caller.
    private let scratch: UnsafeMutablePointer<Float>
    private let inputPointers: UnsafeMutablePointer<UnsafePointer<Float>>
    private let outputPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    init(sampleRate: Double, channelCount: Int) {
        let channels = max(1, channelCount)
        self.sampleRate = sampleRate
        self.channelCount = channels

        let flat = GraphicEQ.coefficients(
            gainsDB: [Float](repeating: 0, count: GraphicEQ.bandCount),
            preampDB: 0,
            sampleRate: sampleRate,
            channelCount: channels)
        setup = flat.withUnsafeBufferPointer { buffer in
            vDSP_biquadm_CreateSetup(buffer.baseAddress!,
                                     vDSP_Length(GraphicEQ.bandCount),
                                     vDSP_Length(channels))
        }

        let scratchCount = GraphicEQ.chunkCapacity * channels
        scratch = .allocate(capacity: scratchCount)
        scratch.initialize(repeating: 0, count: scratchCount)
        inputPointers = .allocate(capacity: channels)
        outputPointers = .allocate(capacity: channels)
        for channel in 0..<channels {
            let row = scratch + channel * GraphicEQ.chunkCapacity
            (inputPointers + channel).initialize(to: UnsafePointer(row))
            (outputPointers + channel).initialize(to: row)
        }
    }

    deinit {
        if let setup {
            vDSP_biquadm_DestroySetup(setup)
        }
        inputPointers.deallocate()
        outputPointers.deallocate()
        scratch.deallocate()
    }

    /// Recompute coefficients and ramp toward them. Safe to call from any (non-RT) thread.
    func setParameters(gainsDB: [Float], preampDB: Float) {
        guard let setup else { return }
        let targets = GraphicEQ.coefficients(gainsDB: gainsDB,
                                             preampDB: preampDB,
                                             sampleRate: sampleRate,
                                             channelCount: channelCount)
        targets.withUnsafeBufferPointer { buffer in
            vDSP_biquadm_SetTargetsDouble(setup,
                                          buffer.baseAddress!,
                                          0.995,
                                          0.0001,
                                          0,
                                          0,
                                          vDSP_Length(GraphicEQ.bandCount),
                                          vDSP_Length(channelCount))
        }
    }

    /// In-place processing of `frameCount` frames. `channels` holds one pointer per channel;
    /// samples for channel c are at channels[c][i * stride]. RT-safe.
    func process(channels: [UnsafeMutablePointer<Float>], stride: Int, frameCount: Int) {
        guard let setup, stride > 0, frameCount > 0, channels.count >= channelCount else { return }
        var offset = 0
        while offset < frameCount {
            let count = min(GraphicEQ.chunkCapacity, frameCount - offset)
            for channel in 0..<channelCount {
                inputPointers[channel] = UnsafePointer(channels[channel] + offset * stride)
            }
            vDSP_biquadm(setup, inputPointers, vDSP_Stride(stride), outputPointers, 1, vDSP_Length(count))
            for channel in 0..<channelCount {
                let source = scratch + channel * GraphicEQ.chunkCapacity
                let destination = channels[channel] + offset * stride
                if stride == 1 {
                    memcpy(destination, source, count * MemoryLayout<Float>.size)
                } else {
                    for frame in 0..<count {
                        destination[frame * stride] = source[frame]
                    }
                }
            }
            offset += count
        }
    }

    /// Zero the filter delay lines. Call when a chain (re)starts so stale state never leaks in.
    func reset() {
        guard let setup else { return }
        vDSP_biquadm_ResetState(setup)
    }

    private static func coefficients(gainsDB: [Float],
                                     preampDB: Float,
                                     sampleRate: Double,
                                     channelCount: Int) -> [Double] {
        let preamp = pow(10.0, Double(max(-gainLimitDB, min(gainLimitDB, preampDB))) / 20)
        var flat = [Double](repeating: 0, count: 5 * bandCount * channelCount)
        for section in 0..<bandCount {
            let frequency = EQSettings.bandFrequencies[section]
            let raw = section < gainsDB.count ? gainsDB[section] : 0
            let gainDB = Double(max(-gainLimitDB, min(gainLimitDB, raw)))
            var b0 = 1.0
            var b1 = 0.0
            var b2 = 0.0
            var a1 = 0.0
            var a2 = 0.0
            // Bands at or above Nyquist stay identity so the cascade remains stable
            // when a device runs at a low sample rate.
            if sampleRate > 0, frequency < sampleRate * 0.49 {
                let amp = pow(10.0, gainDB / 40)
                let omega = 2 * Double.pi * frequency / sampleRate
                let alpha = sin(omega) / (2 * sectionQ)
                let a0 = 1 + alpha / amp
                b0 = (1 + alpha * amp) / a0
                b1 = -2 * cos(omega) / a0
                b2 = (1 - alpha * amp) / a0
                a1 = -2 * cos(omega) / a0
                a2 = (1 - alpha / amp) / a0
            }
            if section == 0 {
                b0 *= preamp
                b1 *= preamp
                b2 *= preamp
            }
            for channel in 0..<channelCount {
                let base = (section * channelCount + channel) * 5
                flat[base] = b0
                flat[base + 1] = b1
                flat[base + 2] = b2
                flat[base + 3] = a1
                flat[base + 4] = a2
            }
        }
        return flat
    }
}
