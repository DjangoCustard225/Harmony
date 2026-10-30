import Foundation
import Observation
import UIKit
import CryptoKit
import HarmonyCore

@MainActor
@Observable
final class ArtistProfileStore {
    private struct Entry: Codable {
        let profile: ArtistProfile?
        let fetched: Date
        let providerVersion: Int?
    }
    private static let providerVersion = 2
    private var entries: [String: Entry] = [:]
    private var errors: [String: String] = [:]
    private(set) var revision = UUID()
    @ObservationIgnored private let client = ArtistProfileClient()
    @ObservationIgnored private var tasks: [String: Task<ArtistProfile?, Never>] = [:]
    @ObservationIgnored private var photoTasks: [String: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private let images = NSCache<NSString, UIImage>()
    @ObservationIgnored private let directory: URL?

    init() {
        directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("ArtistProfiles", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: directory.appendingPathComponent("Profiles.json")),
                let saved = try? JSONDecoder().decode([String: Entry].self, from: data)
            {
                for entry in saved.values {
                    if let profile = entry.profile, let url = profile.photoURL,
                        profile.musicServiceSourcesOnly?.photoURL != url
                    {
                        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }
                            .joined()
                        try? FileManager.default.removeItem(at: directory.appendingPathComponent(key + ".image"))
                    }
                }
                entries = saved.mapValues {
                    Entry(
                        profile: $0.profile?.musicServiceSourcesOnly, fetched: $0.fetched,
                        providerVersion: $0.providerVersion)
                }
                persist()
            }
        }
        images.totalCostLimit = 30 * 1024 * 1024
    }
    private func persist() {
        if let directory, let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: directory.appendingPathComponent("Profiles.json"), options: .atomic)
        }
    }
    private func key(for artist: Artist) -> String { ArtistProfileClient.normalized(artist.name) }
    func cached(_ artist: Artist) -> ArtistProfile? { entries[key(for: artist)]?.profile }
    func error(_ artist: Artist) -> String? { errors[key(for: artist)] }

    func load(_ artist: Artist, musicBrainzID: String?, force: Bool = false) async -> ArtistProfile? {
        let key = key(for: artist)
        guard UserDefaults.standard.object(forKey: "artistDetailsEnabled") as? Bool != false else { return nil }
        if !force, let entry = entries[key], entry.providerVersion == Self.providerVersion,
            Date().timeIntervalSince(entry.fetched) < (entry.profile == nil ? 86400 : 604800)
        {
            return entry.profile
        }
        if let task = tasks[key] { return await task.value }
        errors[key] = nil
        let task = Task<ArtistProfile?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                let profile = try await client.profile(name: artist.name, musicBrainzID: musicBrainzID)
                entries[key] = Entry(profile: profile, fetched: Date(), providerVersion: Self.providerVersion)
                persist()
                return profile
            } catch {
                errors[key] = "Artist details couldn’t load. Check your connection and try again."
                return entries[key]?.profile
            }
        }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil
        if force { revision = UUID() }
        return result
    }

    func photo(_ profile: ArtistProfile) async -> UIImage? {
        guard let url = profile.photoURL else { return nil }
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        if let image = images.object(forKey: key as NSString) { return image }
        if let task = photoTasks[key] { return await task.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            let file = directory?.appendingPathComponent(key + ".image")
            let data: Data
            if let file, let saved = try? Data(contentsOf: file) {
                data = saved
            } else {
                guard UserDefaults.standard.object(forKey: "artistDetailsEnabled") as? Bool != false else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue("Harmony/1.0 (https://github.com/DjangoCustard225)", forHTTPHeaderField: "User-Agent")
                guard let (downloaded, response) = try? await URLSession.shared.data(for: request),
                    let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                    downloaded.count <= 16 * 1024 * 1024, UIImage(data: downloaded) != nil
                else { return nil }
                data = downloaded
                if let file { try? data.write(to: file, options: .atomic) }
            }
            guard let source = UIImage(data: data) else { return nil }
            let image = await source.byPreparingThumbnail(ofSize: CGSize(width: 1200, height: 1200)) ?? source
            images.setObject(
                image, forKey: key as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
            return image
        }
        photoTasks[key] = task
        let result = await task.value
        photoTasks[key] = nil
        return result
    }
}

extension AppStore {
    func musicBrainzID(for artist: Artist) -> String? {
        for track in library?.index.tracks ?? [] where track.song.artistId == artist.id {
            let value = track.metadata?.values("MUSICBRAINZ_ALBUMARTISTID", "MUSICBRAINZ_ARTISTID").first
            if let value, let id = UUID(uuidString: value) { return id.uuidString.lowercased() }
        }
        return nil
    }
}
