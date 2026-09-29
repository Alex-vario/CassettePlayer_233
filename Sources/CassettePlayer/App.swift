import SwiftUI
import AppKit

@main
struct CassettePlayerApp: App {

    @NSApplicationDelegateAdaptor(CassettePlayerAppDelegate.self)
    private var appDelegate

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

private final class CassettePlayerAppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}
