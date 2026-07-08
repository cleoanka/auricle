import SwiftUI

struct EQPanel: View {
    @EnvironmentObject private var controller: AudioController
    @Binding var settings: EQSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Band index while its slider is being dragged; -1 is the preamp.
    @State private var draggedBand: Int?
    @State private var resetHovering = false
    @State private var showingSavePrompt = false
    @State private var newPresetName = ""

    private var resetAnimation: Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
                .frame(height: 24)
            bands
                .frame(height: 108)
                .opacity(settings.enabled ? 1 : 0.45)
                .allowsHitTesting(settings.enabled)
        }
        .alert("Save Preset", isPresented: $showingSavePrompt) {
            TextField("Preset Name", text: $newPresetName)
            Button("Cancel", role: .cancel) { newPresetName = "" }
            Button("Save") { savePreset() }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Toggle("Equalizer", isOn: $settings.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Equalizer enabled")
            Text("Equalizer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(settings.enabled ? .primary : .secondary)
            if let band = draggedBand {
                Text(dragReadout(band))
                    .font(.valueText)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            presetMenu
            resetButton
        }
    }

    private func dragReadout(_ band: Int) -> String {
        let label = band == -1 ? "Pre" : EQSettings.bandLabel(band)
        let value = band == -1 ? settings.preampDB : gain(at: band)
        return String(format: "%@  %+.1f dB", label, value)
    }

    private var presetMenu: some View {
        Menu {
            ForEach(EQPreset.builtins) { preset in
                presetItem(preset)
            }
            let customs = controller.customPresets.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if !customs.isEmpty {
                Divider()
                ForEach(customs) { preset in
                    presetItem(preset)
                }
            }
            Divider()
            Button("Save as…") {
                newPresetName = ""
                showingSavePrompt = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(activePreset?.name ?? "Custom")
                    .font(.valueText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: 110)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("EQ preset")
        .accessibilityValue(activePreset?.name ?? "Custom")
    }

    private var activePreset: EQPreset? {
        controller.allPresets.first {
            $0.gains == settings.gains && $0.preampDB == settings.preampDB
        }
    }

    private func presetItem(_ preset: EQPreset) -> some View {
        Toggle(isOn: Binding(
            get: { activePreset?.id == preset.id },
            set: { on in if on { apply(preset) } }
        )) {
            Text(preset.name)
        }
    }

    private func apply(_ preset: EQPreset) {
        withAnimation(resetAnimation) {
            settings.gains = normalizedGains(preset.gains)
            settings.preampDB = preset.preampDB
        }
    }

    private var resetButton: some View {
        Button {
            withAnimation(resetAnimation) {
                settings.gains = Array(repeating: 0, count: GraphicEQ.bandCount)
                settings.preampDB = 0
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12))
                .foregroundStyle(resetHovering ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { resetHovering = $0 }
        .disabled(settings.isFlat)
        .opacity(settings.isFlat ? 0.4 : 1)
        .accessibilityLabel("Reset equalizer to flat")
    }

    // MARK: Bands

    private var bands: some View {
        HStack(alignment: .bottom, spacing: 4) {
            column(label: "Pre", value: preampBinding, index: -1)
            VStack(spacing: 4) {
                Rectangle()
                    .fill(Color.separatorTone.opacity(0.5))
                    .frame(width: 1, height: 84)
                Text(" ")
                    .font(.bandLabel)
                    .hidden()
            }
            .padding(.horizontal, 2)
            ForEach(0..<GraphicEQ.bandCount, id: \.self) { index in
                column(label: EQSettings.bandLabel(index), value: gainBinding(index), index: index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func column(label: String, value: Binding<Float>, index: Int) -> some View {
        VStack(spacing: 4) {
            VerticalEQSlider(value: value, label: label) { editing in
                if editing {
                    draggedBand = index
                } else if draggedBand == index {
                    withAnimation(.easeOut(duration: 0.3)) { draggedBand = nil }
                }
            }
            Text(label)
                .font(.bandLabel)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 24)
    }

    private var preampBinding: Binding<Float> {
        Binding(
            get: { settings.preampDB },
            set: { settings.preampDB = $0 }
        )
    }

    private func gain(at index: Int) -> Float {
        index >= 0 && index < settings.gains.count ? settings.gains[index] : 0
    }

    private func gainBinding(_ index: Int) -> Binding<Float> {
        Binding(
            get: { gain(at: index) },
            set: { newValue in
                var gains = settings.gains
                while gains.count < GraphicEQ.bandCount { gains.append(0) }
                guard index >= 0 && index < gains.count else { return }
                gains[index] = newValue
                settings.gains = gains
            }
        )
    }

    private func normalizedGains(_ gains: [Float]) -> [Float] {
        var gains = gains
        if gains.count < GraphicEQ.bandCount {
            gains += Array(repeating: 0, count: GraphicEQ.bandCount - gains.count)
        } else if gains.count > GraphicEQ.bandCount {
            gains = Array(gains.prefix(GraphicEQ.bandCount))
        }
        return gains
    }

    // MARK: Presets

    private func savePreset() {
        var name = newPresetName.trimmingCharacters(in: .whitespaces)
        newPresetName = ""
        guard !name.isEmpty else { return }
        let existing = Set(controller.allPresets.map { $0.name.lowercased() })
        if existing.contains(name.lowercased()) {
            var suffix = 2
            while existing.contains("\(name) \(suffix)".lowercased()) { suffix += 1 }
            name = "\(name) \(suffix)"
        }
        controller.addCustomPreset(named: name, from: settings)
    }
}
