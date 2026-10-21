import Foundation
import AVFoundation

struct AudioTrack: Identifiable, Hashable {

    let id = UUID()
    let url: URL

    var title: String {
        url.deletingPathExtension().lastPathComponent
    }

    var artist: String
    var taggedTitle: String
    var album: String
    var trackNumber: Int?
    var discNumber: Int?
    var bitrate: Int
    var artwork: Data?

    /// Artist names used only for catalog grouping. Original metadata remains untouched.
    var catalogueArtists: [String] {
        let raw = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return ["Неизвестный исполнитель"]
        }

        let separatorPattern = #"(?i)\b(?:featuring|feat\.?|ft\.?)(?=\s|$)|\s*/\s*|\s+&\s+"#
        let expression = try? NSRegularExpression(pattern: separatorPattern)
        let fullRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let hasNamedSeparator = expression?.firstMatch(in: raw, range: fullRange) != nil
        let separated = expression?.stringByReplacingMatches(
            in: raw,
            range: fullRange,
            withTemplate: "|"
        ) ?? raw

        var parts = separated
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Split commas only when they produce exactly two non-empty names.
        if !hasNamedSeparator, parts.count == 1 {
            let commaParts = raw
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if commaParts.count == 2 {
                parts = commaParts
            }
        }

        // Handle compact full-name collaborations such as "Вася Обломов&Андрей Макаревич",
        // but leave one-word band names such as "Simon&Garfunkel" intact.
        parts = parts.flatMap { part -> [String] in
            let ampersandParts = part
                .components(separatedBy: "&")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard ampersandParts.count > 1,
                  ampersandParts.allSatisfy({ $0.split(whereSeparator: \.isWhitespace).count >= 2 }) else {
                return [part]
            }
            return ampersandParts.filter { !$0.isEmpty }
        }

        var seen = Set<String>()
        let unique = parts.filter { name in
            let key = name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return seen.insert(key).inserted
        }
        return unique.isEmpty ? ["Неизвестный исполнитель"] : unique
    }

    init(url: URL) {
        self.url = url
        self.artist = ""
        self.taggedTitle = ""
        self.album = ""
        self.trackNumber = nil
        self.discNumber = nil
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

                case .commonKeyTitle:
                    track.taggedTitle =
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

        // Read track/disc numbers from format-specific AVFoundation metadata where available.
        for format in [AVMetadataFormat.iTunesMetadata, .id3Metadata] {
            if let items = try? await asset.loadMetadata(for: format) {
                for item in items {
                    let key = item.identifier?.rawValue.lowercased() ?? ""
                    let value = (try? await item.load(.stringValue)) ?? ""
                    if track.trackNumber == nil,
                       key.contains("tracknumber") {
                        track.trackNumber = Self.integerTag(value)
                    }
                    if track.discNumber == nil,
                       key.contains("discnumber") || key.contains("partofaset") {
                        track.discNumber = Self.integerTag(value)
                    }
                }
            }
        }

        if url.pathExtension.lowercased() == "flac" {
            // AVFoundation does not consistently expose FLAC Vorbis comments
            // as common metadata, so read the tags directly as a fallback.
            let tags = readFLACVorbisComments(from: url)
            if track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.artist = tags["artist"] ?? tags["album_artist"] ?? ""
            }
            if track.taggedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.taggedTitle = tags["title"] ?? ""
            }
            if track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.album = tags["album"] ?? ""
            }
            if track.trackNumber == nil {
                track.trackNumber = Self.integerTag(tags["tracknumber"] ?? tags["track"])
            }
            if track.discNumber == nil {
                track.discNumber = Self.integerTag(tags["discnumber"] ?? tags["disc"])
            }
            if track.artwork == nil {
                track.artwork = readFLACArtwork(from: url)
            }
        }

        return track
    }

    private static func integerTag(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let first = raw.split(separator: "/", maxSplits: 1).first.map(String.init) ?? raw
        let digits = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(digits)
    }

    /// Reads FLAC Vorbis comments (artist/title/album) directly from the metadata blocks.
    /// This is needed because AVFoundation may omit these tags for FLAC files.
    private static func readFLACVorbisComments(from url: URL) -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }

        guard let signature = try? handle.read(upToCount: 4),
              signature == Data("fLaC".utf8) else { return [:] }

        func readUInt32LE(_ data: Data, at offset: inout Int) -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let bytes = [UInt8](data[offset..<(offset + 4)])
            offset += 4
            return UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
        }

        while true {
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else {
                return [:]
            }
            let bytes = [UInt8](header)
            let isLastBlock = (bytes[0] & 0x80) != 0
            let blockType = bytes[0] & 0x7F
            let blockLength = (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])

            if blockLength < 0 || blockLength > 16 * 1024 * 1024 { return [:] }

            if blockType == 4 {
                guard let block = try? handle.read(upToCount: blockLength),
                      block.count == blockLength else { return [:] }
                var offset = 0
                guard let vendorLength = readUInt32LE(block, at: &offset),
                      vendorLength <= UInt32(block.count - offset) else { return [:] }
                offset += Int(vendorLength)
                guard let count = readUInt32LE(block, at: &offset),
                      count <= 100_000 else { return [:] }

                var result: [String: String] = [:]
                for _ in 0..<count {
                    guard let length = readUInt32LE(block, at: &offset),
                          length <= UInt32(block.count - offset) else { return result }
                    let end = offset + Int(length)
                    let entry = String(decoding: block[offset..<end], as: UTF8.self)
                    offset = end
                    guard let separator = entry.firstIndex(of: "=") else { continue }
                    let key = String(entry[..<separator]).lowercased()
                    let value = String(entry[entry.index(after: separator)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty, result[key] == nil {
                        result[key] = value
                    }
                }
                return result
            }

            do {
                try handle.seek(toOffset: handle.offsetInFile + UInt64(blockLength))
            } catch {
                return [:]
            }
            if isLastBlock { return [:] }
        }
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
