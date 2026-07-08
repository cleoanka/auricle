import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: AudioController
    @State private var launchAtLogin = false
    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            generalSection
            presetsSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.bottom, 8)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            if let loginItemMessage {
                Text(loginItemMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Remember per-app settings", isOn: $controller.rememberConfigs)
        } footer: {
            Text("Volume, EQ, and routing are restored when an app returns.")
        }
    }

    /// Login items are best-effort: ad-hoc signing, translocation, or running unbundled
    /// (e.g. `swift run`) can all make SMAppService fail. Never crash, report inline.
    private func setLaunchAtLogin(_ enable: Bool) {
        loginItemMessage = nil
        let service = SMAppService.mainApp
        do {
            if enable {
                if Bundle.main.bundlePath.contains("/AppTranslocation/") {
                    loginItemMessage = "Auricle is running from a temporary location. Move it to /Applications and try again."
                    launchAtLogin = false
                    return
                }
                try service.register()
                if service.status == .requiresApproval {
                    loginItemMessage = "Approve Auricle in System Settings › General › Login Items."
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try service.unregister()
            }
        } catch {
            if service.status == .requiresApproval {
                loginItemMessage = "Approve Auricle in System Settings › General › Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else {
                loginItemMessage = "Couldn't update launch at login: \(error.localizedDescription)"
            }
        }
        launchAtLogin = service.status == .enabled
    }

    // MARK: Presets

    private var presetsSection: some View {
        Section("Presets") {
            if controller.customPresets.isEmpty {
                Text("No custom presets yet. Use “Save as…” in any equalizer.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.customPresets) { preset in
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Button {
                            controller.deleteCustomPreset(preset)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete preset \(preset.name)")
                    }
                }
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(AppInfo.name) \(AppInfo.version)")
                        .font(.headline)
                    Link("Auricle on GitHub", destination: AppInfo.repoURL)
                        .font(.callout)
                    Text("Per-app volume, EQ, and routing via Core Audio process taps. Requires the System Audio Recording permission.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Open source, MIT licensed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var appIcon: NSImage {
        NSApp?.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage()
    }
}
