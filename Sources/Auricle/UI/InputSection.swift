import SwiftUI

// AGENT-TODO(ui): implement per spec (compact):
// - input device picker over controller.devices.inputDevices -> devices.setDefaultInput
// - input gain slider (devices.volumes[defaultInputID] via setVolume) + mute

struct InputSection: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(controller.devices.defaultInput?.name ?? "No input device")
                .font(.body)
        }
        .padding(14)
    }
}
