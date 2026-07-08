import AppKit
import SwiftUI

struct OutputSection: View {
    @EnvironmentObject private var controller: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chainExpanded = false

    private var expandAnimation: Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var masterConfig: Binding<AppAudioConfig> {
        Binding(
            get: { controller.masterConfig },
            set: { controller.setMasterConfig($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Output")
                .padding(.top, 14)
                .padding(.leading, 12)
                .padding(.bottom, 6)
            OutputDeviceRow()
            MasterVolumeRow()
            MasterChainDisclosureRow(expanded: $chainExpanded)
            VStack(spacing: 0) {
                if chainExpanded {
                    MasterChainDrawer(
                        config: masterConfig,
                        errorMessage: controller.masterEngineError,
                        onRetry: { controller.setMasterConfig(controller.masterConfig) }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        }
        .animation(expandAnimation, value: chainExpanded)
    }
}

// Every output device stays visible, stacked — selection is one click, no hidden picker.
private struct OutputDeviceRow: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        let devices = controller.devices
        if devices.outputDevices.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("No output device")
                    .font(.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        } else {
            VStack(spacing: 1) {
                ForEach(devices.outputDevices) { device in
                    DeviceSelectRow(
                        symbol: device.symbolName,
                        title: device.name,
                        selected: device.id == devices.defaultOutputID
                    ) {
                        devices.setDefaultOutput(device)
                    }
                    .accessibilityLabel("Output device \(device.name)")
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct MasterVolumeRow: View {
    @EnvironmentObject private var controller: AudioController
    @State private var emphasizeReadout = false
    @State private var emphasisTask: Task<Void, Never>?

    var body: some View {
        let devices = controller.devices
        let device = devices.defaultOutput
        let muted = device.map { devices.isMuted($0.id, scope: .output) } ?? false
        let volume = device.map { devices.volume(for: $0.id, scope: .output) } ?? 0

        HStack(spacing: 10) {
            MuteButton(isMuted: muted, level: volume, diameter: 28, iconSize: 15) {
                if let device { devices.setMuted(!muted, for: device, scope: .output) }
            }
            .disabled(device == nil)
            .accessibilityLabel(muted ? "Unmute output" : "Mute output")

            Slider(
                value: Binding(
                    get: { Double(volume) },
                    set: { if let device { devices.setVolume(Float($0), for: device, scope: .output) } }
                ),
                in: 0...1
            )
            .disabled(muted || device == nil)
            .opacity(muted ? 0.4 : 1)
            .animation(.easeOut(duration: 0.15), value: muted)
            .accessibilityLabel("Master volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")

            if muted {
                Text("Muted")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text(percentText(volume))
                    .font(.valueText)
                    .foregroundStyle(emphasizeReadout ? .primary : .secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .onScrollWheel(enabled: device != nil && !muted) { ticks, modifiers in
            guard let device = controller.devices.defaultOutput else { return }
            let step: Float = modifiers.contains(.shift) ? 0.06 : (modifiers.contains(.option) ? 0.01 : 0.02)
            let current = controller.devices.volume(for: device.id, scope: .output)
            let next = min(max(current + Float(ticks) * step, 0), 1)
            controller.devices.setVolume(next, for: device, scope: .output)
            bumpReadoutEmphasis()
        }
    }

    private func bumpReadoutEmphasis() {
        emphasizeReadout = true
        emphasisTask?.cancel()
        emphasisTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { emphasizeReadout = false }
        }
    }
}

private struct MasterChainDisclosureRow: View {
    @EnvironmentObject private var controller: AudioController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expanded: Bool

    var body: some View {
        let config = controller.masterConfig
        let active = config.boostDB != 0 || config.eq.enabled
        Button {
            withAnimation(reduceMotion
                ? .linear(duration: 0.15)
                : .spring(response: 0.32, dampingFraction: 0.86)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text("Master Effects")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if active {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
                if controller.masterLevels != nil {
                    LevelMeter { controller.masterLevels ?? (left: 0, right: 0) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Hide master effects" : "Show master effects")
    }
}

private struct MasterChainDrawer: View {
    @Binding var config: AppAudioConfig
    var errorMessage: String?
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.warning)
                        Text("Audio engine couldn't attach — click to retry")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.warning)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(errorMessage)
                .padding(.bottom, 8)
            }
            BoostRow(boostDB: $config.boostDB)
            Divider()
                .opacity(0.5)
                .padding(.vertical, 8)
            EQPanel(settings: $config.eq)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.eqWell)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
