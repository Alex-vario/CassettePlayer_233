import SwiftUI

@main
struct CassettePlayerApp: App {
    @StateObject private var audio = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .environmentObject(audio)
        }
        .windowStyle(.hiddenTitleBar)
    }
}