import Foundation

/// Version shown in the app's title. Bump it on every change handed over for a test.
///
/// v0.1  Read only: state request, outputs, inputs, peak meters, log.
/// v0.2  Write test: 48V of input 2, with confirmation and read-back.
/// v0.3  Clear log button; unexpected messages are logged with their content.
/// v0.4  Version number shown in the title.
/// v0.5  Mixer test: IN 1 and PB 1 sent to PHONES with two sliders.
/// v0.6  Mixer screen: strips IN 1-4, PB 1-4, OUT 1, OUT 2, PHONES; one mix per output; mute with memory;
///       input gains, 48V, pad, line reference; meters. The former screen is now "Diagnostics".
/// v0.7  Simpler: inputs are preamp strips with a large meter, no fader and no mute, and go to Loopy Pro only.
///       Playback in two stereo pairs, PB 1/2 and PB 3/4: summed on OUT 1 and OUT 2, stereo on PHONES.
/// v0.8  On a mono output a pair can send both sides, the left only or the right only.
///       Three scenes (mix, output levels, gains, input settings). Scene 1 is recalled at launch.
/// v0.9  No banner: at launch scene 1 (or the last mix) is sent, and the mix is sent again after a reconnection.
///       One top row; strips fill the width in both orientations; longer faders.
/// v0.10 Named OliSimpleRME, with an icon. Nothing is sent at launch any more: pick scene 1, 2 or 3,
///       then LOAD sends it and SAVE stores into it.
/// v0.11 The PLAYBACK block says "not sent yet" until a LOAD has made its faders the real mix.
/// v0.12 Each input has a name (up to 8 letters) and a column colour, set by touching its header.
///       LOW CUT (80 Hz, 12 dB per octave) and HIGH CUT (10 kHz) of the inputs are live.
/// v0.13 Top row reordered: connection and scenes on the left, the three mix buttons on the right above the outputs.
/// v0.14 Each mix button sits exactly above its output column, on two lines when narrow.
///       Touching an output column shows its mix.
/// v0.15 Active buttons of an input column are filled with the colour of that column.
/// v0.16 48V switched on is red in every column, whatever the colour of the column.
nonisolated enum ProbeVersion {
    static let current = "v0.16"
}
