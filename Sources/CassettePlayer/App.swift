import SwiftUI

@main
struct CassettePlayerApp: App {

    @StateObject private var audio: AudioPlayer

    private let mediaKeys: MediaKeyManager

    init() {

        let audioPlayer =
            AudioPlayer()

        _audio =
            StateObject(
                wrappedValue: audioPlayer
            )

        mediaKeys =
            MediaKeyManager(
                audioPlayer: audioPlayer
            )

        mediaKeys.start()
    }

    var body: some Scene {

        WindowGroup {

            PlayerView()
                .environmentObject(audio)
        }
        .windowStyle(
            .hiddenTitleBar
        )
    }
}