import Accelerate
import Foundation

// AGENT-TODO(dsp): implement using vDSP_biquadm (10 RBJ peaking sections per channel, Q ≈ 1.41,
// ISO octave centers from EQSettings.bandFrequencies). Coefficient updates go through
// vDSP_biquadm_SetTargetsDouble for click-free ramping. Preamp is folded into the section-0 output
// gain or applied as a scalar before the cascade. process() is called from the realtime IO thread:
// no allocation, no locks (parameters are swapped via the setup's own thread-safe target mechanism;
// `enabled` is read as a relaxed atomic snapshot by the engine, which simply skips process() when off).

final class GraphicEQ {
    static let bandCount = 10

    let sampleRate: Double
    let channelCount: Int

    init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        // AGENT-TODO(dsp)
    }

    /// Recompute coefficients and ramp toward them. Safe to call from any (non-RT) thread.
    func setParameters(gainsDB: [Float], preampDB: Float) {
        // AGENT-TODO(dsp)
    }

    /// In-place processing of `frameCount` frames. `channels` holds one pointer per channel;
    /// samples for channel c are at channels[c][i * stride]. RT-safe.
    func process(channels: [UnsafeMutablePointer<Float>], stride: Int, frameCount: Int) {
        // AGENT-TODO(dsp)
    }
}
