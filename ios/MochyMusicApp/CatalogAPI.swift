import Foundation

struct DiscoverySection: Identifiable {
    var id: String { title }
    var title: String
    var songs: [CatalogSong]
}

enum CatalogAPI {
    static func request(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260707.12.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        var payload = body
        payload["context"] = ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20260707.12.00", "hl": Locale.current.language.languageCode?.identifier ?? "en", "gl": Locale.current.region?.identifier ?? "US"], "request": ["useSsl": true, "internalExperimentFlags": []], "user": ["lockedSafetyMode": false]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        if let error = json["error"] as? [String: Any] { throw NSError(domain: "YouTube", code: error["code"] as? Int ?? -1, userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "请求失败"]) }
        return json
    }

    static func search(_ query: String) async throws -> [CatalogSong] {
        let json = try await request("search", body: ["query": query, "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA=="])
        return songs(in: json)
    }

    static func discover(seed: CatalogSong?) async throws -> [DiscoverySection] {
        let home = try await request("browse", body: ["browseId": "FEmusic_home"])
        var sections: [DiscoverySection] = []
        for shelf in nodes("musicCarouselShelfRenderer", in: home) {
            let titleNode = ((shelf["header"] as? [String: Any])?["musicCarouselShelfBasicHeaderRenderer"] as? [String: Any])?["title"]
            let title = text(titleNode)
            let items = songs(in: shelf["contents"] ?? [])
            if !items.isEmpty { sections.append(DiscoverySection(title: title.isEmpty ? "发现音乐" : title, songs: Array(items.prefix(20)))) }
        }
        if sections.isEmpty {
            let items = songs(in: home)
            if !items.isEmpty { sections.append(DiscoverySection(title: "YouTube Music 推荐", songs: Array(items.prefix(30)))) }
        }
        if let seed {
            let items = try await search(seed.artist)
            if !items.isEmpty { sections.insert(DiscoverySection(title: "继续探索 · \(seed.artist)", songs: Array(items.prefix(12))), at: 0) }
        }
        return sections
    }

    static func youtubeLyrics(videoID: String) async throws -> String? {
        let next = try await request("next", body: ["videoId": videoID])
        let tabs = nodes("tabRenderer", in: next)
        let endpoint = tabs.compactMap { ($0["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any] }.first {
            ($0["browseId"] as? String)?.hasPrefix("MPLYt") == true
        }
        guard let endpoint, let browseID = endpoint["browseId"] as? String else { return nil }
        var body: [String: Any] = ["browseId": browseID]
        if let params = endpoint["params"] { body["params"] = params }
        let response = try await request("browse", body: body)
        return nodes("musicDescriptionShelfRenderer", in: response).compactMap { shelf -> String? in
            let words = text(shelf["description"])
            return words.isEmpty ? nil : words
        }.first
    }

    static func nodes(_ key: String, in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var found: [[String: Any]] = []
            if let node = dictionary[key] as? [String: Any] { found.append(node) }
            for childKey in dictionary.keys.sorted() { found += nodes(key, in: dictionary[childKey]!) }
            return found
        }
        if let array = value as? [Any] { return array.flatMap { nodes(key, in: $0) } }
        return []
    }

    static func text(_ value: Any?) -> String {
        guard let node = value as? [String: Any] else { return "" }
        if let simple = node["simpleText"] as? String { return simple }
        return (node["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
    }

    static func songs(in json: Any) -> [CatalogSong] {
        var songs: [CatalogSong] = []
        for node in nodes("musicResponsiveListItemRenderer", in: json) {
            let columns = (node["flexColumns"] as? [[String: Any]] ?? []).compactMap { $0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] }
            guard let id = (node["playlistItemData"] as? [String: Any])?["videoId"] as? String, let first = columns.first else { continue }
            let title = text(first["text"])
            guard !title.isEmpty else { continue }
            let artist = columns.count > 1 ? text(columns[1]["text"]) : "YouTube Music"
            let duration = columns.flatMap { ($0["text"] as? [String: Any])?["runs"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.first { $0.range(of: #"^\d+(?::\d{2}){1,2}$"#, options: .regularExpression) != nil }
            songs.append(CatalogSong(id: id, title: title, artist: artist, duration: duration, thumbnailURL: thumbnail(in: node)))
        }
        for node in nodes("musicTwoRowItemRenderer", in: json) {
            guard let id = ((node["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String else { continue }
            let title = text(node["title"])
            guard !title.isEmpty else { continue }
            songs.append(CatalogSong(id: id, title: title, artist: text(node["subtitle"]), duration: nil, thumbnailURL: thumbnail(in: node)))
        }
        var seen = Set<String>()
        return songs.filter { seen.insert($0.id).inserted }
    }

    private static func thumbnail(in value: Any) -> URL? {
        func urls(_ node: Any) -> [String] {
            if let object = node as? [String: Any] {
                if let list = object["thumbnails"] as? [[String: Any]] { return list.compactMap { $0["url"] as? String } }
                return object.keys.sorted().flatMap { urls(object[$0]!) }
            }
            if let array = node as? [Any] { return array.flatMap(urls) }
            return []
        }
        guard let raw = urls(value).last else { return nil }
        return URL(string: raw.hasPrefix("//") ? "https:\(raw)" : raw)
    }
}
