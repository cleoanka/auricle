import AppKit
import SwiftUI

struct InputSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Input")
                .padding(.top, 12)
                .padding(.leading, 12)
                .padding(.bottom, 6)
            InputDeviceList()
            InputGainRow()
        }
    }
}

// Same stacked-list language as the Output section: every input device visible, one click.
private struct InputDeviceList: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        let devices = controller.devices
        if devices.inputDevices.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("No input device")
                    .font(.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        } else {
            VStack(spacing: 1) {
                ForEach(devices.inputDevices) { device in
                    DeviceSelectRow(
                        symbol: device.symbolName == "laptopcomputer" ? "mic" : device.symbolName,
                        title: device.name,
                        selected: device.id == devices.defaultInputID
                    ) {
                        devices.setDefaultInput(device)
                    }
                    .accessibilityLabel("Input device \(device.name)")
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct InputGainRow: View {
    @EnvironmentObject private var controller: AudioController

    var body: some View {
        let devices = controller.devices
        let device = devices.defaultInput
        let muted = device.map { devices.isMuted($0.id, scope: .input) } ?? false
        let volume = device.map { devices.volume(for: $0.id, scope: .input) } ?? 0

        if device != nil {
            HStack(spacing: 8) {
                Image(systemName: "dial.low")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { if let device { devices.setVolume(Float($0), for: device, scope: .input) } }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .disabled(muted)
                .opacity(muted ? 0.4 : 1)
                .animation(.easeOut(duration: 0.15), value: muted)
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
                    if let device { devices.setMuted(!muted, for: device, scope: .input) }
                }
                .accessibilityLabel(muted ? "Unmute microphone" : "Mute microphone")
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .frame(height: 32)
        }
    }
}
