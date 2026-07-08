import AppKit
import SwiftUI

struct InputSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Input")
                .padding(.top, 12)
                .padding(.leading, 12)
                .padding(.bottom, 6)
            InputRow()
        }
    }
}

private struct InputRow: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        let devices = controller.devices
        let device = devices.defaultInput
        let muted = device.map { devices.isMuted($0.id) } ?? false
        let volume = device.map { devices.volume(for: $0.id) } ?? 0

        HStack(spacing: 8) {
            Image(systemName: "mic")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            if devices.inputDevices.isEmpty {
                Text("No input device")
                    .font(.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Menu {
                    ForEach(devices.inputDevices) { candidate in
                        Toggle(isOn: Binding(
                            get: { candidate.id == devices.defaultInputID },
                            set: { on in if on { devices.setDefaultInput(candidate) } }
                        )) {
                            Label(candidate.name, systemImage: candidate.symbolName)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(device?.name ?? "Select Device")
                            .font(.rowTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .layoutPriority(1)
                .help(device?.name ?? "Select input device")
                .accessibilityLabel("Input device")
                .accessibilityValue(device?.name ?? "none")

                Spacer(minLength: 4)

                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { if let device { devices.setVolume(Float($0), for: device) } }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .frame(width: 110)
                .disabled(muted || device == nil)
                .opacity(muted ? 0.4 : 1)
                .animation(.easeOut(duration: 0.15), value: muted)
                .layoutPriority(2)
                .accessibilityLabel("Input gain")
                .accessibilityValue("\(Int((volume * 100).rounded())) percent")

                Text(percentText(volume))
                    .font(.valueText)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)

                MuteButton(
                    isMuted: muted,
                    level: volume,
                    kind: .microphone,
                    diameter: 22,
                    iconSize: 12
                ) {
                    if let device { devices.setMuted(!muted, for: device) }
                }
                .accessibilityLabel(muted ? "Unmute microphone" : "Mute microphone")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}
