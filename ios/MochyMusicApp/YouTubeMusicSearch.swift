import Foundation
import Combine

struct CatalogSong: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let duration: String?
    let thumbnailURL: URL?
}

@MainActor
final class YouTubeMusicSearch: ObservableObject {
    @Published private(set) var results: [CatalogSong] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var requestTask: Task<Void, Never>?
    private var activeRequestID = UUID()

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRequestID = UUID()
        let requestID = activeRequestID
        requestTask?.cancel()
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        requestTask = Task {
            isLoading = true
            results = []
            errorMessage = nil
            defer { if activeRequestID == requestID { isLoading = false } }
            do {
                let foundSongs = try await Self.fetchSongs(query: query)
                guard activeRequestID == requestID else { return }
                results = foundSongs
                if results.isEmpty {
                    errorMessage = "No songs found. Try another search."
                }
            } catch is CancellationError {
                return
            } catch {
                guard activeRequestID == requestID else { return }
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }
    private static func fetchSongs(query: String) async throws -> [CatalogSong] {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "params", value: "EgWKAQIIAWoKEAkQBRAKEAMQBA==")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260707.12.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20260707.12.00",
                    "hl": Locale.current.language.languageCode?.identifier ?? "en",
                    "gl": Locale.current.region?.identifier ?? "US"
                ],
                "request": ["internalExperimentFlags": [], "useSsl": true],
                "user": ["lockedSafetyMode": false]
            ],
            "query": query
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SearchError.server
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SearchError.invalidResponse
        }

        let renderers = findRenderers(in: json)
        var seen = Set<String>()
        return renderers.compactMap { renderer in
            guard let playlist = renderer["playlistItemData"] as? [String: Any],
                  let id = playlist["videoId"] as? String,
                  seen.insert(id).inserted else { return nil }
            let columns = renderer["flexColumns"] as? [[String: Any]] ?? []
            let title = text(in: columns[safe: 0])
            guard !title.isEmpty else { return nil }
            let artist = text(in: columns[safe: 1])
            let duration = columns.dropFirst(2).compactMap { text(in: $0) }.first
            let thumbnails = (renderer["thumbnail"] as? [String: Any])?["musicThumbnailRenderer"] as? [String: Any]
            let thumbnailItems = thumbnails?["thumbnail"] as? [String: Any]
            let thumbnailList = thumbnailItems?["thumbnails"] as? [[String: Any]] ?? []
            let thumbString = thumbnailList.last?["url"] as? String
            let thumbURL = thumbString.flatMap { URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0) }
            return CatalogSong(id: id, title: title, artist: artist.isEmpty ? "YouTube Music" : artist, duration: duration, thumbnailURL: thumbURL)
        }
    }

    private static func findRenderers(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var found: [[String: Any]] = []
            if let renderer = dictionary["musicResponsiveListItemRenderer"] as? [String: Any] {
                found.append(renderer)
            }
            for child in dictionary.values { found.append(contentsOf: findRenderers(in: child)) }
            return found
        }
        if let array = value as? [Any] {
            return array.flatMap(findRenderers(in:))
        }
        return []
    }

    private static func text(in column: [String: Any]?) -> String {
        guard let renderer = column?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = renderer["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    private enum SearchError: LocalizedError {
        case server
        case invalidResponse
        var errorDescription: String? {
            switch self {
            case .server: return "YouTube Music search is temporarily unavailable."
            case .invalidResponse: return "YouTube Music returned an unreadable response."
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}




