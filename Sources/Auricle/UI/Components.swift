import AppKit
import SwiftUI

// MARK: - Design tokens

extension Font {
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let rowSubtitle = Font.system(size: 11, weight: .regular)
    static let valueText = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let bandLabel = Font.system(size: 9, weight: .medium).monospacedDigit()
    static let bannerText = Font.system(size: 12, weight: .regular)
    static let bannerTitle = Font.system(size: 12, weight: .semibold)
    static let footerText = Font.system(size: 11, weight: .regular)
}

extension Color {
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let meterTrack = Color.primary.opacity(0.08)
    static let rowHover = Color.primary.opacity(0.06)
    static let rowPressed = Color.primary.opacity(0.10)
    static let eqWell = Color.primary.opacity(0.04)
    static let warning = Color(nsColor: .systemYellow)
    static let errorTone = Color(nsColor: .systemRed)
    static let boostTint = Color(nsColor: .systemOrange)
    static let separatorTone = Color(nsColor: .separatorColor)
}

func percentText(_ value: Float) -> String {
    "\(Int((value * 100).rounded()))%"
}

// MARK: - Popover visibility (meters/timers must idle when the popover is closed)

private struct PopoverVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var popoverVisible: Bool {
        get { self[PopoverVisibleKey.self] }
        set { self[PopoverVisibleKey.self] = newValue }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Row hover highlight

struct RowHoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.rowHover)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .opacity(hovering ? 1 : 0)
            )
            .onHover { inside in
                withAnimation(.easeOut(duration: inside ? 0.12 : 0.20)) { hovering = inside }
            }
    }
}

extension View {
    func rowHoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(RowHoverHighlight(cornerRadius: cornerRadius))
    }
}

// MARK: - Scroll-wheel adjustment

struct ScrollWheelCatcher: ViewModifier {
    var isEnabled: Bool
    var onTick: (Int, NSEvent.ModifierFlags) -> Void

    @State private var state = MonitorState()

    final class MonitorState {
        var monitor: Any?
        var residual: CGFloat = 0

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            residual = 0
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && isEnabled { start() } else { state.stop() }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { state.stop() }
            }
            .onDisappear { state.stop() }
    }

    private func start() {
        guard state.monitor == nil else { return }
        let state = state
        let tick = onTick
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.hasPreciseScrollingDeltas {
                state.residual += event.scrollingDeltaY
                let ticks = Int(state.residual / 10)
                if ticks != 0 {
                    state.residual -= CGFloat(ticks) * 10
                    tick(ticks, event.modifierFlags)
                }
            } else {
                let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
                if dy != 0 { tick(dy > 0 ? 1 : -1, event.modifierFlags) }
            }
            return nil
        }
    }
}

extension View {
    func onScrollWheel(
        enabled: Bool = true,
        _ onTick: @escaping (Int, NSEvent.ModifierFlags) -> Void
    ) -> some View {
        modifier(ScrollWheelCatcher(isEnabled: enabled, onTick: onTick))
    }
}

// MARK: - Mute button

struct MuteButton: View {
    enum Kind {
        case speaker, microphone
    }

    var isMuted: Bool
    var level: Float = 1
    var kind: Kind = .speaker
    var diameter: CGFloat = 28
    var iconSize: CGFloat = 15
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .medium))
                .symbolEffect(.bounce, value: isMuted)
                .foregroundStyle(iconColor)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(HoverCircleButtonStyle(hovering: hovering, diameter: diameter))
        .onHover { inside in
            withAnimation(.easeOut(duration: inside ? 0.12 : 0.20)) { hovering = inside }
        }
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }

    private var symbolName: String {
        switch kind {
        case .microphone:
            return isMuted ? "mic.slash.fill" : "mic.fill"
        case .speaker:
            if isMuted { return "speaker.slash.fill" }
            switch level {
            case ..<0.01: return "speaker.fill"
            case ..<0.34: return "speaker.wave.1.fill"
            case ..<0.67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }

    private var iconColor: Color {
        if kind == .microphone, isMuted { return .errorTone }
        return isMuted ? Color.primary : Color.secondary
    }
}

struct HoverCircleButtonStyle: ButtonStyle {
    var hovering: Bool
    var diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.rowPressed : Color.rowHover)
                    .frame(width: diameter, height: diameter)
                    .opacity(hovering || configuration.isPressed ? 1 : 0)
            )
    }
}

// MARK: - Volume slider

struct VolumeSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1

    var body: some View {
        Slider(
            value: Binding(get: { Double(value) }, set: { value = Float($0) }),
            in: Double(range.lowerBound)...Double(range.upperBound)
        )
    }
}

// MARK: - Device selection row (always-visible stacked device lists — no hidden pickers)

struct DeviceSelectRow: View {
    var symbol: String
    var title: String
    var selected: Bool
    /// Smaller metrics for rows inside an app drawer.
    var compact: Bool = false
    /// Warning line under the title (e.g. a routed device that is unplugged).
    var subtitle: String? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 12 : 14))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(compact ? .rowSubtitle : .rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.warning)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: subtitle == nil ? (compact ? 28 : 34) : 40)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Color.rowHover : Color.clear)
        )
        .onHover { inside in
            withAnimation(.easeOut(duration: inside ? 0.12 : 0.20)) { hovering = inside }
        }
        .help(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Tiny uppercase label used inside drawers ("OUTPUT", …).
struct DrawerCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Color.textTertiary)
    }
}

// MARK: - Boost row (shared by the master drawer and per-app drawers)

struct BoostRow: View {
    @Binding var boostDB: Float

    var body: some View {
        HStack(spacing: 10) {
            Text("Boost")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(get: { Double(boostDB) }, set: { boostDB = Float($0) }),
                in: 0...12
            )
            .tint(Color.boostTint)
            .controlSize(.small)
            .accessibilityLabel("Boost")
            .accessibilityValue(boostText)
            Text(boostText)
                .font(.valueText)
                .foregroundStyle(boostDB > 0 ? Color.boostTint : Color.secondary)
                .frame(width: 44, alignment: .trailing)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.25)) { boostDB = 0 }
                }
                .help("Double-click to reset")
        }
        .frame(height: 32)
    }

    private var boostText: String {
        boostDB.rounded() == boostDB
            ? String(format: "%+.0f dB", boostDB)
            : String(format: "%+.1f dB", boostDB)
    }
}

// MARK: - Stereo level meter (44 × 8)

struct LevelMeter: View {
    /// Returns the current (left, right) RMS in 0...1.
    var levels: () -> (left: Float, right: Float)

    @Environment(\.popoverVisible) private var popoverVisible
    @State private var smoother = MeterSmoother()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !popoverVisible)) { timeline in
            Canvas { context, size in
                let raw = popoverVisible ? levels() : (left: Float(0), right: Float(0))
                let display = smoother.step(now: timeline.date, raw: raw)
                drawBar(&context, y: 0, width: size.width, level: display.left)
                drawBar(&context, y: 5, width: size.width, level: display.right)
            }
        }
        .frame(width: 44, height: 8)
        .accessibilityHidden(true)
    }

    private func drawBar(_ context: inout GraphicsContext, y: CGFloat, width: CGFloat, level: Float) {
        context.fill(
            Path(roundedRect: CGRect(x: 0, y: y, width: width, height: 3), cornerRadius: 1.5),
            with: .color(.meterTrack)
        )
        let fill = CGFloat(level) * width
        guard fill > 0.3 else { return }
        let segments: [(from: CGFloat, to: CGFloat, color: Color)] = [
            (0, 0.8, .accentColor),
            (0.8, 0.95, .warning),
            (0.95, 1, .errorTone),
        ]
        for segment in segments {
            let start = segment.from * width
            guard fill > start else { break }
            let end = min(fill, segment.to * width)
            context.fill(
                Path(roundedRect: CGRect(x: start, y: y, width: end - start, height: 3), cornerRadius: 1.5),
                with: .color(segment.color)
            )
        }
    }
}

/// Attack-instant / exponential-release smoothing (τ ≈ 350 ms to −60 dB), per the UI spec.
final class MeterSmoother {
    private var displayLeft: Float = 0
    private var displayRight: Float = 0
    private var lastTick: Date?

    func step(now: Date, raw: (left: Float, right: Float)) -> (left: Float, right: Float) {
        let dt = lastTick.map { max(now.timeIntervalSince($0), 0) } ?? (1.0 / 30.0)
        lastTick = now
        let decay = Float(pow(0.001, dt / 0.35))
        displayLeft = max(normalized(raw.left), displayLeft * decay)
        displayRight = max(normalized(raw.right), displayRight * decay)
        return (displayLeft, displayRight)
    }

    private func normalized(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10f(rms)
        return min(max((db + 60) / 60, 0), 1)
    }
}

// MARK: - Vertical EQ slider (macOS 14 has no native vertical slider)

struct VerticalEQSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = -12...12
    var label: String = ""
    var onEditing: ((Bool) -> Void)? = nil

    private let width: CGFloat = 24
    private let trackHeight: CGFloat = 84
    private let thumbSize: CGFloat = 12

    @State private var hovering = false
    @State private var dragging = false

    private var span: Float { range.upperBound - range.lowerBound }

    private var normalized: CGFloat {
        span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
    }

    private var thumbY: CGFloat { (1 - min(max(normalized, 0), 1)) * trackHeight }

    private var zeroY: CGFloat {
        guard span > 0, range.contains(0) else { return trackHeight }
        return (1 - CGFloat((0 - range.lowerBound) / span)) * trackHeight
    }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.meterTrack)
                .frame(width: 3, height: trackHeight)
            Rectangle()
                .fill(Color.separatorTone)
                .frame(width: 7, height: 1)
                .position(x: width / 2, y: zeroY)
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3, height: abs(thumbY - zeroY))
                .position(x: width / 2, y: (thumbY + zeroY) / 2)
            Circle()
                .fill(Color(nsColor: .controlColor))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .scaleEffect(hovering || dragging ? 1.15 : 1)
                .position(x: width / 2, y: thumbY)
        }
        .frame(width: width, height: trackHeight)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { hovering = inside }
        }
        .gesture(dragGesture)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                value = range.contains(0) ? 0 : range.lowerBound
            }
        }
        .onScrollWheel { ticks, _ in
            clampSet(value + Float(ticks) * 0.5)
        }
        .accessibilityElement()
        .accessibilityLabel(label.isEmpty ? "EQ band" : "\(label) band")
        .accessibilityValue(String(format: "%+.1f decibels", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: clampSet(value + 0.5)
            case .decrement: clampSet(value - 0.5)
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                if !dragging {
                    dragging = true
                    onEditing?(true)
                }
                let norm = 1 - min(max(gesture.location.y / trackHeight, 0), 1)
                var v = range.lowerBound + Float(norm) * span
                let snapDisabled = NSEvent.modifierFlags.contains(.option)
                if !snapDisabled, range.contains(0), abs(v) <= 0.75 { v = 0 }
                value = v
            }
            .onEnded { _ in
                dragging = false
                onEditing?(false)
            }
    }

    private func clampSet(_ v: Float) {
        value = min(max(v, range.lowerBound), range.upperBound)
    }
}

// MARK: - Previews (controller-free components only)

#Preview("Vertical EQ slider") {
    struct Host: View {
        @State private var value: Float = 4.5
        var body: some View {
            VerticalEQSlider(value: $value, label: "1k")
                .padding(20)
        }
    }
    return Host()
}

#Preview("Level meter") {
    LevelMeter { (left: 0.35, right: 0.18) }
        .padding(20)
        .environment(\.popoverVisible, true)
}

#Preview("Mute button") {
    struct Host: View {
        @State private var muted = false
        var body: some View {
            MuteButton(isMuted: muted, level: 0.7) { muted.toggle() }
                .padding(20)
        }
    }
    return Host()
}
