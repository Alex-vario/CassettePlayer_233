import Foundation
import AVFoundation

struct AudioTrack: Identifiable, Hashable {
    let id = UUID()
    let url: URL

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    var artist: String = ""
    var album: String = ""
    var bitrate: Int = 0
    var artwork: Data? = nil

    static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}