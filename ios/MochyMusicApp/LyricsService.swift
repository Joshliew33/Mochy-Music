import Foundation

actor LyricsService {
    static let shared = LyricsService()
    private var cache: [String: SongLyrics] = [:]
    private var retryAfter = Date.distantPast

    func lyrics(for song: CatalogSong) async throws -> SongLyrics? {
        if let cached = cache[song.id] { return cached }
        if Date() >= retryAfter {
            var url = URLComponents(string: "https://lrclib.net/api/get")!
            url.queryItems = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist)]
            if let duration = song.durationSeconds, duration > 0, duration <= 3600 { url.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration)))) }
            var request = URLRequest(url: url.url!); request.timeoutInterval = 15
            request.setValue("MochyMusic-iOS/0.2 (https://github.com/Joshliew33/Mochy-Music)", forHTTPHeaderField: "User-Agent")
            do {
                let (bytes, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 { retryAfter = Date().addingTimeInterval(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60) }
                    if http.statusCode == 200, let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                        let plain = json["plainLyrics"] as? String ?? ""
                        let synced = SongLyrics.parseLRC(json["syncedLyrics"] as? String ?? "")
                        let instrumental = json["instrumental"] as? Bool ?? false
                        if !plain.isEmpty || !synced.isEmpty || instrumental {
                            let result = SongLyrics(plainText: plain, lines: synced, source: "LRCLIB", isInstrumental: instrumental)
                            cache[song.id] = result; return result
                        }
                    }
                }
            } catch { if Task.isCancelled { throw CancellationError() } }
        }
        if let words = try await CatalogAPI.youtubeLyrics(videoID: song.id) {
            let result = SongLyrics(plainText: words, source: "YouTube Music")
            cache[song.id] = result; return result
        }
        return nil
    }
}
