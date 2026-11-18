import Foundation
import Combine
import AVFoundation

/// The three outputs the mixer shows. OUT 1 and OUT 2 are mono. PHONES is one stereo output.
nonisolated enum MixOutput: Int, CaseIterable, Identifiable, Codable, Sendable {
    case out1, out2, phones

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .out1: return "OUT 1"
        case .out2: return "OUT 2"
        case .phones: return "PHONES"
        }
    }

    var subtitle: String {
        switch self {
        case .out1: return "XLR 1"
        case .out2: return "XLR 2"
        case .phones: return "Stereo"
        }
    }

    /// Output numbers of the mixer cells.
    var cellOutputs: [Int] {
        switch self {
        case .out1: return [0]
        case .out2: return [1]
        case .phones: return [2, 3]
        }
    }

    /// Channels of the output level message.
    var levelChannels: [Int] {
        switch self {
        case .out1: return [BabyfaceCodec.channelMainLeft]
        case .out2: return [BabyfaceCodec.channelMainRight]
        case .phones: return [BabyfaceCodec.channelPhonesLeft, BabyfaceCodec.channelPhonesRight]
        }
    }
}

/// The stereo pairs coming back from the iPad over USB. PB 1/2 is the main output of Loopy Pro.
nonisolated enum MixPair: Int, CaseIterable, Identifiable, Codable, Sendable {
    case pb12, pb34

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pb12: return "PB 1/2"
        case .pb34: return "PB 3/4"
        }
    }

    var subtitle: String {
        switch self {
        case .pb12: return "USB 1 + 2"
        case .pb34: return "USB 3 + 4"
        }
    }

    /// Source numbers of the mixer cells, which are also the indices of the peak meters.
    var leftSource: Int { self == .pb12 ? 12 : 14 }
    var rightSource: Int { self == .pb12 ? 13 : 15 }
}

/// The four hardware inputs. They are preamps here: they go to the iPad, never straight to an output.
nonisolated enum MixInput: Int, CaseIterable, Identifiable, Sendable {
    case in1, in2, in3, in4

    var id: Int { rawValue }

    var title: String { "IN \(rawValue + 1)" }
    var subtitle: String { isMic ? "Mic" : "Line" }
    var isMic: Bool { self == .in1 || self == .in2 }
    /// 0 for the first input of its pair (IN 1, IN 3), 1 for the second.
    var pairIndex: Int { rawValue % 2 }
}

/// Colour of an input column.
nonisolated enum StripColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case yellow, orange, red, pink, purple, blue, cyan, green, lime, gray

    var id: String { rawValue }
}

/// What the user calls an input, and the colour of its column.
nonisolated struct InputLabel: Codable, Sendable {
    var name: String
    var color: StripColor

    static let maxLength = 8

    static func defaults() -> [InputLabel] {
        [
            InputLabel(name: "VOICE", color: .yellow),
            InputLabel(name: "", color: .gray),
            InputLabel(name: "GUITAR", color: .blue),
            InputLabel(name: "DRUMS", color: .green),
        ]
    }
}

nonisolated enum MixScale {
    /// The bottom of a fader. For a mixer cell it means off.
    static let floorDB: Double = -60
    static let topDB: Double = 0

    static func isOff(_ dB: Double) -> Bool { dB <= floorDB + 0.25 }

    static func label(_ dB: Double) -> String {
        isOff(dB) ? "off" : String(format: "%.1f dB", dB)
    }
}

/// Which side of a stereo pair feeds a mono output. Adding both sides of the same sound raises it by 6 dB;
/// one side alone does not.
nonisolated enum PairMode: String, Codable, Sendable {
    case sum, left, right

    var next: PairMode {
        switch self {
        case .sum: return .left
        case .left: return .right
        case .right: return .sum
        }
    }
}

/// One cell of the mix: what one pair sends to one output. A muted cell keeps its level to return to.
nonisolated struct MixCell: Codable, Sendable {
    var dB: Double = MixScale.floorDB
    var muted: Bool = false
    /// Used on the mono outputs only. PHONES always stays stereo.
    var mode: PairMode = .sum
}

nonisolated struct MixDocument: Codable, Sendable {
    /// cells[output][pair]
    var cells: [[MixCell]]
    /// Level an output returns to when its mute is released, in dB.
    var outputMemoryDB: [Double]
    /// Low cut and high cut of the four inputs. The unit does not report them.
    var lowCut: [Bool] = [false, false, false, false]
    var highCut: [Bool] = [false, false, false, false]

    init(cells: [[MixCell]], outputMemoryDB: [Double]) {
        self.cells = cells
        self.outputMemoryDB = outputMemoryDB
    }

    private enum CodingKeys: String, CodingKey {
        case cells, outputMemoryDB, lowCut, highCut
    }

    /// Documents saved before the filters existed have no filter keys: they load with the filters off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cells = try container.decode([[MixCell]].self, forKey: .cells)
        outputMemoryDB = try container.decode([Double].self, forKey: .outputMemoryDB)
        let low = try container.decodeIfPresent([Bool].self, forKey: .lowCut) ?? []
        let high = try container.decodeIfPresent([Bool].self, forKey: .highCut) ?? []
        lowCut = low.count == 4 ? low : [false, false, false, false]
        highCut = high.count == 4 ? high : [false, false, false, false]
    }

    static func initial() -> MixDocument {
        var cells = Array(repeating: Array(repeating: MixCell(), count: MixPair.allCases.count),
                          count: MixOutput.allCases.count)
        // A careful start: nothing goes to the XLR outputs until a fader is raised.
        // The main pair of the iPad is audible on the headphones.
        cells[MixOutput.phones.rawValue][MixPair.pb12.rawValue].dB = -6
        return MixDocument(cells: cells, outputMemoryDB: Array(repeating: -20, count: MixOutput.allCases.count))
    }

    var isWellFormed: Bool {
        cells.count == MixOutput.allCases.count
            && cells.allSatisfy { $0.count == MixPair.allCases.count }
            && outputMemoryDB.count == MixOutput.allCases.count
    }
}

/// Everything a scene brings back: the mix, the output levels, the input gains and the input settings.
nonisolated struct MixScene: Codable, Sendable {
    var doc: MixDocument
    /// Raw output level of OUT 1, OUT 2 and PHONES, as the unit reported them.
    var outputRaw: [Int]
    /// Gain of microphone input 1 and 2, in dB.
    var micGain: [Int]
    /// Gain of line input 3 and 4, in half dB.
    var lineGainHalf: [Int]
    /// The six input setting bits: 48V 1/2, +4 dBu reference 3/4, pad 1/2.
    var settings: Int
    var savedAt: Date
}

/// Keeps the mix, saves it, and sends it to the unit. The unit does not report its mixer,
/// so what this store holds is the only picture of it.
@MainActor
final class MixerStore: ObservableObject {

    @Published var selectedOutput: MixOutput = .out1
    @Published private(set) var doc: MixDocument
    /// False until the whole mix has gone to the unit in this session. Until then the unit may still
    /// carry cells set by another app.
    @Published var fullMixSent = false
    @Published var sendingFullMix = false

    private weak var probe: ProbeModel?

    private var pending: [String: [[UInt8]]] = [:]
    private var flushScheduled = false
    /// Values just set by hand. They win over the polled state for a moment, so a control does not jump back.
    private var holds: [String: (value: Double, until: Date)] = [:]

    /// Name and colour of the four inputs.
    @Published private(set) var inputLabels: [InputLabel] = InputLabel.defaults()

    /// The three scenes. nil is an empty slot.
    @Published private(set) var scenes: [MixScene?] = [nil, nil, nil]
    /// The scene slot the LOAD and SAVE buttons act on.
    @Published var selectedScene = 0
    /// The scene loaded or saved last, if any.
    @Published var activeScene: Int?
    /// A scene whose recall would switch 48V on and therefore waits for a confirmation.
    @Published var sceneAwaitingPhantomConfirm: Int?

    private static let storageKey = "mix.document.v3"
    private static let scenesKey = "mix.scenes.v1"
    private static let labelsKey = "input.labels.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(MixDocument.self, from: data),
           saved.isWellFormed {
            doc = saved
        } else {
            doc = MixDocument.initial()
        }
        if let data = UserDefaults.standard.data(forKey: Self.labelsKey),
           let saved = try? JSONDecoder().decode([InputLabel].self, from: data),
           saved.count == MixInput.allCases.count {
            inputLabels = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.scenesKey),
           let saved = try? JSONDecoder().decode([String: MixScene].self, from: data) {
            for index in 0 ..< 3 {
                if let scene = saved[String(index)], scene.doc.isWellFormed,
                   scene.outputRaw.count == 3, scene.micGain.count == 2, scene.lineGainHalf.count == 2 {
                    scenes[index] = scene
                }
            }
        }
    }

    func attach(_ probe: ProbeModel) {
        self.probe = probe
    }

    private func save() {
        if let data = try? JSONEncoder().encode(doc) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Input names and colours

    func label(of input: MixInput) -> InputLabel {
        inputLabels[input.rawValue]
    }

    private func saveLabels() {
        if let data = try? JSONEncoder().encode(inputLabels) {
            UserDefaults.standard.set(data, forKey: Self.labelsKey)
        }
    }

    func setName(_ name: String, of input: MixInput) {
        inputLabels[input.rawValue].name = String(name.prefix(InputLabel.maxLength))
        saveLabels()
    }

    func setColor(_ color: StripColor, of input: MixInput) {
        inputLabels[input.rawValue].color = color
        saveLabels()
    }

    // MARK: Sending, at most about twenty-five updates per second for each control

    private func queue(_ key: String, _ messages: [[UInt8]]) {
        pending[key] = messages
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 40_000_000)
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        let batch = pending
        pending.removeAll()
        guard let probe else { return }
        for (_, messages) in batch {
            for message in messages { probe.send(message) }
        }
    }

    private func hold(_ key: String, _ value: Double) {
        holds[key] = (value, Date().addingTimeInterval(1.0))
        objectWillChange.send()
    }

    private func held(_ key: String) -> Double? {
        guard let entry = holds[key], entry.until > Date() else { return nil }
        return entry.value
    }

    // MARK: Mix cells

    func cell(_ pair: MixPair, in output: MixOutput) -> MixCell {
        doc.cells[output.rawValue][pair.rawValue]
    }

    private func level(of cell: MixCell) -> UInt32 {
        (cell.muted || MixScale.isOff(cell.dB)) ? 0 : BabyfaceCodec.mixerLevel(dB: cell.dB)
    }

    /// Level of one hardware cell, as this mix wants it.
    /// On OUT 1 and OUT 2, which are mono, both sides of a pair are added.
    /// On PHONES the pair stays stereo: left to the left ear, right to the right ear.
    /// Every other source, the four inputs among them, is off: inputs go to the iPad only.
    private func wantedLevel(hardwareSource: Int, cellOutput: Int, output: MixOutput) -> UInt32 {
        for pair in MixPair.allCases {
            let entry = cell(pair, in: output)
            let value = level(of: entry)
            if hardwareSource == pair.leftSource {
                if output == .phones { return cellOutput == 2 ? value : 0 }
                return entry.mode == .right ? 0 : value
            }
            if hardwareSource == pair.rightSource {
                if output == .phones { return cellOutput == 3 ? value : 0 }
                return entry.mode == .left ? 0 : value
            }
        }
        return 0
    }

    /// On a mono output: both sides added, the left side alone, or the right side alone.
    func cycleMode(_ pair: MixPair) {
        let output = selectedOutput
        guard output != .phones else { return }
        doc.cells[output.rawValue][pair.rawValue].mode = cell(pair, in: output).mode.next
        save()
        queue("cell.\(output.rawValue).\(pair.rawValue)", cellMessages(pair, in: output))
    }

    private func cellMessages(_ pair: MixPair, in output: MixOutput) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        for cellOutput in output.cellOutputs {
            for hardwareSource in [pair.leftSource, pair.rightSource] {
                let value = wantedLevel(hardwareSource: hardwareSource, cellOutput: cellOutput, output: output)
                if let message = BabyfaceCodec.setMixer(output: cellOutput, source: hardwareSource, level: value) {
                    messages.append(message)
                }
            }
        }
        return messages
    }

    /// Moves a fader of the mix on screen. Moving the fader of a muted cell releases the mute.
    func setFader(_ pair: MixPair, dB: Double) {
        let output = selectedOutput
        let clamped = min(max(dB, MixScale.floorDB), MixScale.topDB)
        doc.cells[output.rawValue][pair.rawValue].dB = clamped
        doc.cells[output.rawValue][pair.rawValue].muted = false
        save()
        queue("cell.\(output.rawValue).\(pair.rawValue)", cellMessages(pair, in: output))
    }

    /// Mute of one pair in the mix on screen only. The level is kept and comes back on the second press.
    func toggleMute(_ pair: MixPair) {
        let output = selectedOutput
        doc.cells[output.rawValue][pair.rawValue].muted.toggle()
        save()
        queue("cell.\(output.rawValue).\(pair.rawValue)", cellMessages(pair, in: output))
    }

    // MARK: Input filters

    func lowCut(_ input: MixInput) -> Bool { doc.lowCut[input.rawValue] }
    func highCut(_ input: MixInput) -> Bool { doc.highCut[input.rawValue] }

    /// The rate the iPad runs the unit at. The filter coefficients depend on it.
    private func sampleRate() -> Double {
        let rate = AVAudioSession.sharedInstance().sampleRate
        return (rate >= 32_000 && rate <= 192_000) ? rate : 48_000
    }

    private func filterMessage(_ input: MixInput) -> [UInt8]? {
        BabyfaceCodec.setInputFilters(input: input.rawValue, lowCut: lowCut(input), highCut: highCut(input), sampleRate: sampleRate())
    }

    private func sendFilters(_ input: MixInput) {
        guard let message = filterMessage(input) else { return }
        queue("filter.\(input.rawValue)", [message])
        probe?.note(String(format: "FILTER %@: low cut %@, high cut %@, computed for %.0f Hz",
                           input.title, lowCut(input) ? "on" : "off", highCut(input) ? "on" : "off", sampleRate()))
    }

    func toggleLowCut(_ input: MixInput) {
        doc.lowCut[input.rawValue].toggle()
        save()
        sendFilters(input)
    }

    func toggleHighCut(_ input: MixInput) {
        doc.highCut[input.rawValue].toggle()
        save()
        sendFilters(input)
    }

    /// Sends every cell of the three outputs, with zero for every source this mix does not use,
    /// so that nothing set by another app is left in these outputs.
    func sendFullMix() {
        guard let probe, !sendingFullMix else { return }
        sendingFullMix = true
        var messages: [[UInt8]] = []
        for output in MixOutput.allCases {
            for cellOutput in output.cellOutputs {
                for hardwareSource in 0 ..< 24 {
                    let value = wantedLevel(hardwareSource: hardwareSource, cellOutput: cellOutput, output: output)
                    if let message = BabyfaceCodec.setMixer(output: cellOutput, source: hardwareSource, level: value) {
                        messages.append(message)
                    }
                }
            }
        }
        for input in MixInput.allCases {
            if let message = filterMessage(input) { messages.append(message) }
        }
        Task { @MainActor [weak self] in
            var ok = true
            for message in messages {
                if !probe.send(message) { ok = false }
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
            self?.sendingFullMix = false
            self?.fullMixSent = ok
            probe.note("MIX: full mix sent, \(messages.count) messages\(ok ? "" : ", WITH ERRORS")")
        }
    }

    // MARK: Scenes

    private func saveScenes() {
        var stored: [String: MixScene] = [:]
        for index in 0 ..< 3 {
            if let scene = scenes[index] { stored[String(index)] = scene }
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.scenesKey)
        }
    }

    /// Stores the mix on screen together with the levels, gains and input settings the unit reports now.
    func saveScene(_ index: Int) {
        guard (0 ..< 3).contains(index), let probe, let state = probe.state else { return }
        let scene = MixScene(
            doc: doc,
            outputRaw: [
                outputRaw(.out1) ?? state.mainRaw.left,
                outputRaw(.out2) ?? state.mainRaw.right,
                outputRaw(.phones) ?? state.phonesRaw.left,
            ],
            micGain: [micGain(0) ?? state.micGainDB.one, micGain(1) ?? state.micGainDB.two],
            lineGainHalf: [state.lineGainHalfDB.three, state.lineGainHalfDB.four],
            settings: state.settings,
            savedAt: Date()
        )
        scenes[index] = scene
        saveScenes()
        activeScene = index
        probe.note("SCENE \(index + 1) saved")
    }

    /// Inputs (0 or 1) on which this scene would switch 48V on while it is off now.
    func phantomSwitchOns(for index: Int) -> [Int] {
        guard (0 ..< 3).contains(index), let scene = scenes[index], let state = probe?.state else { return [] }
        return [BabyfaceCodec.bitPhantom1, BabyfaceCodec.bitPhantom2].filter { bit in
            (scene.settings >> bit) & 1 == 1 && !state.setting(bit)
        }
    }

    /// Recalls a scene. If it would switch 48V on, it first waits for a confirmation.
    func requestRecall(_ index: Int) {
        guard (0 ..< 3).contains(index), scenes[index] != nil else { return }
        if phantomSwitchOns(for: index).isEmpty {
            recallScene(index, allowPhantomOn: true)
        } else {
            sceneAwaitingPhantomConfirm = index
        }
    }

    /// Sends everything the scene holds. With allowPhantomOn false, 48V is never switched on
    /// (it may still be switched off).
    func recallScene(_ index: Int, allowPhantomOn: Bool) {
        guard (0 ..< 3).contains(index), let probe, let scene = scenes[index] else { return }
        doc = scene.doc
        save()
        activeScene = index
        sendFullMix()
        for input in 0 ..< 2 {
            setMicGain(input, dB: scene.micGain[input])
            setLineGain(input, dB: Double(scene.lineGainHalf[input]) / 2.0)
        }
        for output in MixOutput.allCases {
            let raw = min(max(scene.outputRaw[output.rawValue], 0), BabyfaceCodec.outputUnityRaw)
            writeOutput(output, raw: raw)
        }
        if let state = probe.state {
            let labels = ["48V input 1", "48V input 2", "+4 dBu reference IN 3", "+4 dBu reference IN 4", "Pad IN 1", "Pad IN 2"]
            for bit in 0 ..< 6 {
                let wanted = (scene.settings >> bit) & 1 == 1
                if state.setting(bit) == wanted { continue }
                if bit <= BabyfaceCodec.bitPhantom2 && wanted && !allowPhantomOn { continue }
                probe.enqueueInputSetting(bit: bit, on: wanted, label: labels[bit])
            }
        }
        probe.note("SCENE \(index + 1) recalled\(allowPhantomOn ? "" : ", 48V not switched on")")
    }

    /// Called each time the unit starts answering. Nothing is sent by itself, so that settings made
    /// in another app are never overwritten without being asked. LOAD sends a scene.
    func unitBecameAvailable() {
        fullMixSent = false
    }

    // MARK: Meters

    /// The louder side of a pair.
    func pairPeak(_ pair: MixPair) -> Double? {
        guard let peaks = probe?.peaks, pair.rightSource < peaks.all.count else { return nil }
        let values = [peaks.all[pair.leftSource], peaks.all[pair.rightSource]].compactMap { $0 }
        return values.max()
    }

    func outputPeak(_ output: MixOutput) -> Double? {
        guard let peaks = probe?.peaks else { return nil }
        switch output {
        case .out1: return peaks.main[0]
        case .out2: return peaks.main[1]
        case .phones:
            let values = peaks.phones.compactMap { $0 }
            return values.max()
        }
    }

    // MARK: Output levels (read from the unit, written by this app)

    private func outputRaw(_ output: MixOutput) -> Int? {
        if let value = held("out.\(output.rawValue)") { return Int(value) }
        guard let state = probe?.state else { return nil }
        switch output {
        case .out1: return state.mainRaw.left
        case .out2: return state.mainRaw.right
        case .phones: return state.phonesRaw.left
        }
    }

    func isOutputMuted(_ output: MixOutput) -> Bool {
        guard let raw = outputRaw(output) else { return false }
        return raw <= 62
    }

    /// Level of an output in dB, nil while the unit has not answered yet.
    func outputDB(_ output: MixOutput) -> Double? {
        guard let raw = outputRaw(output) else { return nil }
        return max(BabyfaceCodec.outputDB(raw: raw), MixScale.floorDB)
    }

    private func writeOutput(_ output: MixOutput, raw: Int) {
        hold("out.\(output.rawValue)", Double(raw))
        let messages = output.levelChannels.compactMap { BabyfaceCodec.setLevel(channel: $0, value: raw) }
        queue("out.\(output.rawValue)", messages)
    }

    func setOutputDB(_ output: MixOutput, dB: Double) {
        let clamped = min(max(dB, MixScale.floorDB), MixScale.topDB)
        doc.outputMemoryDB[output.rawValue] = clamped
        save()
        writeOutput(output, raw: BabyfaceCodec.outputRaw(dB: clamped))
    }

    /// Mutes an output the way TotalMix FX does, by level, and keeps the value to return to.
    func toggleOutputMute(_ output: MixOutput) {
        if isOutputMuted(output) {
            writeOutput(output, raw: BabyfaceCodec.outputRaw(dB: doc.outputMemoryDB[output.rawValue]))
        } else {
            if let current = outputDB(output) {
                doc.outputMemoryDB[output.rawValue] = current
                save()
            }
            writeOutput(output, raw: BabyfaceCodec.outputMuteRaw)
        }
    }

    // MARK: Input gains (read from the unit, written by this app)

    /// Gain of microphone input 1 or 2 (index 0 or 1) in dB.
    func micGain(_ index: Int) -> Int? {
        if let value = held("mic.\(index)") { return Int(value) }
        guard let state = probe?.state else { return nil }
        return index == 0 ? state.micGainDB.one : state.micGainDB.two
    }

    func setMicGain(_ index: Int, dB: Int) {
        let clamped = min(max(dB, 0), 65)
        hold("mic.\(index)", Double(clamped))
        let channel = index == 0 ? BabyfaceCodec.channelMic1 : BabyfaceCodec.channelMic2
        if let message = BabyfaceCodec.setLevel(channel: channel, value: BabyfaceCodec.packMicGain(clamped)) {
            queue("mic.\(index)", [message])
        }
    }

    /// Gain of line input 3 or 4 (index 0 or 1) in dB, 0 to 9 in half-dB steps.
    func lineGain(_ index: Int) -> Double? {
        if let value = held("line.\(index)") { return value }
        guard let state = probe?.state else { return nil }
        let steps = index == 0 ? state.lineGainHalfDB.three : state.lineGainHalfDB.four
        return Double(steps) / 2.0
    }

    func setLineGain(_ index: Int, dB: Double) {
        let clamped = min(max(dB, 0), 9)
        let steps = Int((clamped * 2).rounded())
        hold("line.\(index)", Double(steps) / 2.0)
        let channel = index == 0 ? BabyfaceCodec.channelLine3 : BabyfaceCodec.channelLine4
        if let message = BabyfaceCodec.setLevel(channel: channel, value: steps) {
            queue("line.\(index)", [message])
        }
    }
}
