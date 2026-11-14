import Foundation

@main
struct LibraryAndQueueChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LibraryAndQueueChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func song(_ id: String) -> CatalogSong { CatalogSong(id: id, title: "Song \(id)", artist: "Artist", duration: "3:15", thumbnailURL: nil) }

    @MainActor
    static func main() throws {
        let songs = [song("a"), song("b"), song("c")]
        var queue = PlaybackQueue()
        queue.replace(with: songs)
        try require(queue.currentSong == songs[0], "Queue must start at the selected song")
        try require(queue.advance(automatically: true) == songs[1], "Track completion must advance")
        queue.repeatMode = .one
        try require(queue.advance(automatically: true) == songs[1], "Repeat one must keep the current song on completion")
        try require(queue.advance(automatically: false) == songs[2], "Manual next must escape repeat one")
        queue.repeatMode = .off
        try require(queue.advance(automatically: true) == nil, "Repeat off must stop at the end")
        queue.repeatMode = .all
        try require(queue.advance(automatically: true) == songs[0], "Repeat all must wrap")
        queue.enqueue(song("next"), playNext: true)
        try require(queue.advance(automatically: false)?.id == "next", "Play-next must be inserted immediately after current")
        queue.setShuffle(true)
        try require(Set(queue.order).count == queue.entries.count && queue.order.count == queue.entries.count, "Shuffle order must contain every entry exactly once")
        let selected = queue.currentID!
        queue.remove(selected)
        try require(queue.currentID != selected && queue.currentSong != nil, "Removing current must choose a valid successor")
        queue.setShuffle(false)
        queue.move(from: IndexSet(integer: 0), to: queue.entries.count)
        try require(queue.order == queue.entries.map(\.id), "Manual reorder must update unshuffled playback order")
        let restoredQueue = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        try require(restoredQueue == queue, "Queue state, current entry and modes must round-trip")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("library.json")
        let store = LibraryStore(fileURL: path)
        store.toggleFavorite(songs[0]); store.createPlaylist("My playlist")
        let id = store.data.playlists[0].id
        store.add(songs[1], to: id); store.add(songs[1], to: id)
        store.recordPlay(songs[0]); store.recordPlay(songs[0])
        store.recordSearch("Artist"); store.recordSearch("artist")
        store.saveQueue(queue)
        let reloaded = LibraryStore(fileURL: path)
        try require(reloaded.isFavorite(songs[0]), "Favorites must survive app relaunch")
        try require(reloaded.data.playlists[0].songs.count == 1, "Playlist additions must deduplicate video IDs")
        try require(reloaded.data.history.count == 1 && reloaded.data.searches.count == 1, "Histories must deduplicate and persist")
        try require(reloaded.data.queue == queue, "Active queue must persist")
        let backup = try store.exportedData()
        reloaded.toggleFavorite(songs[0]); try reloaded.restore(backup)
        try require(reloaded.isFavorite(songs[0]), "Backup restore must restore favorites")
        store.mergeRemotePlaylist(id: "remote-1", name: "Remote", songs: [songs[0]])
        store.mergeRemotePlaylist(id: "remote-1", name: "Renamed", songs: [songs[2]])
        try require(store.data.playlists.filter { $0.remoteID == "remote-1" }.count == 1, "Repeated cloud imports must update rather than duplicate playlists")
        let invalid = Data("not-json".utf8)
        try invalid.write(to: path)
        let corrupt = LibraryStore(fileURL: path)
        corrupt.createPlaylist("New")
        let preserved = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("unreadable") }
        try require(preserved.count == 1 && (try Data(contentsOf: preserved[0])) == invalid, "Unreadable data must be backed up before writes")

        let lines = SongLyrics.parseLRC("[ar:Artist]\n[00:01.50][00:03.00]line one\n[01:02.25]line two")
        try require(lines.count == 3 && lines.map(\.time) == [1.5, 3, 62.25], "LRC parser must support multiple timestamps and fractions")
        try require(lines.map(\.text) == ["line one", "line one", "line two"], "LRC metadata must not become lyrics")
        try require(songs[0].durationSeconds == 195, "Duration must convert to seconds")
        let invalidSong = CatalogSong(id: "invalid", title: "", artist: "", duration: "3:bad", thumbnailURL: nil)
        try require(invalidSong.durationSeconds == nil, "Malformed durations must not be used for lyric matching")

        let fixture: [String: Any] = ["contents": [["musicResponsiveListItemRenderer": ["playlistItemData": ["videoId": "fixture"], "flexColumns": [["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Title"]]]]], ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Artist"], ["text": " • "], ["text": "3:15"]]]]]]]]]]
        let parsed = CatalogAPI.songs(in: fixture)
        try require(parsed.count == 1 && parsed[0].title == "Title" && parsed[0].duration == "3:15", "Catalog parser must preserve title and identify duration metadata")
        print("PASS: queue transitions/shuffle/editing, persistence/backup, cloud merge, corrupt-data backup, LRC parsing and catalog metadata")
    }
}
