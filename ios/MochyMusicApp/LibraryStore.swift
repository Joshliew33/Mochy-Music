import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published private(set) var data: LibrarySnapshot
    @Published var errorMessage: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "MochyMusic/library.json")
        if let bytes = try? Data(contentsOf: self.fileURL), let saved = try? JSONDecoder().decode(LibrarySnapshot.self, from: bytes), saved.version == 1 {
            data = saved
            data.queue.validate()
        } else {
            data = LibrarySnapshot()
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                let backup = self.fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
                do {
                    try FileManager.default.copyItem(at: self.fileURL, to: backup)
                    errorMessage = "资料库无法读取，原文件已另存备份。请从有效备份恢复。"
                } catch { errorMessage = "资料库无法读取，也无法备份原文件：\(error.localizedDescription)" }
            }
        }
    }

    func isFavorite(_ song: CatalogSong) -> Bool { data.favorites.contains { $0.id == song.id } }
    func toggleFavorite(_ song: CatalogSong) {
        if isFavorite(song) { data.favorites.removeAll { $0.id == song.id } }
        else { data.favorites.insert(song, at: 0) }
        save()
    }
    func createPlaylist(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.playlists.append(LocalPlaylist(name: clean)); save()
    }
    func renamePlaylist(_ id: UUID, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        data.playlists[index].name = clean; save()
    }
    func deletePlaylist(_ id: UUID) { data.playlists.removeAll { $0.id == id }; save() }
    func add(_ song: CatalogSong, to id: UUID) {
        guard let i = data.playlists.firstIndex(where: { $0.id == id }), !data.playlists[i].songs.contains(where: { $0.id == song.id }) else { return }
        data.playlists[i].songs.append(song); save()
    }
    func remove(_ song: CatalogSong, from id: UUID) {
        guard let i = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        data.playlists[i].songs.removeAll { $0.id == song.id }; save()
    }
    func moveSongs(in id: UUID, from offsets: IndexSet, to destination: Int) {
        guard let i = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        var songs = data.playlists[i].songs
        let moving = offsets.sorted().map { songs[$0] }
        let shift = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { songs.remove(at: index) }
        songs.insert(contentsOf: moving, at: max(0, min(songs.count, destination - shift)))
        data.playlists[i].songs = songs; save()
    }
    func recordPlay(_ song: CatalogSong) {
        data.history.removeAll { $0.song.id == song.id }
        data.history.insert(PlayRecord(song: song, playedAt: Date()), at: 0)
        data.history = Array(data.history.prefix(200)); save()
    }
    func recordSearch(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.searches.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        data.searches.insert(clean, at: 0); data.searches = Array(data.searches.prefix(40)); save()
    }
    func clearHistory() { data.history = []; data.searches = []; save() }
    func saveQueue(_ queue: PlaybackQueue) { data.queue = queue; save() }
    func exportedData() throws -> Data { try JSONEncoder().encode(data) }
    func restore(_ bytes: Data) throws {
        let imported = try JSONDecoder().decode(LibrarySnapshot.self, from: bytes)
        guard imported.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        data = imported; data.queue.validate(); save()
    }
    func mergeRemotePlaylist(id: String, name: String, songs: [CatalogSong]) {
        if let index = data.playlists.firstIndex(where: { $0.remoteID == id }) {
            data.playlists[index].name = name; data.playlists[index].songs = songs
        } else { data.playlists.append(LocalPlaylist(name: name, songs: songs, remoteID: id)) }
        save()
    }
    func setRemoteID(_ remoteID: String, for id: UUID) {
        guard let index = data.playlists.firstIndex(where: { $0.id == id }) else { return }
        data.playlists[index].remoteID = remoteID; save()
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch { errorMessage = "资料保存失败：\(error.localizedDescription)" }
    }
}
