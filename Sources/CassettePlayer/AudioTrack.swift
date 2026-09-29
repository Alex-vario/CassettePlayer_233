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
    }

    static func load(from url: URL) async -> AudioTrack {
        var track = AudioTrack(url: url)
        let asset = AVURLAsset(url: url)

        do {
            for item in try await asset.load(.commonMetadata) {
                switch item.commonKey {
                case .commonKeyArtist:
                    track.artist =
                        (try? await item.load(.stringValue)) ?? ""

                case .commonKeyAlbumName:
                    track.album =
                        (try? await item.load(.stringValue)) ?? ""

                case .commonKeyArtwork:
                    track.artwork =
                        try? await item.load(.dataValue)

                default:
                    continue
                }
            }
        } catch {
            // Metadata is optional; the track remains playable without it.
        }

        return track
    }

    static func loadAll(from urls: [URL]) async -> [AudioTrack] {
        var tracks: [AudioTrack] = []
        tracks.reserveCapacity(urls.count)

        for url in urls {
            tracks.append(await load(from: url))
        }

        return tracks
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
