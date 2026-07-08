import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var controller: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popoverVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if controller.permissionIssue {
                PermissionBanner()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .transition(reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .top)))
            }
            OutputSection()
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 10)
            AppsSection()
            Divider()
                .padding(.horizontal, 12)
                .padding(.top, 10)
            InputSection()
            Divider()
                .padding(.top, 12)
            FooterBar()
        }
        .frame(width: 380)
        .frame(maxHeight: 640)
        .environment(\.popoverVisible, popoverVisible)
        .animation(
            reduceMotion ? .linear(duration: 0.15) : .easeInOut(duration: 0.25),
            value: controller.permissionIssue
        )
        .onAppear { popoverVisible = true }
        .onDisappear { popoverVisible = false }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 18))
                .foregroundStyle(Color.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Audio Capture Permission Needed")
                    .font(.bannerTitle)
                    .foregroundStyle(.primary)
                Text("Auricle needs System Audio Recording permission to control per-app volume and show levels.")
                    .font(.bannerText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if controller.processes.apps.isEmpty {
                    Text("Apps can't be listed until permission is granted.")
                        .font(.bannerText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Open Privacy Settings…") {
                    controller.openPrivacySettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.eqWell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

struct FooterBar: View {
    @Environment(\.openWindow) private var openWindow
    @State private var gearHovering = false
    @State private var quitHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                openWindow(id: "settings")
                NSApp.activate()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(gearHovering ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { gearHovering = $0 }
            .accessibilityLabel("Settings")

            Text("\(AppInfo.name) \(AppInfo.version)")
                .font(.footerText)
                .foregroundStyle(Color.textTertiary)

            Spacer(minLength: 0)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.footerText)
            .foregroundStyle(quitHovering ? .primary : .secondary)
            .onHover { quitHovering = $0 }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}
