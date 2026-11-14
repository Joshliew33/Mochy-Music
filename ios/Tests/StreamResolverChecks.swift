import Foundation

final class ResolverURLProtocol: URLProtocol {
    static var playerResponse: [String: Any] = [:]
    static var visitorHeader: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let isVisitor = request.url!.path.hasSuffix("/visitor_id")
        let object: [String: Any] = isVisitor
            ? ["responseContext": ["visitorData": "fixture-visitor"]]
            : Self.playerResponse
        if !isVisitor { Self.visitorHeader = request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") }
        let data = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct StreamResolverChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "StreamResolverChecks", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func resolve(_ response: [String: Any]) async throws -> URL {
        ResolverURLProtocol.playerResponse = response
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ResolverURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        return try await YouTubeStreamResolver(session: session).resolve(videoID: "fixture-song")
    }

    static func main() async throws {
        let formats: [[String: Any]] = [
            ["mimeType": "audio/webm; codecs=\"opus\"", "bitrate": 160000, "url": "https://audio.example/opus.webm"],
            ["mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 48000, "url": "https://audio.example/low.m4a"],
            ["mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 128000, "url": "https://audio.example/aac.m4a"],
            ["mimeType": "audio/mp4; codecs=\"opus\"", "bitrate": 256000, "url": "https://audio.example/opus.mp4"],
            ["mimeType": "audio/mp4; codecs=\"mp4a.40.2\"", "bitrate": 512000, "url": "http://audio.example/insecure.m4a"]
        ]
        let url = try await resolve(["playabilityStatus": ["status": "OK"],
                                     "streamingData": ["adaptiveFormats": formats]])
        try require(url.absoluteString == "https://audio.example/aac.m4a",
                    "Must choose the best HTTPS AAC/MP4 stream instead of higher bitrate Opus.")
        try require(ResolverURLProtocol.visitorHeader == "fixture-visitor",
                    "Player request must send its visitor session header.")

        var rejectedUnsupported = false
        do {
            _ = try await resolve(["playabilityStatus": ["status": "OK"],
                                   "streamingData": ["adaptiveFormats": [formats[0]]]])
        } catch {
            rejectedUnsupported = error.localizedDescription.contains("AAC/MP4")
        }
        try require(rejectedUnsupported, "Unsupported-only responses need an actionable error.")

        var preservedReason = false
        do {
            _ = try await resolve(["playabilityStatus": ["status": "LOGIN_REQUIRED",
                                                         "reason": "Fixture login required"]])
        } catch {
            preservedReason = error.localizedDescription.contains("Fixture login required")
        }
        try require(preservedReason, "YouTube refusal reasons must be preserved.")
        print("PASS: AAC selection, HTTPS-only streams, visitor header, unsupported formats and refusal errors")
    }
}
