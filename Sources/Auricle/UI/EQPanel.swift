import SwiftUI

// AGENT-TODO(ui): implement per spec — shared by the master chain and per-app drawers:
// - enable toggle, preset Menu (controller.allPresets, "Save as…" -> name prompt via alert
//   TextField, delete for custom presets), reset button
// - 10 vertical band sliders (±12 dB) labeled via EQSettings.bandLabel, preamp slider
// - compact: must fit a 380pt-wide popover gracefully

struct EQPanel: View {
    @EnvironmentObject private var controller: AudioController
    @Binding var settings: EQSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Equalizer", isOn: $settings.enabled)
                .toggleStyle(.switch)
            HStack(spacing: 4) {
                ForEach(0..<GraphicEQ.bandCount, id: \.self) { band in
                    VStack(spacing: 2) {
                        Slider(
                            value: Binding(
                                get: { Double(settings.gains[band]) },
                                set: { settings.gains[band] = Float($0) }
                            ),
                            in: -12...12
                        )
                        Text(EQSettings.bandLabel(band))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .disabled(false)
    }
}
