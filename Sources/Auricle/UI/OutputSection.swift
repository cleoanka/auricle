import SwiftUI

// AGENT-TODO(ui): implement per spec:
// - device picker (Menu) listing controller.devices.outputDevices with transport symbols,
//   checkmark on the default; selecting calls devices.setDefaultOutput
// - master volume slider bound to devices.volumes[defaultOutputID] via devices.setVolume,
//   scroll-wheel adjustable, mute toggle via devices.setMuted
// - disclosure for the MASTER chain: Boost slider (0...+12 dB) + system-wide EQPanel bound
//   through controller.setMasterConfig (use a local Binding wrapping controller.masterConfig)
// - master level meter (controller.masterLevels) when the master engine runs

struct OutputSection: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(controller.devices.defaultOutput?.name ?? "No output device")
                .font(.body)
        }
        .padding(14)
    }
}
