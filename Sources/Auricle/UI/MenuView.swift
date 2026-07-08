import SwiftUI

// AGENT-TODO(ui): implement the full popover per the UI spec (materials, spacing, permission
// banner, scroll behavior when the app list grows, footer). Keep width 380.

struct MenuView: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.permissionIssue {
                PermissionBanner()
            }
            OutputSection()
            Divider().padding(.horizontal, 12)
            AppsSection()
            Divider().padding(.horizontal, 12)
            InputSection()
            FooterBar()
        }
        .frame(width: 380)
    }
}

// AGENT-TODO(ui): banner shown when System Audio Recording permission is missing.
struct PermissionBanner: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Auricle needs System Audio Recording access.")
                .font(.caption)
            Spacer()
            Button("Open Settings") { controller.openPrivacySettings() }
                .font(.caption)
        }
        .padding(10)
    }
}

// AGENT-TODO(ui): footer per spec (settings gear -> opens "settings" window via openWindow +
// NSApp.activate, version label, quit button).
struct FooterBar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack {
            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Auricle \(AppInfo.version)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
