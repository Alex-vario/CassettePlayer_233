import Foundation
import AVFoundation

struct AudioTrack: Identifiable, Hashable {

    let id = UUID()
    let url: URL

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    var artist: String
    var album: String
    var bitrate: Int
    var artwork: Data?

    init(url: URL) {

        self.url = url
        self.artist = ""
        self.album = ""
        self.bitrate = 0
        self.artwork = nil

        let asset = AVURLAsset(
            url: url
        )

        for item in asset.commonMetadata {

            if item.commonKey == .commonKeyArtist {
                self.artist =
                    item.stringValue ?? ""
            }

            else if item.commonKey == .commonKeyAlbumName {
                self.album =
                    item.stringValue ?? ""
            }

            else if item.commonKey == .commonKeyArtwork {
                self.artwork =
                    item.dataValue
            }
        }
    }

    static func == (
        lhs: AudioTrack,
        rhs: AudioTrack
    ) -> Bool {
        lhs.url == rhs.url
    }

    func hash(
        into hasher: inout Hasher
    ) {
        hasher.combine(url)
    }
}