import SwiftUI
import CoreMIDI

/// Raw view of the connection: ports, state as read, meters as numbers, log.
struct DiagnosticsView: View {
    @ObservedObject var model: ProbeModel
    @State private var confirmPhantom = false
    @State private var phantomTarget = false

    var body: some View {
        Form {
                Section("MIDI ports (control runs on Port 2)") {
                    Picker("Source (from unit)", selection: $model.selectedSource) {
                        Text("None").tag(MIDIEndpointRef(0))
                        ForEach(model.sources) { Text($0.name).tag($0.ref) }
                    }
                    Picker("Destination (to unit)", selection: $model.selectedDestination) {
                        Text("None").tag(MIDIEndpointRef(0))
                        ForEach(model.destinations) { Text($0.name).tag($0.ref) }
                    }
                    Button("Refresh ports") { model.refreshEndpoints() }
                }

                Section("Read") {
                    Button("Read state once") { model.requestState() }
                    Toggle("Poll 4 times per second", isOn: $model.polling)
                    row("Requests sent", "\(model.requestsSent)")
                    row("Replies (state / RMS / peaks)", "\(model.stateReplies) / \(model.rmsReplies) / \(model.peakReplies)")
                    if model.otherMessages > 0 { row("Other messages", "\(model.otherMessages)") }
                }

                if let s = model.state {
                    Section("Outputs") {
                        row("Level OUT 1 / OUT 2", "\(level(s.mainRaw.left)) / \(level(s.mainRaw.right))")
                        row("Level Phones L / R", "\(level(s.phonesRaw.left)) / \(level(s.phonesRaw.right))")
                        row("AS 1 / 2", "\(level(s.asRaw.one)) / \(level(s.asRaw.two))")
                        row("Dim", s.dim ? "on" : "off")
                    }
                    Section("Inputs") {
                        row("Mic gain 1 / 2", "\(s.micGainDB.one) dB / \(s.micGainDB.two) dB")
                        row("Line gain 3 / 4", "\(halfDB(s.lineGainHalfDB.three)) / \(halfDB(s.lineGainHalfDB.four))")
                        row("Pad 1 / 2", "\(onOff(s.pad.one)) / \(onOff(s.pad.two))")
                        row("Line 3 / 4 sensitivity", "\(sens(s.lineSensitivityPlus4.three)) / \(sens(s.lineSensitivityPlus4.four))")
                        row("48V 1 / 2 (unverified bits)", "\(onOff(s.phantom.one)) / \(onOff(s.phantom.two))")
                    }
                    Section("Write test: 48V on input 2") {
                        row("48V input 2 now", onOff(s.phantom.two))
                        Button(s.phantom.two ? "Switch 48V input 2 OFF" : "Switch 48V input 2 ON") {
                            phantomTarget = !s.phantom.two
                            confirmPhantom = true
                        }
                        .disabled(model.writeInProgress)
                        if !model.writeStatus.isEmpty {
                            Text(model.writeStatus).font(.callout)
                        }
                    }
                } else {
                    Section("State") {
                        Text("No state received yet.").foregroundStyle(.secondary)
                    }
                }

                if let p = model.peaks {
                    Section("Peak meters (dBFS, peak since previous request)") {
                        row("In 1 / 2", "\(meter(p.inputs[0])) / \(meter(p.inputs[1]))")
                        row("In 3 / 4", "\(meter(p.inputs[2])) / \(meter(p.inputs[3]))")
                        row("Playback 1 / 2", "\(meter(p.playback[0])) / \(meter(p.playback[1]))")
                        row("Playback 3 / 4", "\(meter(p.playback[2])) / \(meter(p.playback[3]))")
                        row("Signal OUT 1 / OUT 2", "\(meter(p.main[0])) / \(meter(p.main[1]))")
                        row("Signal Phones L / R", "\(meter(p.phones[0])) / \(meter(p.phones[1]))")
                    }
                }

                Section("Log") {
                    Button("Clear log") { model.clearLog() }
                        .disabled(model.log.isEmpty)
                    if model.log.isEmpty {
                        Text("Empty").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Diagnostics \(ProbeVersion.current)")
            .toolbar(.visible, for: .navigationBar)
            .alert("Switch 48V on input 2 \(phantomTarget ? "ON" : "OFF")?", isPresented: $confirmPhantom) {
                Button("Cancel", role: .cancel) {}
                Button(phantomTarget ? "Switch ON" : "Switch OFF") { model.setInputSetting(bit: BabyfaceCodec.bitPhantom2, on: phantomTarget, label: "48V input 2") }
            } message: {
                Text("Only the 48V bit of input 2 changes. All other input settings are sent back as read.")
            }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func level(_ raw: Int) -> String {
        if raw <= 62 { return "silent (raw \(raw))" }
        return String(format: "%+.1f dB", BabyfaceCodec.outputDB(raw: raw))
    }

    private func halfDB(_ steps: Int) -> String { String(format: "%.1f dB", Double(steps) / 2.0) }
    private func onOff(_ value: Bool) -> String { value ? "on" : "off" }
    private func sens(_ plus4: Bool) -> String { plus4 ? "+4 dBu" : "-10 dBV" }
    private func meter(_ db: Double?) -> String {
        guard let db else { return "-inf" }
        return String(format: "%.1f", db)
    }
}
