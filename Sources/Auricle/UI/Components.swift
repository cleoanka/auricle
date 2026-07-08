import SwiftUI

// AGENT-TODO(ui): shared components per spec.
// VolumeSlider: custom capsule slider — scroll-wheel adjustable, fine-grained drag, subtle fill,
//   optional symbol; used by master, per-app rows, and input.
// LevelMeter: compact stereo RMS meter (two thin bars), smoothed at ~12 Hz via a TimelineView
//   or Timer; values come from ProcessTapEngine.currentLevels through AudioController.

struct VolumeSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1

    var body: some View {
        Slider(
            value: Binding(get: { Double(value) }, set: { value = Float($0) }),
            in: Double(range.lowerBound)...Double(range.upperBound)
        )
    }
}

struct LevelMeter: View {
    /// Returns the current (left, right) RMS in 0...1.
    var levels: () -> (left: Float, right: Float)

    var body: some View {
        // AGENT-TODO(ui)
        EmptyView()
    }
}
