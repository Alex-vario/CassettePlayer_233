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

        if track.artwork == nil,
           url.pathExtension.lowercased() == "flac" {
            track.artwork = readFLACArtwork(from: url)
        }

        return track
    }

    /// Reads FLAC PICTURE metadata without loading the complete audio file.
    private static func readFLACArtwork(from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let signature = try? handle.read(upToCount: 4),
              signature == Data("fLaC".utf8) else {
            return nil
        }

        while true {
            guard let header = try? handle.read(upToCount: 4),
                  header.count == 4 else {
                return nil
            }

            let bytes = [UInt8](header)
            let isLastBlock = (bytes[0] & 0x80) != 0
            let blockType = bytes[0] & 0x7F
            let blockLength =
                (Int(bytes[1]) << 16)
                | (Int(bytes[2]) << 8)
                | Int(bytes[3])

            if blockType == 6 {
                guard let block = try? handle.read(upToCount: blockLength),
                      block.count == blockLength else {
                    return nil
                }
                return imageData(fromFLACPictureBlock: block)
            }

            do {
                try handle.seek(toOffset: handle.offsetInFile + UInt64(blockLength))
            } catch {
                return nil
            }

            if isLastBlock {
                return nil
            }
        }
    }

    /// Extracts the image bytes from a FLAC PICTURE metadata block.
    private static func imageData(fromFLACPictureBlock block: Data) -> Data? {
        let bytes = [UInt8](block)
        var offset = 0

        func readUInt32() -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            let value =
                (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
            offset += 4
            return value
        }

        guard readUInt32() != nil,
              let mimeLength = readUInt32(),
              Int(mimeLength) <= bytes.count - offset else {
            return nil
        }
        offset += Int(mimeLength)

        guard let descriptionLength = readUInt32(),
              Int(descriptionLength) <= bytes.count - offset else {
            return nil
        }
        offset += Int(descriptionLength)

        // Image dimensions, bit depth, and indexed-color count.
        guard offset + 16 <= bytes.count else {
            return nil
        }
        offset += 16

        guard let imageLength = readUInt32(),
              imageLength > 0,
              Int(imageLength) <= bytes.count - offset else {
            return nil
        }

        return Data(bytes[offset..<(offset + Int(imageLength))])
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
