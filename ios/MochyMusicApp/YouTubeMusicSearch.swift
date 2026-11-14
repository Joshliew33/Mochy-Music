import Foundation
import Combine

@MainActor
final class YouTubeMusicSearch: ObservableObject {
    @Published private(set) var results: [CatalogSong] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var requestTask: Task<Void, Never>?
    private var generation = UUID()

    func search(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        generation = UUID(); let requestID = generation
        requestTask?.cancel(); results = []; errorMessage = nil; isLoading = false
        guard !query.isEmpty else { return }
        LibraryStore.shared.recordSearch(query)
        isLoading = true
        requestTask = Task {
            defer { if generation == requestID { isLoading = false } }
            do {
                let songs = try await CatalogAPI.search(query)
                guard !Task.isCancelled, generation == requestID else { return }
                results = songs
                if songs.isEmpty { errorMessage = "没有找到歌曲，试试其他关键词。" }
            } catch {
                guard !Task.isCancelled, generation == requestID else { return }
                errorMessage = "搜索失败：\(error.localizedDescription)"
            }
        }
    }
}
