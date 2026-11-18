import SwiftUI

// MARK: Look

enum Theme {
    static let ground = Color(red: 0.078, green: 0.086, blue: 0.102)
    static let panel = Color(red: 0.102, green: 0.114, blue: 0.133)
    static let strip = Color(red: 0.137, green: 0.153, blue: 0.184)
    static let stripLine = Color(red: 0.184, green: 0.204, blue: 0.239)
    static let well = Color(red: 0.055, green: 0.063, blue: 0.075)
    static let button = Color(red: 0.173, green: 0.192, blue: 0.227)
    static let buttonLine = Color(red: 0.227, green: 0.251, blue: 0.294)
    static let text = Color(red: 0.949, green: 0.957, blue: 0.969)
    static let textDim = Color(red: 0.663, green: 0.690, blue: 0.737)
    static let accent = Color(red: 0.302, green: 0.639, blue: 1.0)
    static let accentDeep = Color(red: 0.118, green: 0.227, blue: 0.361)
    static let phantom = Color(red: 1.0, green: 0.694, blue: 0.361)
    /// 48V switched on: red in every column, whatever the colour of the column.
    static let phantomOn = Color(red: 0.827, green: 0.184, blue: 0.184)
    static let meter = Color(red: 0.184, green: 0.749, blue: 0.608)
    static let thumb = Color(red: 0.902, green: 0.914, blue: 0.937)
    static let warning = Color(red: 1.0, green: 0.82, blue: 0.4)

    static let slotHeight: CGFloat = 44

    /// Group paddings, gaps between groups and gaps between strips, added up across the screen.
    static let fixedWidth: CGFloat = 3 * 24 + 2 * 14 + 6 * 8

    /// Width of one strip so that the nine strips and their three groups fill the given width.
    static func stripWidth(forTotal total: CGFloat) -> CGFloat {
        max(((total - fixedWidth) / 9).rounded(.down), 64)
    }
}

extension StripColor {
    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.25)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.26)
        case .red: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .pink: return Color(red: 1.0, green: 0.50, blue: 0.75)
        case .purple: return Color(red: 0.72, green: 0.55, blue: 1.0)
        case .blue: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .cyan: return Color(red: 0.30, green: 0.85, blue: 0.92)
        case .green: return Color(red: 0.35, green: 0.85, blue: 0.50)
        case .lime: return Color(red: 0.72, green: 0.90, blue: 0.35)
        case .gray: return Color(red: 0.66, green: 0.69, blue: 0.74)
        }
    }

    var title: String { rawValue.capitalized }
}

enum StripButtonStyle {
    case normal, on, phantom, solid
}

/// A full-width button of a strip, one control slot high.
struct StripButton: View {
    let title: String
    var style: StripButtonStyle = .normal
    /// Colour of the column. An active button is filled with it instead of the default blue.
    var tint: Color? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.slotHeight)
                .foregroundStyle(foreground)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch style {
        case .normal: return Theme.text
        case .on: return tint == nil ? Theme.text : Theme.ground
        case .phantom: return Color.white
        case .solid: return Theme.ground
        }
    }

    private var background: Color {
        switch style {
        case .normal: return Theme.button
        case .on: return tint ?? Theme.accentDeep
        case .phantom: return Theme.phantomOn
        case .solid: return Theme.thumb
        }
    }

    private var border: Color {
        switch style {
        case .normal: return Theme.buttonLine
        case .on: return tint ?? Theme.accent
        case .phantom: return Theme.phantomOn
        case .solid: return Theme.thumb
        }
    }
}

/// An empty control slot, so that the faders of all strips line up.
struct StripSlotSpacer: View {
    var body: some View {
        Color.clear.frame(height: Theme.slotHeight)
    }
}

/// Vertical peak meter, -60 dBFS at the bottom, 0 dBFS at the top.
struct MeterBar: View {
    let db: Double?

    var body: some View {
        GeometryReader { geo in
            let fraction = MeterBar.fraction(db)
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.well)
                Capsule()
                    .fill(fraction > 0.9 ? Theme.phantom : Theme.meter)
                    .frame(height: geo.size.height * fraction)
            }
        }
        .frame(width: 10)
        .accessibilityLabel("Level meter")
        .accessibilityValue(db == nil ? "silent" : String(format: "%.0f dBFS", db ?? 0))
    }

    static func fraction(_ db: Double?) -> CGFloat {
        guard let db else { return 0 }
        return CGFloat(min(max((db + 60.0) / 60.0, 0), 1))
    }
}

/// Vertical fader. It moves by the distance dragged, so a touch never makes the level jump.
struct FaderView: View {
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let onChange: (Double) -> Void

    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            let thumbHeight: CGFloat = 30
            let usable = max(geo.size.height - thumbHeight, 1)
            let span = range.upperBound - range.lowerBound
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let fraction = CGFloat((clamped - range.lowerBound) / span)
            let y = (1 - fraction) * usable

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Theme.well)
                    .frame(width: 6, height: geo.size.height)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 6, height: max(geo.size.height - y - thumbHeight / 2, 0))
                    .offset(y: y + thumbHeight / 2)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.thumb)
                    .frame(width: 46, height: thumbHeight)
                    .overlay(Rectangle().fill(Theme.ground).frame(width: 26, height: 2))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .offset(y: y)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        let start = dragStart ?? clamped
                        if dragStart == nil { dragStart = start }
                        let delta = Double(-gesture.translation.height / usable) * span
                        let moved = min(max(start + delta, range.lowerBound), range.upperBound)
                        onChange((moved * 2).rounded() / 2)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(width: 50)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(MixScale.label(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 1, range.upperBound))
            case .decrement: onChange(max(value - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }
}

/// The frame every strip shares: name, control slots, meter and fader, readout, mute.
struct StripShell<Controls: View, Fader: View>: View {
    let width: CGFloat
    let title: String
    let subtitle: String
    let highlighted: Bool
    let readout: String
    let muted: Bool
    let onMute: () -> Void
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let fader: () -> Fader

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            .frame(height: 38)

            controls()

            HStack(spacing: 10) {
                fader()
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)

            Text(readout)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 20)

            StripButton(title: muted ? "MUTED" : "MUTE", style: muted ? .solid : .normal, action: onMute)
        }
        .padding(8)
        .frame(width: width)
        .background(Theme.strip)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlighted ? Theme.accent : Theme.stripLine, lineWidth: highlighted ? 2 : 1)
        )
    }
}

// MARK: Input strip (preamp and meter, no fader: inputs go to the iPad only)

/// Wide input meter with a scale and a peak-hold line. -60 dBFS at the bottom, 0 dBFS at the top.
struct BigMeter: View {
    let db: Double?
    let hold: Double?

    private static let marks: [String] = ["0", "-12", "-24", "-36", "-48", "-60"]

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(BigMeter.marks.indices, id: \.self) { index in
                    Text(BigMeter.marks[index])
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textDim)
                    if index < BigMeter.marks.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 26)
            .accessibilityHidden(true)

            GeometryReader { geo in
                let fraction = MeterBar.fraction(db)
                let holdFraction = MeterBar.fraction(hold)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.well)
                    Rectangle()
                        .fill(fraction > 0.9 ? Theme.phantom : Theme.meter)
                        .frame(height: geo.size.height * fraction)
                    if hold != nil {
                        Rectangle()
                            .fill(Theme.thumb)
                            .frame(height: 2)
                            .offset(y: -geo.size.height * holdFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(width: 30)
        }
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(hold == nil ? "silent" : String(format: "%.0f dBFS", hold ?? 0))
    }
}

struct InputStripView: View {
    @ObservedObject var probe: ProbeModel
    @ObservedObject var mixer: MixerStore
    let input: MixInput
    let width: CGFloat
    let askPhantom: (Int, Bool) -> Void

    @State private var showGain = false
    @State private var showLabel = false

    var body: some View {
        let peak = probe.peaks?.inputs[input.rawValue] ?? nil
        let hold = probe.inputHold[input.rawValue]
        let label = mixer.label(of: input)
        let tint = label.color.color
        let tinted = label.color != .gray
        VStack(spacing: 6) {
            Button {
                showLabel = true
            } label: {
                VStack(spacing: 2) {
                    Text("\(input.title) · \(input.subtitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                    Text(label.name.isEmpty ? "name" : label.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(label.name.isEmpty ? Theme.textDim : tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(input.title), named \(label.name.isEmpty ? "nothing yet" : label.name). Change name and colour")
            .popover(isPresented: $showLabel) {
                LabelPanel(mixer: mixer, input: input)
            }

            if input.isMic {
                micControls
            } else {
                lineControls
            }

            BigMeter(db: peak, hold: hold)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 6)

            Text(hold == nil ? "-inf" : String(format: "%.1f", hold ?? 0))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle((hold ?? -100) > -1 ? Theme.phantom : Theme.text)
                .frame(height: 20)

            Text("PEAK dBFS")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(height: Theme.slotHeight)
        }
        .padding(8)
        .frame(width: width)
        .background(tinted ? tint.opacity(0.16) : Color.clear)
        .background(Theme.strip)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tinted ? tint.opacity(0.9) : Theme.stripLine, lineWidth: tinted ? 2 : 1)
        )
    }

    /// The colour of this column, for its active buttons. nil for a grey column, which keeps the default blue.
    private var onTint: Color? {
        let color = mixer.label(of: input).color
        return color == .gray ? nil : color.color
    }

    @ViewBuilder
    private var micControls: some View {
        let index = input.pairIndex
        let gain = mixer.micGain(index)
        let phantomBit = index == 0 ? BabyfaceCodec.bitPhantom1 : BabyfaceCodec.bitPhantom2
        let padBit = index == 0 ? BabyfaceCodec.bitPad1 : BabyfaceCodec.bitPad2
        let phantomOn = probe.state?.setting(phantomBit) ?? false
        let padOn = probe.state?.setting(padBit) ?? false
        let ready = probe.state != nil && !probe.writeInProgress

        StripButton(title: gain == nil ? "GAIN --" : "GAIN +\(gain ?? 0) dB", enabled: gain != nil) {
            showGain = true
        }
        .popover(isPresented: $showGain) {
            GainPanel(
                title: "\(input.title) gain",
                value: Double(gain ?? 0),
                range: 0 ... 65,
                step: 1,
                unit: "dB"
            ) { mixer.setMicGain(index, dB: Int($0.rounded())) }
        }

        StripButton(title: phantomOn ? "48V ON" : "48V", style: phantomOn ? .phantom : .normal, enabled: ready) {
            askPhantom(index, !phantomOn)
        }
        StripButton(title: padOn ? "PAD ON" : "PAD", style: padOn ? .on : .normal, tint: onTint, enabled: ready) {
            probe.setInputSetting(bit: padBit, on: !padOn, label: "Pad \(input.title)")
        }
        StripButton(title: "LOW CUT", style: mixer.lowCut(input) ? .on : .normal, tint: onTint, enabled: probe.connected) {
            mixer.toggleLowCut(input)
        }
        StripButton(title: "HIGH CUT", style: mixer.highCut(input) ? .on : .normal, tint: onTint, enabled: probe.connected) {
            mixer.toggleHighCut(input)
        }
    }

    @ViewBuilder
    private var lineControls: some View {
        let index = input.pairIndex
        let gain = mixer.lineGain(index)
        let sensBit = index == 0 ? BabyfaceCodec.bitSens3 : BabyfaceCodec.bitSens4
        let plus4 = probe.state?.setting(sensBit) ?? true
        let ready = probe.state != nil && !probe.writeInProgress

        StripButton(title: gain == nil ? "GAIN --" : String(format: "GAIN +%.1f dB", gain ?? 0), enabled: gain != nil) {
            showGain = true
        }
        .popover(isPresented: $showGain) {
            GainPanel(
                title: "\(input.title) gain",
                value: gain ?? 0,
                range: 0 ... 9,
                step: 0.5,
                unit: "dB"
            ) { mixer.setLineGain(index, dB: $0) }
        }

        StripButton(title: plus4 ? "+4 dBu" : "-10 dBV", style: plus4 ? .normal : .on, tint: onTint, enabled: ready) {
            probe.setInputSetting(bit: sensBit, on: !plus4, label: "+4 dBu reference \(input.title)")
        }
        StripSlotSpacer()
        StripButton(title: "LOW CUT", style: mixer.lowCut(input) ? .on : .normal, tint: onTint, enabled: probe.connected) {
            mixer.toggleLowCut(input)
        }
        StripButton(title: "HIGH CUT", style: mixer.highCut(input) ? .on : .normal, tint: onTint, enabled: probe.connected) {
            mixer.toggleHighCut(input)
        }
    }
}

/// Popover to name an input and pick the colour of its column.
struct LabelPanel: View {
    @ObservedObject var mixer: MixerStore
    let input: MixInput

    private let columns = Array(repeating: GridItem(.fixed(48), spacing: 10), count: 5)

    var body: some View {
        let label = mixer.label(of: input)
        VStack(alignment: .leading, spacing: 16) {
            Text("\(input.title) name and colour").font(.headline)
            TextField(
                "Name, up to \(InputLabel.maxLength) letters",
                text: Binding(get: { mixer.label(of: input).name }, set: { mixer.setName($0, of: input) })
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.system(size: 20, weight: .semibold))

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(StripColor.allCases) { choice in
                    Button {
                        mixer.setColor(choice, of: input)
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: label.color == choice ? 3 : 0).padding(-4)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(label.color == choice ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}

// MARK: Playback pair strip

struct PairStripView: View {
    @ObservedObject var mixer: MixerStore
    let pair: MixPair
    let width: CGFloat

    var body: some View {
        let cell = mixer.cell(pair, in: mixer.selectedOutput)
        StripShell(
            width: width,
            title: pair.title,
            subtitle: pair.subtitle,
            highlighted: false,
            readout: cell.muted ? "muted" : MixScale.label(cell.dB),
            muted: cell.muted,
            onMute: { mixer.toggleMute(pair) },
            controls: {
                if mixer.selectedOutput == .phones {
                    StripButton(title: "STEREO", enabled: false) {}
                } else {
                    StripButton(title: PairStripView.modeTitle(cell.mode), style: cell.mode == .sum ? .normal : .on) {
                        mixer.cycleMode(pair)
                    }
                }
            },
            fader: {
                MeterBar(db: mixer.pairPeak(pair))
                FaderView(
                    value: cell.muted ? MixScale.floorDB : cell.dB,
                    range: MixScale.floorDB ... MixScale.topDB,
                    label: "\(pair.title) to \(mixer.selectedOutput.title)"
                ) { mixer.setFader(pair, dB: $0) }
            }
        )
    }
}

/// Popover with a slider and two step buttons for an input gain.
struct GainPanel: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            Text(step < 1 ? String(format: "+%.1f %@", value, unit) : String(format: "+%.0f %@", value, unit))
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range,
                step: step
            )
            .accessibilityLabel(title)
            HStack(spacing: 16) {
                Button {
                    onChange(max(value - step, range.lowerBound))
                } label: {
                    Text(step < 1 ? "- 0.5" : "- 1").frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.bordered)
                Button {
                    onChange(min(value + step, range.upperBound))
                } label: {
                    Text(step < 1 ? "+ 0.5" : "+ 1").frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

extension PairStripView {
    static func modeTitle(_ mode: PairMode) -> String {
        switch mode {
        case .sum: return "L + R"
        case .left: return "LEFT ONLY"
        case .right: return "RIGHT ONLY"
        }
    }
}

// MARK: Output strip

struct OutputStripView: View {
    @ObservedObject var probe: ProbeModel
    @ObservedObject var mixer: MixerStore
    let output: MixOutput
    let width: CGFloat

    var body: some View {
        let level = mixer.outputDB(output)
        let muted = mixer.isOutputMuted(output)
        StripShell(
            width: width,
            title: output.title,
            subtitle: output.subtitle,
            highlighted: mixer.selectedOutput == output,
            readout: readout(level: level, muted: muted),
            muted: muted,
            onMute: { mixer.toggleOutputMute(output) },
            controls: {
                StripSlotSpacer()
            },
            fader: {
                MeterBar(db: mixer.outputPeak(output))
                FaderView(
                    value: muted ? MixScale.floorDB : (level ?? MixScale.floorDB),
                    range: MixScale.floorDB ... MixScale.topDB,
                    label: "\(output.title) level"
                ) { mixer.setOutputDB(output, dB: $0) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { mixer.selectedOutput = output }
        .accessibilityAction(named: "Show the mix for \(output.title)") { mixer.selectedOutput = output }
    }

    private func readout(level: Double?, muted: Bool) -> String {
        if muted { return "muted" }
        guard let level else { return "--" }
        return String(format: "%.1f dB", level)
    }
}

// MARK: Mixer screen

struct PhantomRequest: Identifiable {
    let inputIndex: Int
    let target: Bool
    var id: String { "\(inputIndex)-\(target)" }
}

struct MixerView: View {
    @ObservedObject var probe: ProbeModel
    @ObservedObject var mixer: MixerStore

    @State private var phantomRequest: PhantomRequest?
    @State private var confirmOverwrite = false

    var body: some View {
        GeometryReader { geo in
            let width = Theme.stripWidth(forTotal: geo.size.width)
            let leftover = max(geo.size.width - (9 * width + Theme.fixedWidth), 0)
            VStack(spacing: 10) {
                // The mix buttons sit exactly above the three output strips.
                topBar(stripWidth: width, trailing: 12 + leftover)
                HStack(alignment: .top, spacing: 14) {
                    group("INPUTS", hint: "to Loopy Pro") {
                        ForEach(MixInput.allCases) { input in
                            InputStripView(probe: probe, mixer: mixer, input: input, width: width) { index, target in
                                askPhantom(index, target)
                            }
                        }
                    }
                    group(
                        "PLAYBACK",
                        hint: mixer.fullMixSent ? "to \(mixer.selectedOutput.title)" : "not sent yet",
                        hintColor: mixer.fullMixSent ? Theme.textDim : Theme.warning
                    ) {
                        ForEach(MixPair.allCases) { pair in
                            PairStripView(mixer: mixer, pair: pair, width: width)
                        }
                    }
                    group("OUTPUTS", hint: "master level") {
                        ForEach(MixOutput.allCases) { output in
                            OutputStripView(probe: probe, mixer: mixer, output: output, width: width)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !probe.writeStatus.isEmpty {
                    Text(probe.writeStatus)
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { probe.polling = true }
        .alert(
            phantomTitle,
            isPresented: Binding(get: { phantomRequest != nil }, set: { if !$0 { phantomRequest = nil } })
        ) {
            Button("Cancel", role: .cancel) { phantomRequest = nil }
            Button(phantomRequest?.target == true ? "Switch ON" : "Switch OFF") {
                if let request = phantomRequest {
                    let bit = request.inputIndex == 0 ? BabyfaceCodec.bitPhantom1 : BabyfaceCodec.bitPhantom2
                    probe.setInputSetting(bit: bit, on: request.target, label: "48V input \(request.inputIndex + 1)")
                }
                phantomRequest = nil
            }
        } message: {
            Text("Check what is plugged into this input. Only this 48V setting changes.")
        }
        .alert("Replace scene \(mixer.selectedScene + 1)?", isPresented: $confirmOverwrite) {
            Button("Cancel", role: .cancel) {}
            Button("Replace") { mixer.saveScene(mixer.selectedScene) }
        } message: {
            Text("The scene will hold the mix on screen and the levels, gains and input settings the Babyface has now.")
        }
        .alert(
            scenePhantomTitle,
            isPresented: Binding(
                get: { mixer.sceneAwaitingPhantomConfirm != nil },
                set: { if !$0 { mixer.sceneAwaitingPhantomConfirm = nil } }
            )
        ) {
            Button("Recall with 48V") {
                if let index = mixer.sceneAwaitingPhantomConfirm { mixer.recallScene(index, allowPhantomOn: true) }
                mixer.sceneAwaitingPhantomConfirm = nil
            }
            Button("Recall, keep 48V off") {
                if let index = mixer.sceneAwaitingPhantomConfirm { mixer.recallScene(index, allowPhantomOn: false) }
                mixer.sceneAwaitingPhantomConfirm = nil
            }
            Button("Cancel", role: .cancel) { mixer.sceneAwaitingPhantomConfirm = nil }
        } message: {
            Text("Check what is plugged into these inputs before switching phantom power on.")
        }
    }

    private var phantomTitle: String {
        guard let request = phantomRequest else { return "48V" }
        return "Switch 48V on input \(request.inputIndex + 1) \(request.target ? "ON" : "OFF")?"
    }

    private var scenePhantomTitle: String {
        guard let index = mixer.sceneAwaitingPhantomConfirm else { return "Scene" }
        let inputs = mixer.phantomSwitchOns(for: index).map { "input \($0 + 1)" }.joined(separator: " and ")
        return "Scene \(index + 1) switches 48V ON for \(inputs)"
    }

    private func askPhantom(_ inputIndex: Int, _ target: Bool) {
        phantomRequest = PhantomRequest(inputIndex: inputIndex, target: target)
    }

    /// One row: the connection and the scenes on the left, and on the right, above the outputs,
    /// which mix the playback faders show.
    private func topBar(stripWidth: CGFloat, trailing: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(probe.connected ? Theme.meter : Theme.warning)
                    .frame(width: 10, height: 10)
                Text(probe.connected ? "Connected" : "No reply")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)

            NavigationLink {
                DiagnosticsView(model: probe)
            } label: {
                Text(ProbeVersion.current)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .foregroundStyle(Theme.textDim)
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Diagnostics, version \(ProbeVersion.current)")

            scenesBar
                .padding(.leading, 8)

            Spacer(minLength: 8)

            ForEach(MixOutput.allCases) { output in
                let selected = mixer.selectedOutput == output
                Button {
                    mixer.selectedOutput = output
                } label: {
                    ViewThatFits(in: .horizontal) {
                        Text("MIX \(output.title)")
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                        VStack(spacing: 0) {
                            Text("MIX")
                                .font(.system(size: 11, weight: .semibold))
                            Text(output.title)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: stripWidth, height: 44)
                    .foregroundStyle(selected ? Theme.ground : Theme.text)
                    .background(selected ? Theme.accent : Theme.strip)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Theme.accent : Theme.buttonLine, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the mix for \(output.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.trailing, trailing)
    }

    /// Pick a slot with 1, 2 or 3, then LOAD sends that scene to the Babyface and SAVE stores into it.
    private var scenesBar: some View {
        let slot = mixer.selectedScene
        let slotHasScene = mixer.scenes[slot] != nil
        return HStack(spacing: 8) {
            Text("SCENE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textDim)
            ForEach(0 ..< 3, id: \.self) { index in
                let exists = mixer.scenes[index] != nil
                let selected = slot == index
                let loaded = mixer.activeScene == index && mixer.fullMixSent
                Button {
                    mixer.selectedScene = index
                } label: {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(loaded ? Theme.ground : (exists ? Theme.text : Theme.textDim))
                        .background(loaded ? Theme.thumb : Theme.strip)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? Theme.accent : Theme.buttonLine, lineWidth: selected ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scene \(index + 1)\(exists ? "" : ", empty")\(loaded ? ", loaded" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button {
                mixer.requestRecall(slot)
            } label: {
                Text("LOAD")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .foregroundStyle(Theme.ground)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!slotHasScene || !probe.connected)
            .opacity(slotHasScene && probe.connected ? 1 : 0.4)
            .accessibilityLabel("Load scene \(slot + 1) into the Babyface")

            Button {
                if slotHasScene {
                    confirmOverwrite = true
                } else {
                    mixer.saveScene(slot)
                }
            } label: {
                Text("SAVE")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .foregroundStyle(Theme.text)
                    .background(Theme.strip)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.buttonLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!probe.connected)
            .opacity(probe.connected ? 1 : 0.4)
            .accessibilityLabel("Save the current settings to scene \(slot + 1)")
        }
    }

    private func group<Content: View>(
        _ title: String,
        hint: String,
        hintColor: Color = Theme.textDim,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(hint)
                    .font(.system(size: 12, weight: hintColor == Theme.warning ? .bold : .medium))
                    .foregroundStyle(hintColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .top, spacing: 8) {
                content()
            }
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
