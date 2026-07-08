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
                        .contentShape(Rectangle())
                        .onTapGesture { toggleDrawer() }
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
            disclosureChevron
        }
        .padding(.horizontal, 8)
        .frame(height: appRowHeight)
    }

    private var disclosureChevron: some View {
        Button {
            toggleDrawer()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isExpanded ? .primary : .secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide options for \(app.name)" : "Show options for \(app.name)")
    }

    private func toggleDrawer() {
        withAnimation(expandAnimation) {
            expandedKey = isExpanded ? nil : app.configKey
        }
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
        .contentShape(Rectangle())
        .onTapGesture { toggleDrawer() }
        .accessibilityHidden(true)
    }

    // MARK: Drawer — routing, boost, EQ and reset, all visible and stacked

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrawerCaption(text: "Output")
                .padding(.leading, 2)
                .padding(.bottom, 3)
            routingList
            Divider()
                .opacity(0.5)
                .padding(.vertical, 8)
            BoostRow(boostDB: config.boostDB)
            Divider()
                .opacity(0.5)
                .padding(.vertical, 8)
            EQPanel(settings: config.eq)
            drawerFooter
        }
        .padding(10)
    }

    private var routingList: some View {
        let cfg = controller.config(for: app)
        return VStack(spacing: 1) {
            DeviceSelectRow(
                symbol: "macwindow.on.rectangle",
                title: "System Default",
                selected: cfg.outputDeviceUID == nil,
                compact: true
            ) {
                route(to: nil)
            }
            ForEach(controller.devices.outputDevices) { device in
                DeviceSelectRow(
                    symbol: device.symbolName,
                    title: device.name,
                    selected: cfg.outputDeviceUID == device.uid,
                    compact: true
                ) {
                    route(to: device.uid)
                }
            }
            if let uid = cfg.outputDeviceUID,
               !controller.devices.outputDevices.contains(where: { $0.uid == uid }) {
                DeviceSelectRow(
                    symbol: "exclamationmark.triangle",
                    title: "Unplugged device",
                    selected: true,
                    compact: true,
                    subtitle: "Using System Default until it returns"
                ) {
                    route(to: nil)
                }
            }
        }
    }

    private func route(to uid: String?) {
        var updated = controller.config(for: app)
        guard updated.outputDeviceUID != uid else { return }
        updated.outputDeviceUID = uid
        controller.setConfig(updated, for: app)
    }

    @ViewBuilder
    private var drawerFooter: some View {
        if hasSavedConfig || errorMessage != nil {
            HStack {
                if let errorMessage {
                    Button("Copy Diagnostics") {
                        copyDiagnostics(errorMessage)
                    }
                    .buttonStyle(.plain)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if hasSavedConfig {
                    Button("Reset") {
                        closeDrawerIfNeeded()
                        controller.resetConfig(for: app)
                    }
                    .buttonStyle(.plain)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .help("Forget every setting for \(app.name)")
                }
            }
            .padding(.top, 10)
        }
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
