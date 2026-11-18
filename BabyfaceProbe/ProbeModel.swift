import Foundation
import Combine
import CoreMIDI

/// Connection to the Babyface: ports, polling, state, meters, and the guarded write of input settings.
@MainActor
final class ProbeModel: ObservableObject {

    @Published var sources: [MIDIEndpointInfo] = []
    @Published var destinations: [MIDIEndpointInfo] = []
    @Published var selectedSource: MIDIEndpointRef = 0 {
        didSet {
            engine.listen(to: selectedSource)
            remember(selectedSource, in: sources, key: Self.sourceNameKey)
        }
    }
    @Published var selectedDestination: MIDIEndpointRef = 0 {
        didSet { remember(selectedDestination, in: destinations, key: Self.destinationNameKey) }
    }

    @Published var state: BabyfaceState?
    @Published var peaks: BabyfacePeaks?
    /// Peak of each of the four inputs, held and falling slowly, in dBFS. nil is silence.
    @Published var inputHold: [Double?] = [nil, nil, nil, nil]
    @Published var lastStateAt: Date?
    /// True while the unit keeps answering the state requests.
    @Published var connected = false

    @Published var requestsSent = 0
    @Published var stateReplies = 0
    @Published var rmsReplies = 0
    @Published var peakReplies = 0
    @Published var otherMessages = 0
    @Published var log: [String] = []

    @Published var polling = false { didSet { polling ? startPolling() : stopPolling() } }

    /// Result of the last write of an input setting, shown in the UI.
    @Published var writeStatus = ""
    @Published var writeInProgress = false

    /// The mix this app keeps and sends. The unit does not report its mixer.
    let mixer = MixerStore()

    private enum WriteStage {
        case idle
        case waitingFreshState(bit: Int, target: Bool, label: String)
        case waitingReadback(bit: Int, target: Bool, label: String)
    }
    private var writeStage: WriteStage = .idle
    /// Setting writes waiting for their turn. Each one reads, writes one bit and reads back.
    private var settingQueue: [(bit: Int, target: Bool, label: String)] = []
    private var writeGeneration = 0
    /// State replies that were already on their way when the write went out are ignored until this time.
    private var readbackNotBefore = Date.distantPast

    private let engine = MIDIEngine()
    private var timer: Timer?

    private static let sourceNameKey = "port.source.name"
    private static let destinationNameKey = "port.destination.name"

    init() {
        if let error = engine.startError { append("ERROR: \(error)") }
        engine.onSysEx = { [weak self] bytes in
            Task { @MainActor [weak self] in self?.handle(bytes) }
        }
        engine.onSetupChanged = { [weak self] in
            Task { @MainActor [weak self] in self?.refreshEndpoints() }
        }
        mixer.attach(self)
        refreshEndpoints()
    }

    // MARK: Ports

    func refreshEndpoints() {
        sources = engine.sources()
        destinations = engine.destinations()
        if !sources.contains(where: { $0.ref == selectedSource }) {
            selectedSource = Self.pickControlPort(sources, rememberedKey: Self.sourceNameKey)?.ref ?? 0
        }
        if !destinations.contains(where: { $0.ref == selectedDestination }) {
            selectedDestination = Self.pickControlPort(destinations, rememberedKey: Self.destinationNameKey)?.ref ?? 0
        }
    }

    /// The port chosen by hand last time wins. Otherwise: control runs on the unit's second MIDI port ("Port 2").
    private static func pickControlPort(_ list: [MIDIEndpointInfo], rememberedKey: String) -> MIDIEndpointInfo? {
        if let name = UserDefaults.standard.string(forKey: rememberedKey),
           let match = list.first(where: { $0.name == name }) {
            return match
        }
        let babyface = list.filter { $0.name.localizedCaseInsensitiveContains("babyface") }
        if let port2 = babyface.first(where: { $0.name.localizedCaseInsensitiveContains("port 2") }) { return port2 }
        if let second = babyface.first(where: { $0.name.hasSuffix("2") }) { return second }
        if babyface.count >= 2 { return babyface[1] }
        return nil
    }

    private func remember(_ ref: MIDIEndpointRef, in list: [MIDIEndpointInfo], key: String) {
        guard ref != 0, let info = list.first(where: { $0.ref == ref }) else { return }
        UserDefaults.standard.set(info.name, forKey: key)
    }

    // MARK: Sending

    /// Sends one complete SysEx to the selected destination.
    @discardableResult
    func send(_ message: [UInt8]) -> Bool {
        guard selectedDestination != 0 else { return false }
        return engine.sendSysEx(message, to: selectedDestination) == noErr
    }

    func requestState() {
        if let last = lastStateAt {
            let alive = Date().timeIntervalSince(last) < 1.5
            if connected != alive { connected = alive }
        }
        guard selectedDestination != 0 else {
            if connected { connected = false }
            return
        }
        let status = engine.sendStateRequest(to: selectedDestination)
        if status == noErr {
            requestsSent += 1
        } else {
            append("Send failed (\(status))")
        }
    }

    private func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestState() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Input settings (48V, pad, line sensitivity)

    /// Reads a fresh state, changes only one setting bit, then reads back and compares.
    /// Every other setting is sent back exactly as read.
    func setInputSetting(bit: Int, on target: Bool, label: String) {
        guard !writeInProgress else { return }
        guard selectedDestination != 0 else {
            writeStatus = "No destination selected"
            return
        }
        writeInProgress = true
        writeGeneration += 1
        writeStage = .waitingFreshState(bit: bit, target: target, label: label)
        writeStatus = "Reading state before the write..."
        requestState()
        armWriteTimeout("No state reply. Nothing was written.")
    }

    /// Like setInputSetting, but several can be asked for at once. They run one after the other.
    func enqueueInputSetting(bit: Int, on target: Bool, label: String) {
        settingQueue.append((bit, target, label))
        startNextSetting()
    }

    private func startNextSetting() {
        guard !writeInProgress, !settingQueue.isEmpty else { return }
        let next = settingQueue.removeFirst()
        setInputSetting(bit: next.bit, on: next.target, label: next.label)
    }

    private func armWriteTimeout(_ message: String) {
        let generation = writeGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.writeInProgress, self.writeGeneration == generation else { return }
            self.writeStage = .idle
            self.writeInProgress = false
            self.writeStatus = message
            self.append("WRITE: \(message)")
            self.startNextSetting()
        }
    }

    private func continueWrite(with fresh: BabyfaceState) {
        switch writeStage {
        case .idle:
            return

        case .waitingFreshState(let bit, let target, let label):
            if fresh.setting(bit) == target {
                finishWrite("\(label) already \(target ? "on" : "off"). Nothing was written.")
                return
            }
            guard let message = BabyfaceCodec.setInputSetting(bit: bit, on: target, currentSettings: fresh.settings) else {
                finishWrite("Could not build the message. Nothing was written.")
                return
            }
            let sent = send(message)
            append("WRITE sent (settings were \(String(format: "%02X", fresh.settings))): \(Self.hex(message))")
            guard sent else {
                finishWrite("Send failed.")
                return
            }
            writeGeneration += 1
            writeStage = .waitingReadback(bit: bit, target: target, label: label)
            readbackNotBefore = Date().addingTimeInterval(0.12)
            writeStatus = "Written. Reading back..."
            let generation = writeGeneration
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self, self.writeGeneration == generation else { return }
                self.requestState()
            }
            armWriteTimeout("Written, but no state reply to confirm it.")

        case .waitingReadback(let bit, let target, let label):
            if Date() < readbackNotBefore { return }
            if fresh.setting(bit) == target {
                finishWrite("CONFIRMED by the unit: \(label) is \(target ? "on" : "off"). Settings now \(String(format: "%02X", fresh.settings)).")
            } else {
                finishWrite("NOT confirmed: the unit still reports \(label) \(fresh.setting(bit) ? "on" : "off").")
            }
        }
    }

    private func finishWrite(_ message: String) {
        writeGeneration += 1
        writeStage = .idle
        writeInProgress = false
        writeStatus = message
        append("WRITE: \(message)")
        startNextSetting()
    }

    // MARK: Receiving

    private func handle(_ bytes: [UInt8]) {
        guard let frame = BabyfaceCodec.parseFrame(bytes) else {
            otherMessages += 1
            append("Unknown SysEx, \(bytes.count) bytes: \(Self.hex(bytes.prefix(12)))")
            return
        }
        switch frame.subID {
        case BabyfaceCodec.subState:
            if let parsed = BabyfaceState(words: frame.words) {
                let first = state == nil
                state = parsed
                lastStateAt = Date()
                let cameBack = !connected
                if cameBack { connected = true }
                stateReplies += 1
                continueWrite(with: parsed)
                if cameBack { mixer.unitBecameAvailable() }
                if first || !polling {
                    append("State, \(bytes.count) bytes. Words 0-3: " +
                           parsed.words.prefix(4).map { String(format: "%08X", $0) }.joined(separator: " "))
                }
            } else {
                otherMessages += 1
                append("Sub ID 00 with \(frame.words.count) words (44 expected), \(bytes.count) bytes: " +
                       frame.words.map { String(format: "%08X", $0) }.joined(separator: " "))
            }
        case BabyfaceCodec.subRMS:
            rmsReplies += 1
        case BabyfaceCodec.subPeaks:
            if let parsed = BabyfacePeaks(words: frame.words) {
                peaks = parsed
                peakReplies += 1
                var held = inputHold
                for index in 0 ..< 4 {
                    let current = parsed.inputs[index] ?? -200
                    let falling = (held[index] ?? -200) - 1.5      // about 6 dB per second
                    let value = max(current, falling)
                    held[index] = value < -90 ? nil : value
                }
                inputHold = held
            } else {
                otherMessages += 1
                append("Sub ID 02 with \(frame.words.count) words (40 expected)")
            }
        default:
            otherMessages += 1
            append(String(format: "Sub ID %02X, %d bytes: ", frame.subID, bytes.count) +
                   frame.words.prefix(8).map { String(format: "%08X", $0) }.joined(separator: " "))
        }
    }

    // MARK: Log

    func clearLog() {
        log.removeAll()
    }

    /// Adds a line to the log from another part of the app.
    func note(_ line: String) {
        append(line)
    }

    private func append(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.insert("\(stamp)  \(line)", at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }

    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
