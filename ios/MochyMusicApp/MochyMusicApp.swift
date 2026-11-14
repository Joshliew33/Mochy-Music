import SwiftUI

@main
@MainActor
struct MochyMusicApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var audioPlayer = AudioPlayer(library: .shared)
    @StateObject private var account = YouTubeAccount()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(library).environmentObject(audioPlayer).environmentObject(account)
        }
    }
}
