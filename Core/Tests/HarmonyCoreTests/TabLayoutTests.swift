import XCTest
@testable import HarmonyCore

final class TabLayoutTests: XCTestCase {
    func testStandardShowsThreeTabsWithArtistsHidden() {
        let layout = TabLayout.standard
        XCTAssertEqual(layout.visibleTabs, [.albums, .songs, .playlists])
        XCTAssertFalse(layout.isVisible(.artists))
        XCTAssertEqual(layout.storage, "albums,-artists,songs,playlists")
    }

    func testToggleKeepsBetweenOneAndThreeVisible() {
        var layout = TabLayout.standard
        XCTAssertFalse(layout.canToggle(.artists))
        layout.toggle(.artists)
        XCTAssertFalse(layout.isVisible(.artists))

        layout.toggle(.songs)
        layout.toggle(.artists)
        XCTAssertEqual(layout.visibleTabs, [.albums, .artists, .playlists])

        layout.toggle(.albums)
        layout.toggle(.playlists)
        XCTAssertEqual(layout.visibleTabs, [.artists])
        XCTAssertFalse(layout.canToggle(.artists))
        layout.toggle(.artists)
        XCTAssertEqual(layout.visibleTabs, [.artists])
    }

    func testMoveReordersTabsLikeOnMove() {
        var layout = TabLayout.standard
        layout.move(from: [3], to: 0)
        XCTAssertEqual(layout.order, [.playlists, .albums, .artists, .songs])
        layout.move(from: [0, 1], to: 4)
        XCTAssertEqual(layout.order, [.artists, .songs, .playlists, .albums])
        layout.move(from: [9], to: 0)
        XCTAssertEqual(layout.order, [.artists, .songs, .playlists, .albums])
        XCTAssertEqual(layout.visibleTabs, [.songs, .playlists, .albums])
    }

    func testStorageRoundTripsAndRepairsBadValues() {
        var layout = TabLayout.standard
        layout.move(from: [3], to: 0)
        layout.toggle(.songs)
        XCTAssertEqual(TabLayout(storage: layout.storage), layout)

        XCTAssertEqual(TabLayout(storage: ""), .standard)
        XCTAssertEqual(TabLayout(storage: "radio,,-"), .standard)
        // Unknown entries (like the old "settings") and duplicates drop; missing tabs are appended hidden.
        let repaired = TabLayout(storage: "songs,-settings,radio,songs,-albums")
        XCTAssertEqual(repaired.order, [.songs, .albums, .artists, .playlists])
        XCTAssertEqual(repaired.visibleTabs, [.songs])
        // Too many visible keeps the first three; none visible shows the first.
        XCTAssertEqual(
            TabLayout(storage: "playlists,albums,artists,songs").visibleTabs, [.playlists, .albums, .artists])
        XCTAssertEqual(TabLayout(storage: "-playlists,-albums").visibleTabs, [.playlists])
    }
}
