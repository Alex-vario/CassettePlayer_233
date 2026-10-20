import SwiftUI
import AppKit

@main
struct CassettePlayerApp: App {

    @NSApplicationDelegateAdaptor(CassettePlayerAppDelegate.self)
    private var appDelegate

    @StateObject private var audio: AudioPlayer

    private let mediaKeys: MediaKeyManager
    private let remoteServer: HMRemoteServer

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

        let server = HMRemoteServer(audio: audioPlayer)
        remoteServer = server

        mediaKeys.start()
        server.start()
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
