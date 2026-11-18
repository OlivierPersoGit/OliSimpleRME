import SwiftUI

@main struct MyApp: App {
    @StateObject private var probe = ProbeModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MixerView(probe: probe, mixer: probe.mixer)
            }
            .preferredColorScheme(.dark)
        }
    }
}
