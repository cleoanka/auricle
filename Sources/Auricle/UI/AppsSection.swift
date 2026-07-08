import AppKit
import SwiftUI

private let appRowHeight: CGFloat = 52

struct AppsSection: View {
    @EnvironmentObject private var controller: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// configKey of the single row whose EQ drawer is open.
    @State private var expandedKey: String?

    private var reorderAnimation: Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Apps")
                .padding(.top, 12)
                .padding(.leading, 12)
                .padding(.bottom, 6)
            content
        }
        .onChange(of: controller.processes.apps) { _, apps in
            // A quit app must not leave its drawer armed to reopen on relaunch.
            guard let key = expandedKey, !apps.contains(where: { $0.configKey == key }) else { return }
            expandedKey = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let apps = controller.processes.apps
        if apps.isEmpty {
            // With a permission problem the banner already explains the empty list.
            if !controller.permissionIssue {
                EmptyAppsState()
            }
        } else {
            // The popover's outer ScrollView handles overflow; no inner scroll region.
            appList(apps)
        }
    }

    private func appList(_ apps: [AudioApp]) -> some View {
        VStack(spacing: 2) {
            ForEach(apps) { app in
                AppRow(app: app, expandedKey: $expandedKey)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.horizontal, 8)
        .animation(reorderAnimation, value: apps.map(\.id))
    }
}

private struct EmptyAppsState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 28))
                .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
            Text("No apps are playing audio")
                .font(.rowTitle)
                .foregroundStyle(.secondary)
            Text("Apps appear here when they start playing.")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .accessibilityElement(children: .combine)
    }
}

struct AppRow: View {
    @EnvironmentObject private var controller: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: AudioApp
    @Binding var expandedKey: String?

    @State private var hovering = false

    private var config: Binding<AppAudioConfig> {
        Binding(
            get: { controller.config(for: app) },
            set: { controller.setConfig($0, for: app) }
        )
    }

    private var isExpanded: Bool { expandedKey == app.configKey }
    private var errorMessage: String? { controller.engineErrors[app.configKey] }
    private var hasSavedConfig: Bool { controller.appConfigs[app.configKey] != nil }
    private var configuredSilent: Bool { !app.isPlaying && hasSavedConfig }

    private var expandAnimation: Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        let cfg = controller.config(for: app)
        VStack(spacing: 0) {
            mainRow(cfg)
            if isExpanded {
                drawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isExpanded ? Color.eqWell : (hovering ? Color.rowHover : Color.clear))
        )
        .onHover { inside in
            withAnimation(.easeOut(duration: inside ? 0.12 : 0.20)) { hovering = inside }
        }
        .animation(expandAnimation, value: isExpanded)
    }

    // MARK: Main row

    private func mainRow(_ cfg: AppAudioConfig) -> some View {
        HStack(spacing: 10) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.rowTitle)
                        .foregroundStyle(configuredSilent ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(app.name)
                    if errorMessage == nil, app.isPlaying, controller.isManaged(app) {
                        LevelMeter { controller.levels(for: app) ?? (left: 0, right: 0) }
                    }
                }
                if let errorMessage {
                    Button {
                        retryEngine()
                    } label: {
                        Text("Audio engine couldn't attach — click to retry")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.warning)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(errorMessage)
                } else {
                    sliderRow(cfg)
                }
            }
            MuteButton(isMuted: cfg.isMuted, level: cfg.volume, diameter: 22, iconSize: 12) {
                var updated = controller.config(for: app)
                updated.isMuted.toggle()
                controller.setConfig(updated, for: app)
            }
            .accessibilityLabel(cfg.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
            overflowMenu(cfg)
        }
        .padding(.horizontal, 8)
        .frame(height: appRowHeight)
    }

    private func sliderRow(_ cfg: AppAudioConfig) -> some View {
        HStack(spacing: 8) {
            VolumeSlider(value: config.volume)
                .controlSize(.mini)
                .frame(minWidth: 70)
                .disabled(cfg.isMuted || controller.permissionIssue)
                .opacity(cfg.isMuted ? 0.4 : (configuredSilent ? 0.7 : 1))
                .animation(.easeOut(duration: 0.15), value: cfg.isMuted)
                .help(controller.permissionIssue ? "Requires permission" : "\(app.name) volume")
                .accessibilityLabel("\(app.name) volume")
                .accessibilityValue("\(Int((cfg.volume * 100).rounded())) percent")
            if cfg.isMuted {
                Text("Muted")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text(percentText(cfg.volume))
                    .font(.valueText)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private var iconView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            .opacity(configuredSilent ? 0.55 : 1)
            if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.warning)
                    .offset(x: 4, y: 3)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Overflow menu

    private func overflowMenu(_ cfg: AppAudioConfig) -> some View {
        Menu {
            Menu("Output") {
                routeItem(nil, title: "System Default")
                Divider()
                ForEach(controller.devices.outputDevices) { device in
                    routeItem(device.uid, title: device.name, symbol: device.symbolName)
                }
                if let uid = cfg.outputDeviceUID,
                   !controller.devices.outputDevices.contains(where: { $0.uid == uid }) {
                    Divider()
                    Toggle(isOn: .constant(true)) {
                        Label("Missing Device — using System Default", systemImage: "exclamationmark.triangle")
                    }
                    .disabled(true)
                }
            }
            Menu("Boost") {
                boostItem(0, title: "Off (0 dB)")
                boostItem(3, title: "+3 dB")
                boostItem(6, title: "+6 dB")
                boostItem(9, title: "+9 dB")
                boostItem(12, title: "+12 dB")
            }
            Button {
                withAnimation(expandAnimation) {
                    expandedKey = isExpanded ? nil : app.configKey
                }
            } label: {
                if cfg.eq.enabled {
                    Label(isExpanded ? "Hide Equalizer" : "Show Equalizer", systemImage: "checkmark")
                } else {
                    Text(isExpanded ? "Hide Equalizer" : "Show Equalizer")
                }
            }
            Divider()
            Button("Reset App Settings") {
                closeDrawerIfNeeded()
                controller.resetConfig(for: app)
            }
            if configuredSilent {
                Button("Forget This App") {
                    closeDrawerIfNeeded()
                    controller.resetConfig(for: app)
                }
            }
            if let errorMessage {
                Divider()
                Button("Copy Diagnostics") {
                    copyDiagnostics(errorMessage)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Options for \(app.name)")
    }

    private func routeItem(_ uid: String?, title: String, symbol: String? = nil) -> some View {
        Toggle(isOn: Binding(
            get: { controller.config(for: app).outputDeviceUID == uid },
            set: { on in
                guard on else { return }
                var updated = controller.config(for: app)
                updated.outputDeviceUID = uid
                controller.setConfig(updated, for: app)
            }
        )) {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
    }

    private func boostItem(_ value: Float, title: String) -> some View {
        Toggle(isOn: Binding(
            get: { abs(controller.config(for: app).boostDB - value) < 0.01 },
            set: { on in
                guard on else { return }
                var updated = controller.config(for: app)
                updated.boostDB = value
                controller.setConfig(updated, for: app)
            }
        )) {
            Text(title)
        }
    }

    // MARK: Drawer

    private var drawer: some View {
        VStack(spacing: 0) {
            BoostRow(boostDB: config.boostDB)
            Divider()
                .opacity(0.5)
                .padding(.vertical, 8)
            EQPanel(settings: config.eq)
        }
        .padding(10)
    }

    // MARK: Actions

    private func closeDrawerIfNeeded() {
        if isExpanded {
            withAnimation(expandAnimation) { expandedKey = nil }
        }
    }

    /// Re-applying the current config makes the controller reconcile (and so retry) the engine.
    private func retryEngine() {
        controller.setConfig(controller.config(for: app), for: app)
    }

    private func copyDiagnostics(_ message: String) {
        let text = """
        \(AppInfo.name) \(AppInfo.version)
        App: \(app.name) (\(app.bundleID ?? "no bundle ID"), pid \(app.id))
        Error: \(message)
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
