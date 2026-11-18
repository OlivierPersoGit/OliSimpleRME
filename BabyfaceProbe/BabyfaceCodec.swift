import Foundation

// RME Babyface Pro FS, class-compliant mode: SysEx codec.
// Message layout follows the public-domain protocol reference at
// github.com/ultracello/loopy-pro-rme-interface-control (docs/protocol).
// This file builds and parses bytes. It sends nothing.

nonisolated enum BabyfaceCodec {

    /// F0, RME manufacturer ID 00 20 0D, device ID 10.
    static let header: [UInt8] = [0xF0, 0x00, 0x20, 0x0D, 0x10]

    // Sub IDs, unit to host
    static let subState: UInt8 = 0x00
    static let subRMS: UInt8 = 0x01
    static let subPeaks: UInt8 = 0x02

    // Sub IDs, host to unit
    static let subMixer: UInt8 = 0x01
    static let subInputSettings: UInt8 = 0x03
    static let subLevels: UInt8 = 0x04
    static let subEQ: UInt8 = 0x06
    static let subRequest: UInt8 = 0x10

    /// "Request state". The unit answers with sub ID 00, 01 and 02. Changes nothing on the unit.
    static let requestState: [UInt8] = [0xF0, 0x00, 0x20, 0x0D, 0x10, 0x10, 0xF7]

    static let meterFullScale: Double = Double(0x0800_0000)

    // MARK: Framing

    /// Splits one complete SysEx into its sub ID and its 32-bit words.
    /// Each word travels as five 7-bit bytes, least significant bits first.
    static func parseFrame(_ data: [UInt8]) -> (subID: UInt8, words: [UInt32])? {
        guard data.count >= 7,
              Array(data.prefix(5)) == header,
              data.last == 0xF7,
              (data.count - 7) % 5 == 0 else { return nil }
        let body = Array(data[6 ..< data.count - 1])
        var words: [UInt32] = []
        words.reserveCapacity(body.count / 5)
        var i = 0
        while i + 5 <= body.count {
            var word: UInt32 = 0
            for k in 0 ..< 5 {
                let b = body[i + k]
                if b > 0x7F { return nil }
                word |= UInt32(b & 0x7F) << UInt32(7 * k)   // the fifth byte's upper bits fall off, as intended
            }
            words.append(word)
            i += 5
        }
        return (data[5], words)
    }

    /// One 32-bit word as five 7-bit bytes, bits 0-6 first.
    static func packWord(_ word: UInt32) -> [UInt8] {
        (0 ..< 5).map { UInt8((word >> UInt32(7 * $0)) & 0x7F) }
    }

    static func frame(subID: UInt8, words: [UInt32]) -> [UInt8] {
        header + [subID] + words.flatMap { packWord($0) } + [0xF7]
    }

    // MARK: Input settings (sub ID 03)

    /// Bit numbers of the input settings (state word 0, bits 0-5).
    static let bitPhantom1 = 0
    static let bitPhantom2 = 1
    static let bitSens3 = 2      // set = +4 dBu, clear = -10 dBV
    static let bitSens4 = 3
    static let bitPad1 = 4
    static let bitPad2 = 5

    /// Switches one input setting. The message says which bit changes (bits 0-15) and carries the
    /// complete new state of all six settings (bits 16-30), so the others go back exactly as read.
    static func setInputSetting(bit: Int, on: Bool, currentSettings: Int) -> [UInt8]? {
        guard (0 ..< 6).contains(bit), currentSettings & ~0x3F == 0 else { return nil }
        let new = on ? (currentSettings | (1 << bit)) : (currentSettings & ~(1 << bit))
        let word = UInt32(1 << bit) | (UInt32(new) << 16)
        return frame(subID: subInputSettings, words: [word])
    }

    // MARK: Levels and gains (sub ID 04)

    /// Channels of the level message.
    static let channelMic1 = 0
    static let channelMic2 = 1
    static let channelLine3 = 2
    static let channelLine4 = 3
    static let channelMainLeft = 4      // XLR output 1
    static let channelMainRight = 5     // XLR output 2
    static let channelPhonesLeft = 6
    static let channelPhonesRight = 7

    /// The value TotalMix FX writes for a muted output. Raw 62 and below is silence.
    static let outputMuteRaw = 59
    static let outputUnityRaw = 243

    /// One word: bits 0-15 channel, bits 16-23 value.
    static func setLevel(channel: Int, value: Int) -> [UInt8]? {
        guard (0 ... 15).contains(channel), (0 ... 255).contains(value) else { return nil }
        return frame(subID: subLevels, words: [UInt32(channel) | (UInt32(value) << 16)])
    }

    /// Microphone gain 0 ... 65 dB as the unit wants it written. The state reports the plain dB number.
    static func packMicGain(_ dB: Int) -> Int {
        let g = min(max(dB, 0), 65)
        return g < 60 ? ((g % 3) << 5) | (g / 3) : ((g % 6) << 5) | 20
    }

    /// Output level: raw 243 = 0 dB, half a dB per step. Raw 62 and below is silence.
    static func outputDB(raw: Int) -> Double {
        Double(raw - outputUnityRaw) / 2.0
    }

    /// Raw output level for a value in dB, capped at 0 dB.
    static func outputRaw(dB: Double) -> Int {
        let raw = Int((Double(outputUnityRaw) + 2.0 * dB).rounded())
        return min(max(raw, 0), outputUnityRaw)
    }

    // MARK: Mixer (sub ID 01)

    /// Linear level of a mixer cell for 0 dB. 0 is off.
    static let mixerUnity: UInt32 = 0x20000

    /// Level of a mixer cell for a gain in dB. nil is off. Capped at 0 dB here.
    static func mixerLevel(dB: Double?) -> UInt32 {
        guard let dB else { return 0 }
        let capped = min(dB, 0)
        return UInt32((Double(mixerUnity) * pow(10.0, capped / 20.0)).rounded())
    }

    /// One mixer cell: what one source sends to one output. Cell index = 26 x output + source.
    /// Outputs 0-1 XLR 1/2, 2-3 Phones. Sources 0-3 inputs 1-4, 12-23 playback 1-12.
    static func setMixer(output: Int, source: Int, level: UInt32) -> [UInt8]? {
        guard (0 ... 11).contains(output), (0 ... 23).contains(source), level <= mixerUnity else { return nil }
        let word = UInt32(26 * output + source) | (level << 12)
        return frame(subID: subMixer, words: [word])
    }

    // MARK: Low cut and high cut of an input (sub ID 06, the equaliser message)

    /// A coefficient as signed 5.27 fixed point in a 32-bit word. 1.0 is 0x08000000.
    static func fixed527(_ x: Double) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64((x * 134_217_728.0).rounded()))
    }

    /// A second-order low pass as the unit wants a band: a1/a0, a2/a0, b1/b0, b2/b0, and its gain b0/a0.
    static func lowPassBand(frequency: Double, q: Double, sampleRate: Double)
        -> (a1: Double, a2: Double, b1: Double, b2: Double, gain: Double) {
        let w = 2.0 * Double.pi * frequency / sampleRate
        let cw = cos(w)
        let alpha = sin(w) / (2.0 * q)
        let b0 = (1.0 - cw) / 2.0
        let b1 = 1.0 - cw
        let b2 = b0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cw
        let a2 = 1.0 - alpha
        return (a1 / a0, a2 / a0, b1 / b0, b2 / b0, b0 / a0)
    }

    /// The word of the low cut, 1 - k, with k solved so that the -3 dB point lies at the frequency asked for.
    /// The unit applies k(1 - z^-1) / (1 - k z^-1) once per pole.
    static func lowCutCoefficient(frequency: Double, poles: Int, sampleRate: Double) -> Double? {
        guard (1 ... 4).contains(poles) else { return nil }
        let g2 = pow(2.0, -1.0 / Double(poles))
        let cw = cos(2.0 * Double.pi * frequency / sampleRate)
        let a = 2.0 * (1.0 - cw) - g2
        let b = 2.0 * g2 * cw
        let c = -g2
        let discriminant = b * b - 4.0 * a * c
        guard discriminant >= 0, abs(a) > 1e-12 else { return nil }
        let root = discriminant.squareRoot()
        let candidates = [(-b + root) / (2.0 * a), (-b - root) / (2.0 * a)].filter { $0 > 0 && $0 < 1 }
        guard candidates.count == 1 else { return nil }
        return 1.0 - candidates[0]
    }

    static let lowCutFrequency: Double = 80
    static let lowCutPoles = 2                 // 12 dB per octave
    static let highCutFrequency: Double = 10_000

    /// Low cut and high cut of hardware input 0 ... 3, sixteen words, to be sent in one piece.
    /// Each input uses the slot of its own number. With both off the equaliser of the input is switched off.
    /// The coefficients are right for the sample rate given; the unit runs at the rate the iPad sets.
    static func setInputFilters(input: Int, lowCut: Bool, highCut: Bool, sampleRate: Double) -> [UInt8]? {
        guard (0 ... 3).contains(input), sampleRate >= 32_000 else { return nil }
        var control = UInt32(input) | (UInt32(input) << 16)        // slot, channel; bit 20 clear = input
        var lowCutWord: UInt32 = 0
        if lowCut {
            guard let coefficient = lowCutCoefficient(frequency: lowCutFrequency, poles: lowCutPoles, sampleRate: sampleRate) else { return nil }
            control |= UInt32((1 << lowCutPoles) - 1) << 8
            lowCutWord = fixed527(coefficient)
        }
        var band3: [UInt32] = [0, 0, 0, 0]
        var gain = 1.0
        if highCut {
            let band = lowPassBand(frequency: highCutFrequency, q: 0.707, sampleRate: sampleRate)
            band3 = [fixed527(band.a1), fixed527(band.a2), fixed527(band.b1), fixed527(band.b2)]
            gain = band.gain
        }
        if lowCut || highCut { control |= 1 << 31 }
        var words: [UInt32] = [control]
        words.append(contentsOf: [0, 0, 0, 0])      // band 1, flat
        words.append(contentsOf: [0, 0, 0, 0])      // band 2, flat
        words.append(contentsOf: band3)
        words.append(fixed527(gain))
        words.append(lowCutWord)
        words.append(0)
        return frame(subID: subEQ, words: words)
    }

    // MARK: Meters

    static func meterDBFS(_ word: UInt32) -> Double? {
        word == 0 ? nil : 20.0 * log10(Double(word) / meterFullScale)
    }
}

/// The fields of the state message (sub ID 00, 44 words).
nonisolated struct BabyfaceState: Sendable {
    var mainRaw: (left: Int, right: Int)
    var phonesRaw: (left: Int, right: Int)
    var asRaw: (one: Int, two: Int)
    var micGainDB: (one: Int, two: Int)
    var lineGainHalfDB: (three: Int, four: Int)
    var phantom: (one: Bool, two: Bool)
    var lineSensitivityPlus4: (three: Bool, four: Bool)
    var pad: (one: Bool, two: Bool)
    var dim: Bool
    /// The six input setting bits exactly as the unit reports them.
    var settings: Int
    var encoderCounter: Int
    var words: [UInt32]

    init?(words w: [UInt32]) {
        guard w.count == 44 else { return nil }
        let settings = w[0] & 0x3F
        self.settings = Int(settings)
        mainRaw = (Int(w[1] & 0xFF), Int((w[1] >> 9) & 0xFF))
        micGainDB = (Int(w[2] & 0x7F), Int((w[2] >> 7) & 0x7F))
        phonesRaw = (Int((w[2] >> 14) & 0xFF), Int((w[2] >> 23) & 0xFF))
        asRaw = (Int(w[3] & 0xFF), Int((w[3] >> 9) & 0xFF))
        lineGainHalfDB = (Int((w[3] >> 19) & 0x1F), Int((w[3] >> 24) & 0x1F))
        phantom = (settings & 1 != 0, settings & 2 != 0)
        lineSensitivityPlus4 = (settings & 4 != 0, settings & 8 != 0)
        pad = (settings & 16 != 0, settings & 32 != 0)
        dim = w[0] & (1 << 13) != 0
        encoderCounter = Int((w[0] >> 16) & 0xF)
        words = w
    }

    func setting(_ bit: Int) -> Bool {
        (settings >> bit) & 1 == 1
    }
}

/// Peak meters (sub ID 02, 40 words). Each answer carries the peak since the previous request.
nonisolated struct BabyfacePeaks: Sendable {
    /// All forty meters in dBFS, nil for silence. 0-3 inputs 1-4, 12-23 playback 1-12,
    /// 26-27 XLR outputs 1/2, 28-29 Phones left/right.
    var all: [Double?]
    var inputs: [Double?]      // inputs 1-4
    var playback: [Double?]    // playback 1-4
    var main: [Double?]        // XLR output 1, 2
    var phones: [Double?]      // Phones left, right

    init?(words w: [UInt32]) {
        guard w.count == 40 else { return nil }
        let db = w.map { BabyfaceCodec.meterDBFS($0) }
        all = db
        inputs = Array(db[0 ..< 4])
        playback = Array(db[12 ..< 16])
        main = Array(db[26 ..< 28])
        phones = Array(db[28 ..< 30])
    }
}
