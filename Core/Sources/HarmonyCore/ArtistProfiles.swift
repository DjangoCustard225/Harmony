import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct ArtistProfileCredit: Codable, Sendable {
    public var name: String
    public var url: URL
    public var author: String?
    public var license: String?
    public var licenseURL: URL?
    public init(name: String, url: URL, author: String? = nil, license: String? = nil, licenseURL: URL? = nil) {
        self.name = name; self.url = url; self.author = author; self.license = license; self.licenseURL = licenseURL
    }
}

public struct ArtistProfile: Codable, Sendable {
    public var name: String
    public var biography: String?
    public var biographyCredit: ArtistProfileCredit?
    public var photoURL: URL?
    public var photoCredit: ArtistProfileCredit?
    public init(
        name: String, biography: String? = nil, biographyCredit: ArtistProfileCredit? = nil,
        photoURL: URL? = nil, photoCredit: ArtistProfileCredit? = nil
    ) {
        self.name = name; self.biography = biography; self.biographyCredit = biographyCredit
        self.photoURL = photoURL; self.photoCredit = photoCredit
    }
    /// Remove fields from providers that Harmony no longer uses when reading older caches.
    public var musicServiceSourcesOnly: ArtistProfile? {
        let allowed: Set<String> = ["Deezer", "TheAudioDB"]
        var result = self
        if !allowed.contains(biographyCredit?.name ?? "") { result.biography = nil; result.biographyCredit = nil }
        if !allowed.contains(photoCredit?.name ?? "") { result.photoURL = nil; result.photoCredit = nil }
        return result.hasContent ? result : nil
    }
    public var hasContent: Bool { biography != nil || photoURL != nil }
}

/// Music-specific artist profiles, with Deezer preferred over TheAudioDB.
public actor ArtistProfileClient {
    private let session: URLSession
    private var nextAudioDBRequest = Date.distantPast
    private var nextDeezerRequest = Date.distantPast
    private var anonymousToken: String?
    private var tokenExpiration = Date.distantPast
    public init(session: URLSession = .shared) { self.session = session }

    public func profile(name: String, musicBrainzID: String? = nil) async throws -> ArtistProfile? {
        guard !Self.normalized(name).isEmpty, Self.normalized(name) != "unknown artist" else { return nil }
        var profile: ArtistProfile?
        var lookupError: Error?
        do {
            let scheduled = max(Date(), nextDeezerRequest)
            nextDeezerRequest = scheduled.addingTimeInterval(0.25)
            if scheduled > Date() { try await Task.sleep(for: .seconds(scheduled.timeIntervalSinceNow)) }
            try Task.checkCancellation()
            var parts = URLComponents(string: "https://api.deezer.com/search/artist")!
            parts.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "limit", value: "25")]
            if let artist = try Self.deezerArtist(try await request(parts.url!), name: name) {
                profile = artist.profile
                do {
                    let token = try await deezerToken()
                    let body: [String: Any] = [
                        "operationName": "ArtistBio", "variables": ["artistId": String(artist.id)],
                        "query": "query ArtistBio($artistId: String!) { artist(artistId: $artistId) { bio { full } } }",
                    ]
                    let data = try await request(
                        URL(string: "https://pipe.deezer.com/api")!,
                        body: JSONSerialization.data(withJSONObject: body), token: token)
                    if let biography = try Self.deezerBiography(data) {
                        profile?.biography = biography
                        profile?.biographyCredit = artist.credit
                    }
                } catch {
                    try Task.checkCancellation()
                    lookupError = error
                }
            }
        } catch {
            try Task.checkCancellation()
            lookupError = error
        }
        if profile?.biography == nil || profile?.photoURL == nil {
            do {
                let scheduled = max(Date(), nextAudioDBRequest)
                nextAudioDBRequest = scheduled.addingTimeInterval(2.1)  // Free tier: 30 API calls/minute.
                if scheduled > Date() { try await Task.sleep(for: .seconds(scheduled.timeIntervalSinceNow)) }
                try Task.checkCancellation()
                var parts = URLComponents(string: "https://www.theaudiodb.com/api/v1/json/123/search.php")!
                parts.queryItems = [URLQueryItem(name: "s", value: name)]
                let data = try await request(parts.url!)
                if let fallback = try Self.audioDBProfile(data, name: name, musicBrainzID: musicBrainzID) {
                    if profile == nil {
                        profile = fallback
                    } else {
                        if profile?.biography == nil {
                            profile?.biography = fallback.biography; profile?.biographyCredit = fallback.biographyCredit
                        }
                        if profile?.photoURL == nil {
                            profile?.photoURL = fallback.photoURL; profile?.photoCredit = fallback.photoCredit
                        }
                    }
                }
            } catch {
                try Task.checkCancellation()
                if lookupError == nil { lookupError = error }
            }
        }
        if profile?.hasContent == true { return profile }
        if let lookupError { throw lookupError }
        return nil
    }

    private func request(_ url: URL, body: Data? = nil, token: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Harmony/1.0 (https://github.com/DjangoCustard225)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("en", forHTTPHeaderField: "Accept-Language")
        }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 404 { return Data("{}".utf8) }
        guard (200..<300).contains(response.statusCode), data.count <= 4 * 1024 * 1024 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func deezerToken() async throws -> String {
        if let anonymousToken, tokenExpiration > Date() { return anonymousToken }
        struct Response: Decodable { let jwt: String }
        let data = try await request(URL(string: "https://auth.deezer.com/login/anonymous?jo=p&rto=c")!)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let parts = response.jwt.split(separator: ".")
        guard parts.count == 3 else { throw URLError(.badServerResponse) }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let payload = Data(base64Encoded: encoded),
            let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let expiration = claims["exp"] as? Double
        else { throw URLError(.badServerResponse) }
        let expiry = Date(timeIntervalSince1970: expiration - 60)
        guard expiry > Date() else { throw URLError(.badServerResponse) }
        anonymousToken = response.jwt
        tokenExpiration = expiry
        return response.jwt
    }

    public struct DeezerArtist: Decodable, Sendable {
        public let id: Int
        public let name: String
        let nb_fan: Int?
        let picture_xl: String?
        let picture_big: String?
        let picture_medium: String?
        var credit: ArtistProfileCredit {
            ArtistProfileCredit(name: "Deezer", url: URL(string: "https://www.deezer.com/artist/\(id)")!)
        }
        var profile: ArtistProfile {
            let photo = [picture_xl, picture_big, picture_medium].compactMap { ArtistProfileClient.https($0) }
                .first { !$0.absoluteString.contains("/images/artist//") }
            return ArtistProfile(name: name, photoURL: photo, photoCredit: photo == nil ? nil : credit)
        }
    }

    public static func deezerArtist(_ data: Data, name: String) throws -> DeezerArtist? {
        struct Response: Decodable { let data: [DeezerArtist]?; let error: APIError? }
        struct APIError: Decodable { let code: Int? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.error != nil { throw URLError(.badServerResponse) }
        return response.data?.filter { normalized($0.name) == normalized(name) && $0.id > 0 }
            .sorted { a, b in a.nb_fan == b.nb_fan ? a.id < b.id : (a.nb_fan ?? 0) > (b.nb_fan ?? 0) }.first
    }

    public static func deezerBiography(_ data: Data) throws -> String? {
        struct Bio: Decodable { let full: String? }
        struct Artist: Decodable { let bio: Bio? }
        struct Content: Decodable { let artist: Artist? }
        struct Response: Decodable { let data: Content?; let errors: [APIError]? }
        struct APIError: Decodable { let message: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.errors?.isEmpty == false { throw URLError(.badServerResponse) }
        return plain(response.data?.artist?.bio?.full)
    }

    public static func audioDBProfile(_ data: Data, name: String, musicBrainzID: String? = nil) throws -> ArtistProfile?
    {
        struct Envelope: Decodable { var artists: [Record]? }
        struct Record: Decodable {
            var idArtist: String?
            var strArtist: String?
            var strArtistAlternate: String?
            var strBiography: String?
            var strBiographyEN: String?
            var strArtistThumb: String?
            var strArtistWideThumb: String?
            var strMusicBrainzID: String?
        }
        let records = try JSONDecoder().decode(Envelope.self, from: data).artists ?? []
        guard
            let record = records.first(where: { record in
                let names = [record.strArtist ?? ""] + (record.strArtistAlternate ?? "").components(separatedBy: ";")
                guard names.contains(where: { normalized($0) == normalized(name) }) else { return false }
                if let expected = musicBrainzID, let actual = record.strMusicBrainzID, !actual.isEmpty {
                    return expected.lowercased() == actual.lowercased()
                }
                return true
            }), let id = record.idArtist, id.allSatisfy(\.isNumber), !id.isEmpty,
            let source = URL(string: "https://www.theaudiodb.com/artist/" + id)
        else { return nil }
        let photo = https(record.strArtistThumb) ?? https(record.strArtistWideThumb)
        let bio = plain(record.strBiographyEN) ?? plain(record.strBiography)
        let credit = ArtistProfileCredit(name: "TheAudioDB", url: source)
        return ArtistProfile(
            name: record.strArtist ?? name, biography: bio, biographyCredit: bio == nil ? nil : credit,
            photoURL: photo, photoCredit: photo == nil ? nil : credit)
    }

    public static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func https(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }
    private static func plain(_ value: String?) -> String? {
        guard var text = value else { return nil }
        text = text.replacingOccurrences(
            of: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, with: "", options: .regularExpression
        )
        .replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div)>"#, with: "\n\n", options: .regularExpression)
        .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        for (entity, character) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
