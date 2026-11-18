import Foundation
import CoreMIDI

/// One CoreMIDI source or destination.
nonisolated struct MIDIEndpointInfo: Identifiable, Hashable, Sendable {
    let ref: MIDIEndpointRef
    let name: String
    var id: MIDIEndpointRef { ref }
}

/// Thin CoreMIDI wrapper: lists endpoints, receives complete SysEx messages from one source,
/// and sends complete SysEx messages to one destination.
nonisolated final class MIDIEngine: @unchecked Sendable {

    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0

    /// Bytes of the SysEx being received. Touched only on the CoreMIDI receive thread.
    private var sysexBuffer: [UInt8] = []

    /// Called on a CoreMIDI thread with one complete SysEx, F0 ... F7.
    var onSysEx: (@Sendable ([UInt8]) -> Void)?
    /// Called on a CoreMIDI thread when devices appear or disappear.
    var onSetupChanged: (@Sendable () -> Void)?

    private(set) var startError: String?

    init() {
        var status = MIDIClientCreateWithBlock("BabyfaceProbe" as CFString, &client) { [weak self] _ in
            self?.onSetupChanged?()
        }
        if status != noErr { startError = "MIDIClientCreate failed (\(status))"; return }

        status = MIDIInputPortCreateWithProtocol(client, "BabyfaceProbe In" as CFString, ._1_0, &inPort) { [weak self] eventList, _ in
            self?.receive(eventList)
        }
        if status != noErr { startError = "Input port failed (\(status))"; return }

        status = MIDIOutputPortCreate(client, "BabyfaceProbe Out" as CFString, &outPort)
        if status != noErr { startError = "Output port failed (\(status))" }
    }

    // MARK: Endpoints

    func sources() -> [MIDIEndpointInfo] {
        (0 ..< MIDIGetNumberOfSources()).compactMap { i in
            let ref = MIDIGetSource(i)
            return ref == 0 ? nil : MIDIEndpointInfo(ref: ref, name: Self.displayName(ref))
        }
    }

    func destinations() -> [MIDIEndpointInfo] {
        (0 ..< MIDIGetNumberOfDestinations()).compactMap { i in
            let ref = MIDIGetDestination(i)
            return ref == 0 ? nil : MIDIEndpointInfo(ref: ref, name: Self.displayName(ref))
        }
    }

    private static func displayName(_ ref: MIDIEndpointRef) -> String {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &unmanaged)
        if status == noErr, let cf = unmanaged?.takeRetainedValue() {
            return cf as String
        }
        return "Endpoint \(ref)"
    }

    /// Listens to one source and stops listening to the previous one. Pass 0 to listen to nothing.
    func listen(to source: MIDIEndpointRef) {
        if connectedSource != 0 {
            MIDIPortDisconnectSource(inPort, connectedSource)
            connectedSource = 0
        }
        guard source != 0 else { return }
        if MIDIPortConnectSource(inPort, source, nil) == noErr {
            connectedSource = source
        }
    }

    // MARK: Send

    /// Sends one complete SysEx (F0 ... F7) as Universal MIDI Packets inside a single event packet,
    /// so the whole message is handed to CoreMIDI in one piece.
    @discardableResult
    func sendSysEx(_ message: [UInt8], to destination: MIDIEndpointRef) -> OSStatus {
        guard destination != 0, message.count >= 2, message.first == 0xF0, message.last == 0xF7 else { return -1 }
        let payload = Array(message[1 ..< message.count - 1])
        guard payload.allSatisfy({ $0 < 0x80 }) else { return -1 }

        var chunks: [[UInt8]] = []
        var index = 0
        while index < payload.count {
            let end = min(index + 6, payload.count)
            chunks.append(Array(payload[index ..< end]))
            index = end
        }
        if chunks.isEmpty { chunks = [[]] }
        guard chunks.count * 2 <= 64 else { return -1 }

        var words: [UInt32] = []
        for (n, chunk) in chunks.enumerated() {
            // SysEx7 status: 0 complete, 1 start, 2 continue, 3 end.
            let status: UInt32
            if chunks.count == 1 { status = 0 }
            else if n == 0 { status = 1 }
            else if n == chunks.count - 1 { status = 3 }
            else { status = 2 }
            var b = chunk
            while b.count < 6 { b.append(0) }
            let w0: UInt32 = (0x3 << 28) | (status << 20) | (UInt32(chunk.count) << 16) | (UInt32(b[0]) << 8) | UInt32(b[1])
            let w1: UInt32 = (UInt32(b[2]) << 24) | (UInt32(b[3]) << 16) | (UInt32(b[4]) << 8) | UInt32(b[5])
            words.append(w0)
            words.append(w1)
        }

        var list = MIDIEventList()
        let first = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, first, 0, words.count, words)
        return MIDISendEventList(outPort, destination, &list)
    }

    /// Sends F0 00 20 0D 10 10 F7. Changes nothing on the unit.
    @discardableResult
    func sendStateRequest(to destination: MIDIEndpointRef) -> OSStatus {
        sendSysEx(BabyfaceCodec.requestState, to: destination)
    }

    // MARK: Receive

    private func receive(_ eventList: UnsafePointer<MIDIEventList>) {
        let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words) ?? 12
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            guard count > 0, count <= 64 else { continue }
            let wordPointer = UnsafeRawPointer(packet).advanced(by: wordsOffset).assumingMemoryBound(to: UInt32.self)
            var i = 0
            while i < count {
                let word = wordPointer[i]
                let messageType = word >> 28
                let size = Self.packetSize(messageType: messageType)
                if messageType == 0x3, i + 1 < count {
                    handleSysEx7(word, wordPointer[i + 1])
                }
                i += size
            }
        }
    }

    /// Number of 32-bit words of a Universal MIDI Packet, by message type.
    private static func packetSize(messageType: UInt32) -> Int {
        switch messageType {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4
        }
    }

    private func handleSysEx7(_ w0: UInt32, _ w1: UInt32) {
        let status = (w0 >> 20) & 0xF      // 0 complete, 1 start, 2 continue, 3 end
        let byteCount = min(Int((w0 >> 16) & 0xF), 6)
        let all: [UInt8] = [
            UInt8((w0 >> 8) & 0xFF), UInt8(w0 & 0xFF),
            UInt8((w1 >> 24) & 0xFF), UInt8((w1 >> 16) & 0xFF), UInt8((w1 >> 8) & 0xFF), UInt8(w1 & 0xFF),
        ]
        let bytes = all.prefix(byteCount)

        switch status {
        case 0:
            onSysEx?([0xF0] + bytes + [0xF7])
            sysexBuffer.removeAll(keepingCapacity: true)
        case 1:
            sysexBuffer = [0xF0] + bytes
        case 2:
            if !sysexBuffer.isEmpty { sysexBuffer.append(contentsOf: bytes) }
        case 3:
            if !sysexBuffer.isEmpty {
                sysexBuffer.append(contentsOf: bytes)
                sysexBuffer.append(0xF7)
                onSysEx?(sysexBuffer)
            }
            sysexBuffer.removeAll(keepingCapacity: true)
        default:
            break
        }
    }
}
