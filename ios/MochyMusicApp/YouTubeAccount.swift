import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

private struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

private enum AccountKeychain {
    static let service = "app.mochy.music.ios.oauth"
    static func read() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "google", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess else { return nil }
        return value as? Data
    }
    static func save(_ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "google"]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "google"] as CFDictionary)
    }
}

@MainActor
final class YouTubeAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var displayName = "YouTube"
    @Published var message: String?
    private var tokens: OAuthTokens?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTask: Task<OAuthTokens, Error>?
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    private var clientID: String { Bundle.main.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? "" }
    private var callbackScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    private var redirectURI: String { "\(callbackScheme):/oauthredirect" }
    var configurationMessage: String? {
        guard clientID.hasSuffix(".apps.googleusercontent.com") else { return "账号登录尚需配置 Google iOS OAuth 客户端 ID。当前收藏和歌单可正常保存在手机，并可导出备份。" }
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        guard types.contains(where: { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(callbackScheme) }) else { return "Google 登录回调尚未配置，请重新构建安装包。" }
        return nil
    }

    override init() {
        super.init()
        if configurationMessage == nil, let data = AccountKeychain.read(), let saved = try? JSONDecoder().decode(OAuthTokens.self, from: data) {
            tokens = saved; isSignedIn = true
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func signIn() {
        guard !isBusy else { return }
        if let configurationMessage { message = configurationMessage; return }
        isBusy = true; message = nil
        let operationID = generation
        operation = Task {
            defer { isBusy = false }
            do {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
                let verifier = Self.base64URL(Data(bytes))
                let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
                let state = UUID().uuidString
                var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                url.queryItems = ["client_id": clientID, "redirect_uri": redirectURI, "response_type": "code", "scope": "https://www.googleapis.com/auth/youtube.force-ssl", "code_challenge": challenge, "code_challenge_method": "S256", "state": state, "access_type": "offline", "prompt": "consent"].map { URLQueryItem(name: $0.key, value: $0.value) }
                let callback: URL = try await withCheckedThrowingContinuation { continuation in
                    let session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: callbackScheme) { callback, error in
                        if let callback { continuation.resume(returning: callback) }
                        else { continuation.resume(throwing: error ?? URLError(.userAuthenticationRequired)) }
                    }
                    session.presentationContextProvider = self
                    authSession = session
                    if !session.start() { continuation.resume(throwing: URLError(.cannotLoadFromNetwork)) }
                }
                authSession = nil
                let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard callback.scheme == callbackScheme, params.first(where: { $0.name == "state" })?.value == state,
                      let code = params.first(where: { $0.name == "code" })?.value else { throw URLError(.userAuthenticationRequired) }
                let fresh = try await exchange(["client_id": clientID, "code": code, "code_verifier": verifier, "redirect_uri": redirectURI, "grant_type": "authorization_code"])
                guard generation == operationID else { return }
                try saveTokens(fresh)
                if let channel = try await api("channels", parameters: ["part": "snippet", "mine": "true"])["items"] as? [[String: Any]], let first = channel.first {
                    displayName = (first["snippet"] as? [String: Any])?["title"] as? String ?? "YouTube"
                }
                message = "已登录。可以导入云端歌单。"
            } catch {
                authSession = nil
                if generation == operationID { message = "登录未完成：\(error.localizedDescription)" }
            }
        }
    }

    func signOut() {
        generation = UUID(); operation?.cancel(); authSession?.cancel(); authSession = nil
        refreshTask?.cancel(); refreshTask = nil
        tokens = nil; isSignedIn = false; displayName = "YouTube"; AccountKeychain.delete()
        message = "已退出账号，本地资料已保留。"
    }

    func importPlaylists(into library: LibraryStore) {
        guard !isBusy, isSignedIn else { return }
        isBusy = true; message = "正在读取云端歌单…"
        operation = Task {
            defer { isBusy = false }
            do {
                let lists = try await allItems("playlists", parameters: ["part": "snippet", "mine": "true", "maxResults": "50"])
                var count = 0
                for list in lists {
                    try Task.checkCancellation()
                    guard let id = list["id"] as? String, let snippet = list["snippet"] as? [String: Any], let title = snippet["title"] as? String else { continue }
                    let items = try await allItems("playlistItems", parameters: ["part": "snippet,contentDetails", "playlistId": id, "maxResults": "50"])
                    var seen = Set<String>()
                    let songs = items.compactMap { item -> CatalogSong? in
                        guard let s = item["snippet"] as? [String: Any], let title = s["title"] as? String,
                              title != "Deleted video", title != "Private video",
                              let videoID = (item["contentDetails"] as? [String: Any])?["videoId"] as? String, seen.insert(videoID).inserted else { return nil }
                        let thumb = ((s["thumbnails"] as? [String: Any])?["high"] as? [String: Any])?["url"] as? String
                        return CatalogSong(id: videoID, title: title, artist: s["videoOwnerChannelTitle"] as? String ?? "YouTube", duration: nil, thumbnailURL: thumb.flatMap(URL.init(string:)))
                    }
                    library.mergeRemotePlaylist(id: id, name: title, songs: songs); count += 1
                }
                message = "已导入 \(count) 个歌单。仅包含 YouTube Data API 可访问的歌单。"
            } catch { if !Task.isCancelled { message = "同步未完成：\(error.localizedDescription)" } }
        }
    }

    func upload(_ playlist: LocalPlaylist, library: LibraryStore) {
        guard !isBusy, isSignedIn else { return }
        isBusy = true; message = "正在上传歌单…"
        operation = Task {
            defer { isBusy = false }
            do {
                let id: String
                if let remoteID = playlist.remoteID { id = remoteID }
                else {
                    let created = try await api("playlists", parameters: ["part": "snippet,status"], method: "POST", body: ["snippet": ["title": playlist.name], "status": ["privacyStatus": "private"]])
                    guard let newID = created["id"] as? String else { throw URLError(.cannotParseResponse) }
                    id = newID; library.setRemoteID(id, for: playlist.id)
                }
                let existing = try await allItems("playlistItems", parameters: ["part": "contentDetails", "playlistId": id, "maxResults": "50"])
                var present = Set(existing.compactMap { ($0["contentDetails"] as? [String: Any])?["videoId"] as? String })
                for song in playlist.songs where !present.contains(song.id) {
                    try Task.checkCancellation()
                    _ = try await api("playlistItems", parameters: ["part": "snippet"], method: "POST", body: ["snippet": ["playlistId": id, "resourceId": ["kind": "youtube#video", "videoId": song.id]]])
                    present.insert(song.id)
                }
                message = "已上传新歌曲。云端原有歌曲和顺序未删除。"
            } catch { if !Task.isCancelled { message = "上传未完成，可稍后重试：\(error.localizedDescription)" } }
        }
    }

    private func allItems(_ endpoint: String, parameters: [String: String]) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []; var page: String?
        repeat {
            try Task.checkCancellation()
            var params = parameters; params["pageToken"] = page
            let json = try await api(endpoint, parameters: params)
            result += json["items"] as? [[String: Any]] ?? []; page = json["nextPageToken"] as? String
        } while page != nil
        return result
    }

    private func api(_ endpoint: String, parameters: [String: String], method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let token = try await accessToken()
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(endpoint)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (bytes, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = json["error"] as? [String: Any]
            throw NSError(domain: "YouTube", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: error?["message"] as? String ?? "账号请求失败，请重新登录。"])
        }
        return json
    }

    private func accessToken() async throws -> String {
        guard let saved = tokens else { throw URLError(.userAuthenticationRequired) }
        if saved.expiresAt.timeIntervalSinceNow > 60 { return saved.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let refresh = saved.refreshToken else { throw URLError(.userAuthenticationRequired) }
        let sessionID = generation
        let task = Task { try await exchange(["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"], existingRefresh: refresh) }
        refreshTask = task
        defer { refreshTask = nil }
        let fresh = try await task.value
        guard sessionID == generation else { throw CancellationError() }
        try saveTokens(fresh); return fresh.accessToken
    }

    private func exchange(_ values: [String: String], existingRefresh: String? = nil) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents(); form.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let access = json["access_token"] as? String else { throw URLError(.userAuthenticationRequired) }
        return OAuthTokens(accessToken: access, refreshToken: json["refresh_token"] as? String ?? existingRefresh, expiresAt: Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600))
    }
    private func saveTokens(_ tokens: OAuthTokens) throws {
        try AccountKeychain.save(JSONEncoder().encode(tokens)); self.tokens = tokens; isSignedIn = true
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
