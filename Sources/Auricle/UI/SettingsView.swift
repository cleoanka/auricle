import ServiceManagement
import SwiftUI

// AGENT-TODO(ui): implement per spec:
// - Launch at login toggle via SMAppService.mainApp (handle failure gracefully — e.g. when
//   running unbundled from `swift run`, show the error inline instead of crashing)
// - "Remember per-app settings" toggle -> controller.rememberConfigs
// - About: app icon/name/version, link to AppInfo.repoURL, brief "how it works" note
//   (Core Audio process taps; System Audio Recording permission)

struct SettingsView: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        Form {
            Toggle("Remember per-app settings", isOn: $controller.rememberConfigs)
            LabeledContent("Version", value: AppInfo.version)
            Link("GitHub", destination: AppInfo.repoURL)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.bottom, 8)
    }
}
