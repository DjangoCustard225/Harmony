import AVFoundation
import HarmonyCore

@MainActor
enum LocalMetadataReader {
    static let version = 1
    static func read(_ url: URL) async throws -> TrackMetadata {
        var result =
            try await Task.detached(priority: .utility) { try FLACMetadata.read(from: url) }.value ?? TrackMetadata()
        result.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let asset = AVURLAsset(url: url)
        if result.duration == nil, let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            result.duration = seconds
        }
        if result.sampleRate == nil, let track = try? await asset.loadTracks(withMediaType: .audio).first,
            let descriptions = try? await track.load(.formatDescriptions), let format = descriptions.first,
            let audio = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        {
            result.sampleRate = Int(audio.mSampleRate)
            result.channels = Int(audio.mChannelsPerFrame)
            if audio.mBitsPerChannel > 0 { result.bitsPerSample = Int(audio.mBitsPerChannel) }
        }
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        metadata += (try? await asset.load(.metadata)) ?? []
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            metadata += (try? await asset.loadMetadata(for: format)) ?? []
        }
        let identifiers: [AVMetadataIdentifier: String] = [
            .commonIdentifierTitle: "TITLE", .iTunesMetadataSongName: "TITLE", .id3MetadataTitleDescription: "TITLE",
            .commonIdentifierArtist: "ARTIST", .iTunesMetadataArtist: "ARTIST", .id3MetadataLeadPerformer: "ARTIST",
            .commonIdentifierAlbumName: "ALBUM", .iTunesMetadataAlbum: "ALBUM", .id3MetadataAlbumTitle: "ALBUM",
            .iTunesMetadataAlbumArtist: "ALBUMARTIST", .id3MetadataBand: "ALBUMARTIST",
            .iTunesMetadataTrackNumber: "TRACKNUMBER", .id3MetadataTrackNumber: "TRACKNUMBER",
            .iTunesMetadataDiscNumber: "DISCNUMBER", .id3MetadataPartOfASet: "DISCNUMBER",
            .iTunesMetadataLyrics: "LYRICS", .id3MetadataUnsynchronizedLyric: "LYRICS",
            .commonIdentifierCreationDate: "DATE", .iTunesMetadataReleaseDate: "DATE",
            .iTunesMetadataUserGenre: "GENRE", .iTunesMetadataUserComment: "COMMENT",
            .iTunesMetadataEncodedBy: "ENCODEDBY", .iTunesMetadataEncodingTool: "ENCODER",
            .id3MetadataRecordingTime: "DATE", .id3MetadataYear: "YEAR",
            .id3MetadataContentType: "GENRE", .id3MetadataComposer: "COMPOSER", .iTunesMetadataComposer: "COMPOSER",
            .commonIdentifierCopyrights: "COPYRIGHT", .iTunesMetadataCopyright: "COPYRIGHT",
            .id3MetadataCopyright: "COPYRIGHT",
            .iTunesMetadataPublisher: "PUBLISHER", .id3MetadataPublisher: "PUBLISHER", .id3MetadataComments: "COMMENT",
        ]
        var native = TrackMetadata()
        for item in metadata {
            if item.commonKey == .commonKeyArtwork || item.identifier == .iTunesMetadataCoverArt
                || item.identifier == .id3MetadataAttachedPicture
            {
                continue
            }
            let identifier = item.identifier
            let rawKey =
                identifier?.rawValue ?? item.commonKey?.rawValue ?? String(describing: item.key ?? "tag" as NSString)
            let key = identifier.flatMap { identifiers[$0] } ?? rawKey
            if let text = try? await item.load(.stringValue), !text.isEmpty {
                native.append(text, for: key)
                if key != rawKey { native.append(text, for: rawKey) }
            } else if key == "TRACKNUMBER" || key == "DISCNUMBER",
                let data = try? await item.load(.dataValue), data.count >= 6
            {
                let value = Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
                let total = Int(data[data.startIndex + 4]) << 8 | Int(data[data.startIndex + 5])
                if value > 0 { native.append(String(value), for: key) }
                if total > 0 { native.append(String(total), for: key == "TRACKNUMBER" ? "TRACKTOTAL" : "DISCTOTAL") }
            } else if let number = try? await item.load(.numberValue) {
                native.append(number.stringValue, for: key)
            }
        }
        if native.lyrics == nil, let lyrics = try? await asset.load(.lyrics) { native.append(lyrics, for: "LYRICS") }
        for (key, values) in native.tags where result.text(key) == nil {
            for value in values { result.append(value, for: key) }
        }
        return result
    }
}
