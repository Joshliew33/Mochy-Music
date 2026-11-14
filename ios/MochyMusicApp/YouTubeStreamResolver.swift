import Foundation

actor YouTubeStreamResolver {
    static let shared = YouTubeStreamResolver()

    private var visitorData: String?

    func resolve(videoID: String) async throws -> URL {
        let visitor = try await getVisitorData()
        let response = try await playerResponse(videoID: videoID, visitorData: visitor)
        let playability = response["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String
        guard status == "OK" else {
            throw ResolverError.unavailable(playability?["reason"] as? String ?? "YouTube did not allow this track to play.")
        }

        let streamingData = response["streamingData"] as? [String: Any]
        let formats = streamingData?["adaptiveFormats"] as? [[String: Any]] ?? []
        let playable = formats.compactMap { format -> (Int, URL)? in
            guard let mimeType = format["mimeType"] as? String,
                  mimeType.lowercased().hasPrefix("audio/"),
                  let rawURL = format["url"] as? String,
                  let url = URL(string: rawURL),
                  url.scheme == "https" else { return nil }
            return (format["bitrate"] as? Int ?? 0, url)
        }
        guard let streamURL = playable.max(by: { $0.0 < $1.0 })?.1 else {
            throw ResolverError.noDirectAudio
        }
        return streamURL
    }

    private func getVisitorData() async throws -> String {
        if let visitorData { return visitorData }
        let response = try await post(
            endpoint: "https://www.youtube.com/youtubei/v1/visitor_id",
            body: ["context": ["client": clientContext()]],
            formatVersion: "2"
        )
        guard let context = response["responseContext"] as? [String: Any],
              let value = context["visitorData"] as? String,
              !value.isEmpty else {
            throw ResolverError.invalidVisitor
        }
        visitorData = value
        return value
    }

    private func playerResponse(videoID: String, visitorData: String) async throws -> [String: Any] {
        var client = clientContext()
        client["visitorData"] = visitorData
        return try await post(
            endpoint: "https://www.youtube.com/youtubei/v1/player",
            body: [
                "context": ["client": client],
                "videoId": videoID,
                "contentCheckOk": true,
                "racyCheckOk": true
            ],
            formatVersion: "2"
        )
    }

    private func clientContext() -> [String: Any] {
        [
            "clientName": "VISIONOS",
            "clientVersion": "1.04",
            "clientScreen": "WATCH",
            "platform": "MOBILE",
            "osName": "visionOS",
            "osVersion": "26.6.0.23O770",
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "hl": Locale.current.language.languageCode?.identifier ?? "en",
            "gl": Locale.current.region?.identifier ?? "US"
        ]
    }

    private func post(endpoint: String, body: [String: Any], formatVersion: String) async throws -> [String: Any] {
        guard let url = URL(string: endpoint) else { throw ResolverError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(formatVersion, forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("101", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.04", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ResolverError.requestFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResolverError.invalidResponse
        }
        return json
    }

    private enum ResolverError: LocalizedError {
        case invalidVisitor
        case invalidResponse
        case requestFailed
        case noDirectAudio
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .invalidVisitor: return "YouTube could not start a playback session."
            case .invalidResponse: return "YouTube returned an unreadable playback response."
            case .requestFailed: return "Could not contact YouTube to resolve this song."
            case .noDirectAudio: return "YouTube did not return a directly playable audio stream for this song."
            case let .unavailable(reason): return reason
            }
        }
    }
}
