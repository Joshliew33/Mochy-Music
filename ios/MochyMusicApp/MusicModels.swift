import Foundation

struct CatalogSong: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let duration: String?
    let thumbnailURL: URL?

    var durationSeconds: Double? {
        guard let duration else { return nil }
        let strings = duration.split(separator: ":")
        let parts = strings.compactMap { Double($0) }
        guard (2...3).contains(parts.count), parts.count == strings.count,
              parts.allSatisfy({ $0 >= 0 }), parts.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

struct QueueEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var song: CatalogSong
}

enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one
    var label: String { switch self { case .off: "关闭循环"; case .all: "列表循环"; case .one: "单曲循环" } }
}

struct PlaybackQueue: Codable, Equatable {
    private(set) var entries: [QueueEntry] = []
    private(set) var order: [UUID] = []
    private(set) var currentID: UUID?
    var repeatMode: RepeatMode = .off
    private(set) var isShuffled = false

    var currentSong: CatalogSong? { entries.first { $0.id == currentID }?.song }
    var position: Int? { order.firstIndex { $0 == currentID } }
    var canNext: Bool { !entries.isEmpty && ((position ?? -1) + 1 < order.count || repeatMode == .all) }
    var canPrevious: Bool { !entries.isEmpty && ((position ?? 0) > 0 || repeatMode == .all) }

    mutating func replace(with songs: [CatalogSong], startAt index: Int = 0) {
        entries = songs.map { QueueEntry(song: $0) }
        currentID = entries.indices.contains(index) ? entries[index].id : entries.first?.id
        rebuildOrder()
    }

    mutating func select(_ id: UUID) -> CatalogSong? {
        guard entries.contains(where: { $0.id == id }) else { return nil }
        currentID = id
        return currentSong
    }

    mutating func enqueue(_ song: CatalogSong, playNext: Bool = false) {
        let entry = QueueEntry(song: song)
        if playNext, let currentID, let index = entries.firstIndex(where: { $0.id == currentID }), let position {
            entries.insert(entry, at: index + 1)
            order.insert(entry.id, at: position + 1)
        } else {
            entries.append(entry)
            order.append(entry.id)
        }
        if currentID == nil { currentID = entry.id }
    }

    mutating func advance(automatically: Bool) -> CatalogSong? {
        if automatically && repeatMode == .one { return currentSong }
        guard !order.isEmpty else { return nil }
        let next = (position ?? -1) + 1
        if next < order.count { currentID = order[next] }
        else if repeatMode == .all { currentID = order[0] }
        else { return nil }
        return currentSong
    }

    mutating func previous() -> CatalogSong? {
        guard let position, !order.isEmpty else { return nil }
        if position > 0 { currentID = order[position - 1] }
        else if repeatMode == .all { currentID = order.last }
        else { return nil }
        return currentSong
    }

    mutating func setShuffle(_ value: Bool) {
        isShuffled = value
        rebuildOrder()
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        let shift = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) where entries.indices.contains(index) { entries.remove(at: index) }
        entries.insert(contentsOf: moving, at: max(0, min(entries.count, destination - shift)))
        if !isShuffled { order = entries.map(\.id) }
    }

    mutating func remove(_ id: UUID) {
        let oldPosition = position ?? 0
        entries.removeAll { $0.id == id }
        order.removeAll { $0 == id }
        if currentID == id { currentID = order.isEmpty ? nil : order[min(oldPosition, order.count - 1)] }
    }

    mutating func validate() {
        let valid = Set(entries.map(\.id))
        var seen = Set<UUID>()
        order = order.filter { valid.contains($0) && seen.insert($0).inserted }
        order += entries.map(\.id).filter { !seen.contains($0) }
        if let currentID, !valid.contains(currentID) { self.currentID = order.first }
    }

    private mutating func rebuildOrder() {
        let ids = entries.map(\.id)
        if isShuffled, let currentID {
            order = [currentID] + ids.filter { $0 != currentID }.shuffled()
        } else { order = ids }
    }
}

struct LocalPlaylist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var songs: [CatalogSong] = []
    var remoteID: String?
}

struct PlayRecord: Identifiable, Codable, Equatable {
    var id: String { song.id }
    var song: CatalogSong
    var playedAt: Date
}

struct LibrarySnapshot: Codable {
    var version = 1
    var favorites: [CatalogSong] = []
    var playlists: [LocalPlaylist] = []
    var history: [PlayRecord] = []
    var searches: [String] = []
    var queue = PlaybackQueue()
}

struct LyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}

struct SongLyrics {
    var plainText: String
    var lines: [LyricLine] = []
    var source: String
    var isInstrumental = false

    static func parseLRC(_ text: String) -> [LyricLine] {
        let pattern = #"\[(\d+):(\d{2}(?:\.\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let words = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(ns.substring(with: match.range(at: 1))),
                      let seconds = Double(ns.substring(with: match.range(at: 2))) else { continue }
                result.append(LyricLine(id: result.count, time: minutes * 60 + seconds, text: words))
            }
        }
        return result.sorted { $0.time < $1.time }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }
}
