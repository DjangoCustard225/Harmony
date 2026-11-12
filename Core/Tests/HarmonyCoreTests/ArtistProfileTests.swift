import XCTest
@testable import HarmonyCore
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class ArtistProfileTests: XCTestCase {
    func testAudioDBReadsCurrentBiographyAndActualArtistPhoto() throws {
        let data = Data(
            #"{"artists":[{"idArtist":"123","strArtist":"Benny Blanco","strBiography":"<p>Producer &amp; songwriter.</p><script>bad()</script><p>Biography.</p>","strArtistThumb":"https://r2.theaudiodb.com/artist.jpg"}]}"#
                .utf8)
        let profile = try XCTUnwrap(ArtistProfileClient.audioDBProfile(data, name: "benny blanco"))
        XCTAssertEqual(profile.name, "Benny Blanco")
        XCTAssertEqual(profile.biography, "Producer & songwriter.\n\nBiography.")
        XCTAssertEqual(profile.photoURL?.absoluteString, "https://r2.theaudiodb.com/artist.jpg")
        XCTAssertEqual(profile.biographyCredit?.url.absoluteString, "https://www.theaudiodb.com/artist/123")
        XCTAssertEqual(profile.photoCredit?.name, "TheAudioDB")
    }
    func testBiographyEntitiesDecodeOnceIncludingNumericForms() throws {
        let data = Data(
            #"{"artists":[{"idArtist":"1","strArtist":"A","strBiography":"&lt;3 &amp;lt;b&amp;gt; &#233;&#x41; &#39;x&apos; &bogus; & end&amp;"}]}"#
                .utf8)
        let profile = try XCTUnwrap(ArtistProfileClient.audioDBProfile(data, name: "A"))
        XCTAssertEqual(profile.biography, "<3 &lt;b&gt; éA 'x' &bogus; & end&")
    }
    func testAudioDBSupportsLegacyBiographyAndRejectsWrongIdentity() throws {
        let data = Data(
            #"{"artists":[{"idArtist":"123","strArtist":"Björk","strBiographyEN":"Singer.","strMusicBrainzID":"id-one","strArtistThumb":"http://example.org/photo.jpg"}]}"#
                .utf8)
        XCTAssertNil(try ArtistProfileClient.audioDBProfile(data, name: "Other artist"))
        XCTAssertNil(try ArtistProfileClient.audioDBProfile(data, name: "Björk", musicBrainzID: "id-two"))
        let profile = try XCTUnwrap(ArtistProfileClient.audioDBProfile(data, name: " bjork ", musicBrainzID: "id-one"))
        XCTAssertEqual(profile.biography, "Singer.")
        XCTAssertNil(profile.photoURL)
        XCTAssertNil(try ArtistProfileClient.audioDBProfile(Data(#"{"artists":null}"#.utf8), name: "Nobody"))
    }
    func testDeezerMatchesNamesAndPrefersTheMostPopularNamesake() throws {
        let data = Data(
            #"{"data":[{"id":1,"name":"Benny Blanco","nb_fan":2},{"id":2,"name":"Benny Blanco","nb_fan":200},{"id":3,"name":"Benny Blanco & Other","nb_fan":1000}]}"#
                .utf8)
        XCTAssertEqual(try ArtistProfileClient.deezerArtist(data, name: "benny blanco")?.id, 2)
        XCTAssertNil(try ArtistProfileClient.deezerArtist(data, name: "Unrelated"))
        XCTAssertThrowsError(try ArtistProfileClient.deezerArtist(Data(#"{"error":{"code":4}}"#.utf8), name: "Test"))
    }
    func testDeezerBiographyAndErrors() throws {
        let data = Data(
            #"{"data":{"artist":{"bio":{"full":"<p>Producer &amp; songwriter.</p><p>Another paragraph.</p>"}}}}"#.utf8)
        XCTAssertEqual(try ArtistProfileClient.deezerBiography(data), "Producer & songwriter.\n\nAnother paragraph.")
        XCTAssertNil(try ArtistProfileClient.deezerBiography(Data(#"{"data":{"artist":{"bio":null}}}"#.utf8)))
        XCTAssertThrowsError(
            try ArtistProfileClient.deezerBiography(Data(#"{"errors":[{"message":"Unavailable"}]}"#.utf8)))
    }
    func testLegacyCacheDropsUnsupportedSourcesButRetainsAudioDBFields() throws {
        let old = ArtistProfile(
            name: "Test", biography: "Old biography",
            biographyCredit: ArtistProfileCredit(
                name: "Wikipedia", url: URL(string: "https://en.wikipedia.org/wiki/Test")!),
            photoURL: URL(string: "https://r2.theaudiodb.com/photo.jpg")!,
            photoCredit: ArtistProfileCredit(
                name: "TheAudioDB", url: URL(string: "https://www.theaudiodb.com/artist/1")!))
        let retained = try XCTUnwrap(old.musicServiceSourcesOnly)
        XCTAssertNil(retained.biography)
        XCTAssertEqual(retained.photoURL, old.photoURL)
        let unsupported = ArtistProfile(name: "Test", biography: "Old", biographyCredit: old.biographyCredit)
        XCTAssertNil(unsupported.musicServiceSourcesOnly)
    }
    func testCompleteDeezerProfileDoesNotContactFallback() async throws {
        let client = mockClient(biography: "Primary biography", primaryPhoto: true)
        let profile = try await client.profile(name: "Test")
        XCTAssertEqual(profile?.biography, "Primary biography")
        XCTAssertEqual(profile?.photoCredit?.name, "Deezer")
        XCTAssertFalse(ProfileProtocol.requests.contains { $0.url?.host == "www.theaudiodb.com" })
        XCTAssertEqual(ProfileProtocol.requests.first?.url?.host, "api.deezer.com")
    }
    func testFallbackFillsOnlyMissingFieldsWithoutReplacingDeezerPhoto() async throws {
        let client = mockClient(biography: nil, primaryPhoto: true)
        let profile = try await client.profile(name: "Test")
        XCTAssertEqual(profile?.biography, "Fallback biography")
        XCTAssertEqual(profile?.biographyCredit?.name, "TheAudioDB")
        XCTAssertEqual(profile?.photoURL?.host, "cdn-images.dzcdn.net")
        XCTAssertEqual(profile?.photoCredit?.name, "Deezer")
        XCTAssertTrue(ProfileProtocol.requests.contains { $0.url?.host == "www.theaudiodb.com" })
    }
    func testFallbackFillsMissingPhotoAndHandlesDeezerFailure() async throws {
        var client = mockClient(biography: "Primary biography", primaryPhoto: false)
        var profile = try await client.profile(name: "Test")
        XCTAssertEqual(profile?.biographyCredit?.name, "Deezer")
        XCTAssertEqual(profile?.photoCredit?.name, "TheAudioDB")
        client = mockClient(biography: nil, primaryPhoto: false, failPrimary: true)
        profile = try await client.profile(name: "Test")
        XCTAssertEqual(profile?.biography, "Fallback biography")
        XCTAssertEqual(profile?.photoCredit?.name, "TheAudioDB")
    }
    func testDeezerPlaceholderPhotoUsesFallback() async throws {
        let client = mockClient(biography: "Primary biography", primaryPhoto: true, placeholder: true)
        let profile = try await client.profile(name: "Test")
        XCTAssertEqual(profile?.photoCredit?.name, "TheAudioDB")
    }
    func testLiveDeezerFixtures() throws {
        let env = ProcessInfo.processInfo.environment
        guard let search = env["HARMONY_DEEZER_FIXTURE"], let biography = env["HARMONY_DEEZER_BIO_FIXTURE"] else {
            throw XCTSkip("Set saved Deezer search and biography fixtures")
        }
        let artist = try XCTUnwrap(
            ArtistProfileClient.deezerArtist(Data(contentsOf: URL(fileURLWithPath: search)), name: "benny blanco"))
        XCTAssertEqual(artist.id, 1547598)
        XCTAssertTrue(
            try XCTUnwrap(ArtistProfileClient.deezerBiography(Data(contentsOf: URL(fileURLWithPath: biography)))).count
                > 100)
    }

    private func mockClient(
        biography: String?, primaryPhoto: Bool, failPrimary: Bool = false, placeholder: Bool = false
    ) -> ArtistProfileClient {
        ProfileProtocol.configure { request in
            switch request.url?.host {
            case "api.deezer.com":
                if failPrimary { return (503, Data("{}".utf8)) }
                let photo =
                    placeholder
                    ? "https://cdn-images.dzcdn.net/images/artist//1000x1000.jpg"
                    : "https://cdn-images.dzcdn.net/artist.jpg"
                let record: [String: Any] = [
                    "id": 12, "name": "Test", "nb_fan": 100, "picture_xl": primaryPhoto ? photo : "",
                ]
                return (200, try! JSONSerialization.data(withJSONObject: ["data": [record]]))
            case "auth.deezer.com":
                let claims = try! JSONSerialization.data(withJSONObject: [
                    "exp": Date().addingTimeInterval(3600).timeIntervalSince1970
                ])
                let token =
                    "header." + claims.base64EncodedString().replacingOccurrences(of: "=", with: "") + ".signature"
                return (200, try! JSONSerialization.data(withJSONObject: ["jwt": token]))
            case "pipe.deezer.com":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
                return (
                    200,
                    try! JSONSerialization.data(withJSONObject: ["data": ["artist": ["bio": ["full": biography ?? ""]]]]
                    )
                )
            case "www.theaudiodb.com":
                return (
                    200,
                    Data(
                        #"{"artists":[{"idArtist":"123","strArtist":"Test","strBiography":"Fallback biography","strArtistThumb":"https://r2.theaudiodb.com/fallback.jpg"}]}"#
                            .utf8)
                )
            default:
                XCTFail("Unexpected provider host")
                return (500, Data("{}".utf8))
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProfileProtocol.self]
        return ArtistProfileClient(session: URLSession(configuration: config))
    }
    func testUnknownArtistDoesNotContactProviders() async throws {
        let client = ArtistProfileClient()
        let profile = try await client.profile(name: "Unknown artist")
        XCTAssertNil(profile)
    }
    func testLiveArtistFixture() throws {
        guard let path = ProcessInfo.processInfo.environment["HARMONY_ARTIST_FIXTURE"] else {
            throw XCTSkip("Set HARMONY_ARTIST_FIXTURE to a saved TheAudioDB response")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let profile = try XCTUnwrap(ArtistProfileClient.audioDBProfile(data, name: "benny blanco"))
        XCTAssertTrue(profile.biography?.isEmpty == false)
        XCTAssertNotNil(profile.photoURL)
        XCTAssertEqual(profile.name.lowercased(), "benny blanco")
        let restored = try JSONDecoder().decode(ArtistProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored.biography, profile.biography)
        XCTAssertEqual(restored.photoURL, profile.photoURL)
        XCTAssertEqual(restored.photoCredit?.url, profile.photoCredit?.url)
    }
}

private final class ProfileProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, Data))?
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    static func configure(_ handler: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let handler = Self.handler
        Self.lock.unlock()
        let (status, data) = handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
