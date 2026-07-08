import SwiftUI

// AGENT-TODO(ui): implement per spec:
// - section header "Apps"; empty state when controller.processes.apps is empty
// - one AppRow per app; ScrollView with max height when the list grows
// AppRow:
// - app icon (Image(nsImage:)), name, live LevelMeter when controller.isManaged(app)
// - volume slider (config.volume 0...1), mute button, overflow menu:
//   route to device ("System Default" + each outputDevice), Boost slider, EQ toggle
//   expanding an inline EQPanel drawer (animated), Reset
// - error badge when controller.engineErrors[app.configKey] != nil (tooltip with message)
// - all edits flow through controller.setConfig(_:for:) using a local Binding helper

struct AppsSection: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps")
                .font(.caption)
                .foregroundStyle(.secondary)
            if controller.processes.apps.isEmpty {
                Text("Nothing is playing audio")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.processes.apps) { app in
                    AppRow(app: app)
                }
            }
        }
        .padding(14)
    }
}

struct AppRow: View {
    @EnvironmentObject private var controller: AudioController
    let app: AudioApp

    private var config: Binding<AppAudioConfig> {
        Binding(
            get: { controller.config(for: app) },
            set: { controller.setConfig($0, for: app) }
        )
    }

    var body: some View {
        HStack {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
            Spacer()
            // AGENT-TODO(ui): slider, mute, meter, overflow menu, EQ drawer
        }
    }
}
