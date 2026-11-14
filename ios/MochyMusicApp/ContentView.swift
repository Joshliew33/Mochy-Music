import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum MusicTab: String, CaseIterable, Identifiable {
    case home, search, library, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .home: "首页"; case .search: "搜索"; case .library: "音乐库"; case .settings: "设置" }
    }
    var icon: String {
        switch self { case .home: "house"; case .search: "magnifyingglass"; case .library: "square.stack"; case .settings: "gearshape" }
    }
    var selectedIcon: String {
        switch self { case .home: "house.fill"; case .search: "magnifyingglass"; case .library: "square.stack.fill"; case .settings: "gearshape.fill" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var tabSelection
    @State private var selectedTab: MusicTab = .home
    @State private var showPlayer = false
    @State private var keyboardVisible = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .toolbar(.hidden, for: .tabBar).tag(MusicTab.home)
            NavigationStack { SearchView() }
                .toolbar(.hidden, for: .tabBar).tag(MusicTab.search)
            NavigationStack { MusicLibraryView() }
                .toolbar(.hidden, for: .tabBar).tag(MusicTab.library)
            NavigationStack { SettingsView() }
                .toolbar(.hidden, for: .tabBar).tag(MusicTab.settings)
        }
        .tint(.mint)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible { bottomDock }
        }
        .sheet(isPresented: $showPlayer) {
            PlayerView().presentationDragIndicator(.visible).presentationCornerRadius(32)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--layout-player") { showPlayer = true }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    // Both surfaces participate in layout. Their combined height is reserved for
    // scrolling content, including when the player or an error becomes visible.
    private var bottomDock: some View {
        VStack(spacing: 10) {
            if let error = player.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button { player.errorMessage = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                        .accessibilityLabel("关闭错误提示")
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 6)
                .glassPill().accessibilityIdentifier("playback-error")
                .onTapGesture { showPlayer = true }
            }
            if player.currentSong != nil || player.currentTrack != nil { miniPlayer }
            navigationPill
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.16)], startPoint: .top, endPoint: .bottom)
                .padding(.top, -16).ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: player.currentSong != nil || player.currentTrack != nil)
    }

    private var navigationPill: some View {
        HStack(spacing: 2) {
            ForEach(MusicTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 21, weight: .semibold)).frame(height: 24)
                        if !typeSize.isAccessibilitySize {
                            Text(tab.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.mint : Color.primary.opacity(0.7))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(.white.opacity(0.12)).matchedGeometryEffect(id: "tab-selection", in: tabSelection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                .accessibilityIdentifier("tab-\(tab.rawValue)")
            }
        }
        .padding(5).glassPill(interactive: true)
        .accessibilityIdentifier("bottom-navigation")
    }

    private var miniPlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showPlayer = true } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: player.currentSong?.thumbnailURL ?? player.currentTrack?.artworkURL, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(player.currentSong?.title ?? player.currentTrack?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.isBuffering ? "正在加载…" : player.currentSong?.artist ?? player.currentTrack?.artist ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("打开播放器")
                Button { player.togglePlayback() } label: {
                    if player.isBuffering { ProgressView().tint(.primary).frame(width: 44, height: 44) }
                    else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44) }
                }
                .foregroundStyle(.primary).buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying || player.isBuffering ? "暂停" : "播放")
                Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title3).frame(width: 40, height: 44) }
                    .foregroundStyle(.primary).buttonStyle(.plain)
                    .disabled(!player.queue.canNext).accessibilityLabel("下一首")
            }.padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
            if player.duration > 0 {
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.1))
                        .overlay(alignment: .leading) { Capsule().fill(.mint.opacity(0.8)).frame(width: proxy.size.width * min(1, max(0, player.elapsedTime / player.duration))) }
                }.frame(height: 2).padding(.horizontal, 30).padding(.bottom, 5)
            }
        }
        .glassPill(interactive: true)
        .accessibilityIdentifier("mini-player")
    }
}

struct CoverImage: View {
    var url: URL?
    var size: CGFloat
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            RoundedRectangle(cornerRadius: 10).fill(.mint.opacity(0.15)).overlay { Image(systemName: "music.note").foregroundStyle(.mint) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(24, size / 5)))
    }
}

struct SongRow: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    var song: CatalogSong
    var play: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    CoverImage(url: song.thumbnailURL, size: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            .foregroundStyle(player.currentSong?.id == song.id ? Color.mint : Color.primary)
                        Text([song.artist, song.duration].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if player.resolvingTrackID == song.id { ProgressView().tint(.mint) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button { library.toggleFavorite(song) } label: { Label(library.isFavorite(song) ? "取消收藏" : "收藏", systemImage: library.isFavorite(song) ? "heart.slash" : "heart") }
                Button { player.enqueue(song, playNext: true) } label: { Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") }
                Button { player.enqueue(song) } label: { Label("加入队列", systemImage: "text.badge.plus") }
                Menu("加入歌单") {
                    ForEach(library.data.playlists) { list in Button(list.name) { library.add(song, to: list.id) } }
                    if library.data.playlists.isEmpty { Text("请先在音乐库创建歌单") }
                }
                ShareLink(item: URL(string: "https://music.youtube.com/watch?v=\(song.id)")!) { Label("分享歌曲", systemImage: "square.and.arrow.up") }
            } label: { Image(systemName: "ellipsis").frame(width: 40, height: 44) }.accessibilityLabel("\(song.title) 的更多操作")
        }.padding(.vertical, 4)
    }
}

struct SongCollectionView: View {
    @EnvironmentObject private var player: AudioPlayer
    var title: String
    var songs: [CatalogSong]
    var body: some View {
        List {
            if !songs.isEmpty { Button { player.play(songs) } label: { Label("播放全部", systemImage: "play.fill") } }
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in SongRow(song: song) { player.play(songs, startAt: index) } }
            if songs.isEmpty { ContentUnavailableView("还没有歌曲", systemImage: "music.note") }
        }.navigationTitle(title)
    }
}

struct HomeView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var sections: [DiscoverySection] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("随时，听你喜欢的。").font(.largeTitle.bold())
                    Text("Mochy Music").foregroundStyle(.mint)
                }.padding(.top)
                if !library.data.history.isEmpty {
                    NavigationLink { SongCollectionView(title: "最近播放", songs: library.data.history.map(\.song)) } label: { Label("继续聆听 · 最近播放", systemImage: "clock.arrow.circlepath").font(.headline) }
                    ForEach(library.data.history.prefix(4)) { record in SongRow(song: record.song) { player.play(library.data.history.map(\.song), startAt: library.data.history.firstIndex { $0.id == record.id } ?? 0) } }
                }
                if loading { ProgressView("正在获取推荐…") }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title).font(.title3.bold())
                        ForEach(Array(section.songs.enumerated()), id: \.element.id) { index, song in SongRow(song: song) { player.play(section.songs, startAt: index) } }
                    }
                }
                if !loading && sections.isEmpty && error == nil { Text("暂时没有推荐，先搜索喜欢的歌曲吧。").foregroundStyle(.secondary) }
            }.padding(20)
        }.navigationTitle("发现").navigationBarTitleDisplayMode(.inline)
            .task { if sections.isEmpty { await load() } }.refreshable { await load() }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { sections = try await CatalogAPI.discover(seed: library.data.history.first?.song ?? library.data.favorites.first) }
        catch { if !Task.isCancelled { self.error = "推荐暂时无法加载：\(error.localizedDescription)" } }
    }
}

struct SearchView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var search = YouTubeMusicSearch()
    @State private var query = ""
    var body: some View {
        List {
            if query.isEmpty && !library.data.searches.isEmpty {
                Section("最近搜索") { ForEach(library.data.searches, id: \.self) { text in Button(text) { query = text; search.search(text) } } }
            }
            if search.isLoading { ProgressView("搜索中…") }
            if let error = search.errorMessage { Text(error).foregroundStyle(.secondary) }
            if !search.results.isEmpty { Button { player.play(search.results) } label: { Label("播放搜索结果", systemImage: "play.fill") } }
            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, song in SongRow(song: song) { player.play(search.results, startAt: index) } }
        }.navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌曲或歌手")
            .onSubmit(of: .search) { search.search(query) }
            .onChange(of: query) { _, value in if value.isEmpty { search.search("") } }
    }
}

struct MusicLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var creating = false
    @State private var name = ""
    var body: some View {
        List {
            Section {
                NavigationLink { SongCollectionView(title: "我的收藏", songs: library.data.favorites) } label: { Label("我的收藏（\(library.data.favorites.count)）", systemImage: "heart.fill") }
                NavigationLink { SongCollectionView(title: "播放历史", songs: library.data.history.map(\.song)) } label: { Label("播放历史", systemImage: "clock") }
            }
            Section("歌单") {
                ForEach(library.data.playlists) { list in NavigationLink { PlaylistView(id: list.id) } label: { Label("\(list.name) · \(list.songs.count) 首", systemImage: "music.note.list") } }
                Button { name = ""; creating = true } label: { Label("新建歌单", systemImage: "plus") }
            }
            if let error = library.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
        }.navigationTitle("音乐库")
            .alert("新建歌单", isPresented: $creating) { TextField("歌单名称", text: $name); Button("创建") { library.createPlaylist(name) }; Button("取消", role: .cancel) {} }
    }
}

struct PlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var account: YouTubeAccount
    @Environment(\.dismiss) private var dismiss
    var id: UUID
    @State private var rename = false
    @State private var name = ""
    @State private var deleting = false
    @State private var uploading = false
    private var playlist: LocalPlaylist? { library.data.playlists.first { $0.id == id } }
    var body: some View {
        List {
            if let list = playlist {
                if !list.songs.isEmpty { Button { player.play(list.songs) } label: { Label("播放全部", systemImage: "play.fill") } }
                ForEach(Array(list.songs.enumerated()), id: \.element.id) { index, song in SongRow(song: song) { player.play(list.songs, startAt: index) } }
                    .onDelete { offsets in for index in offsets { library.remove(list.songs[index], from: id) } }
                    .onMove { library.moveSongs(in: id, from: $0, to: $1) }
                if list.songs.isEmpty { Text("在歌曲的更多菜单中添加到此歌单。").foregroundStyle(.secondary) }
            }
        }.navigationTitle(playlist?.name ?? "歌单")
            .toolbar {
                EditButton()
                Menu {
                    Button("重命名") { name = playlist?.name ?? ""; rename = true }
                    if account.isSignedIn { Button("上传到 YouTube…") { uploading = true }.disabled(account.isBusy) }
                    Button("删除歌单", role: .destructive) { deleting = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .alert("重命名歌单", isPresented: $rename) { TextField("名称", text: $name); Button("保存") { library.renamePlaylist(id, name: name) }; Button("取消", role: .cancel) {} }
            .confirmationDialog("删除此本地歌单？", isPresented: $deleting, titleVisibility: .visible) { Button("删除歌单", role: .destructive) { library.deletePlaylist(id); dismiss() } }
            .confirmationDialog("将歌曲上传到你的 YouTube 账号？新歌单会设为私密；已有云端歌单只追加缺少的歌曲。", isPresented: $uploading, titleVisibility: .visible) { Button("上传") { if let list = playlist { account.upload(list, library: library) } } }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    private var artworkURL: URL? { player.currentSong?.thumbnailURL ?? player.currentTrack?.artworkURL }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    CoverImage(url: artworkURL, size: min(260, max(140, min(geometry.size.width - 48, geometry.size.height * 0.34))))
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                        .padding(.top, 12)
                    VStack(spacing: 7) {
                        Text(player.currentSong?.title ?? player.currentTrack?.title ?? "尚未播放")
                            .font(.title2.bold()).multilineTextAlignment(.center)
                        Text(player.currentSong?.artist ?? player.currentTrack?.artist ?? "").foregroundStyle(.secondary)
                    }
                    if let error = player.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { min(max(0, player.elapsedTime), max(1, player.duration)) }, set: player.seek), in: 0...max(1, player.duration))
                            .disabled(player.duration <= 0).tint(.mint)
                        HStack { Text(time(player.elapsedTime)); Spacer(); Text(time(player.duration)) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 26) {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.end.fill").font(.title2).frame(width: 58, height: 58)
                        }.disabled(player.currentSong == nil).accessibilityLabel("上一首")
                        Button { player.togglePlayback() } label: {
                            Image(systemName: player.isPlaying || player.isBuffering ? "pause.fill" : "play.fill")
                                .font(.system(size: 32, weight: .semibold)).frame(width: 82, height: 82)
                        }.accessibilityLabel(player.isPlaying || player.isBuffering ? "暂停" : "播放")
                        Button { player.next() } label: {
                            Image(systemName: "forward.end.fill").font(.title2).frame(width: 58, height: 58)
                        }.disabled(!player.queue.canNext).accessibilityLabel("下一首")
                    }.foregroundStyle(.primary).buttonStyle(GlassButtonStyle())
                    if player.isBuffering { ProgressView("加载音频…").tint(.mint) }
                    HStack(spacing: 14) {
                        Button { player.toggleShuffle() } label: {
                            Label("随机", systemImage: "shuffle").labelStyle(.iconOnly)
                                .foregroundStyle(player.queue.isShuffled ? Color.mint : Color.primary)
                                .frame(maxWidth: .infinity).frame(height: 46)
                        }.accessibilityLabel(player.queue.isShuffled ? "关闭随机播放" : "开启随机播放")
                        Button { player.cycleRepeat() } label: {
                            Label(player.queue.repeatMode.label, systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat").labelStyle(.iconOnly)
                                .foregroundStyle(player.queue.repeatMode == .off ? Color.primary : Color.mint)
                                .frame(maxWidth: .infinity).frame(height: 46)
                        }.accessibilityLabel(player.queue.repeatMode.label)
                        if let song = player.currentSong {
                            Button { library.toggleFavorite(song) } label: {
                                Image(systemName: library.isFavorite(song) ? "heart.fill" : "heart")
                                    .foregroundStyle(library.isFavorite(song) ? Color.mint : Color.primary)
                                    .frame(maxWidth: .infinity).frame(height: 46)
                            }.accessibilityLabel(library.isFavorite(song) ? "取消收藏" : "收藏")
                        }
                    }.font(.title3).buttonStyle(GlassButtonStyle())
                    NavigationLink { QueueView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet")
                            Text("播放队列").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(player.queue.entries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.padding(.horizontal, 18).frame(height: 50).foregroundStyle(.primary)
                    }.buttonStyle(GlassButtonStyle())
                    if let song = player.currentSong { LyricsPanel(song: song) }
                }.padding(24)
            }
            .background { PlayerBackdrop(url: artworkURL) }
            .navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).frame(width: 40, height: 40) }
                        .buttonStyle(GlassButtonStyle()).foregroundStyle(.primary).accessibilityLabel("收起播放器")
                }
            }
            }
        }.tint(.mint).preferredColorScheme(.dark)
    }
    private func time(_ seconds: Double) -> String {
        let n = seconds.isFinite ? max(0, Int(seconds)) : 0
        return "\(n / 60):\(String(format: "%02d", n % 60))"
    }
}

private struct PlayerBackdrop: View {
    var url: URL?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                RadialGradient(colors: [.mint.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: proxy.size.height * 0.8)
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).blur(radius: 75).opacity(0.32)
                    } placeholder: { Color.clear }
                }
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.ignoresSafeArea()
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var clearing = false
    var body: some View {
        List {
            ForEach(player.queue.entries) { entry in
                Button { player.selectQueueEntry(entry.id) } label: {
                    HStack { CoverImage(url: entry.song.thumbnailURL, size: 40); VStack(alignment: .leading) { Text(entry.song.title).lineLimit(1); Text(entry.song.artist).font(.caption).foregroundStyle(.secondary) }; Spacer(); if player.queue.currentID == entry.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.mint) } }
                }.buttonStyle(.plain)
            }.onDelete { offsets in let ids = offsets.map { player.queue.entries[$0].id }; ids.forEach(player.removeQueueEntry) }
                .onMove(perform: player.moveQueue)
            if player.queue.entries.isEmpty { ContentUnavailableView("队列为空", systemImage: "music.note.list") }
        }.navigationTitle("播放队列").toolbar { EditButton(); Button { clearing = true } label: { Image(systemName: "trash") }.disabled(player.queue.entries.isEmpty) }
            .confirmationDialog("清空播放队列？", isPresented: $clearing, titleVisibility: .visible) { Button("清空", role: .destructive) { player.clearQueue() } }
    }
}

struct LyricsPanel: View {
    @EnvironmentObject private var player: AudioPlayer
    var song: CatalogSong
    @State private var lyrics: SongLyrics?
    @State private var loading = false
    @State private var error: String?
    private var activeIndex: Int? { lyrics?.lines.last(where: { $0.time <= player.elapsedTime })?.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("歌词").font(.headline)
            if loading { ProgressView("查找歌词…") }
            else if let lyrics {
                if lyrics.isInstrumental { Text("纯音乐").foregroundStyle(.secondary) }
                else if !lyrics.lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(lyrics.lines) { line in Button { player.seek(to: line.time) } label: { Text(line.text.isEmpty ? "♪" : line.text).font(.title3.weight(activeIndex == line.id ? .bold : .regular)).foregroundStyle(activeIndex == line.id ? Color.mint : Color.secondary).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).id(line.id) }
                            }.padding(.vertical, 30)
                        }.frame(height: 260)
                            .onChange(of: activeIndex) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } } }
                    }
                } else { Text(lyrics.plainText).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text("歌词来源：\(lyrics.source)").font(.caption).foregroundStyle(.secondary)
            } else { Text(error ?? "暂无匹配歌词").foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).glassCard()
            .task(id: song.id) { await load() }
    }
    private func load() async {
        lyrics = nil; error = nil; loading = true; defer { loading = false }
        do { let result = try await LyricsService.shared.lyrics(for: song); try Task.checkCancellation(); lyrics = result }
        catch { if !Task.isCancelled { self.error = "歌词暂时无法加载：\(error.localizedDescription)" } }
    }
}

struct LibraryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var account: YouTubeAccount
    @State private var export = false
    @State private var importFile = false
    @State private var document = LibraryDocument(data: Data())
    @State private var pendingRestore: Data?
    @State private var confirmRestore = false
    @State private var clear = false
    @State private var message: String?
    @State private var streamURL = ""
    var body: some View {
        Form {
            Section("YouTube 账号") {
                if let configuration = account.configurationMessage { Text(configuration).font(.footnote).foregroundStyle(.secondary) }
                if account.isSignedIn {
                    Label(account.displayName, systemImage: "person.crop.circle.badge.checkmark")
                    Button("导入云端歌单") { account.importPlaylists(into: library) }.disabled(account.isBusy)
                    Button("退出账号", role: .destructive) { account.signOut() }
                } else { Button("登录 Google / YouTube") { account.signIn() }.disabled(account.configurationMessage != nil || account.isBusy) }
                if account.isBusy { ProgressView() }
                if let status = account.message { Text(status).font(.footnote).textSelection(.enabled) }
                Text("导入会更新之前导入的同一云端歌单。本地歌单可在详情页手动上传；新建云端副本默认为私密。YouTube Music 专属资料可能不在官方 API 的开放范围内。").font(.caption).foregroundStyle(.secondary)
            }
            Section("资料备份") {
                Button("导出收藏、歌单、历史和队列") { do { document = LibraryDocument(data: try library.exportedData()); export = true } catch { message = error.localizedDescription } }
                Button("从 JSON 备份恢复…") { importFile = true }
                if let error = library.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section("历史") { Button("清除搜索和播放历史", role: .destructive) { clear = true } }
            Section("HTTPS 音频直链") {
                TextField("https://…", text: $streamURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("播放直链") { if let url = URL(string: streamURL), url.scheme?.lowercased() == "https" { player.play(Track(title: url.lastPathComponent, artist: "音频直链", streamURL: url)) } }.disabled(URL(string: streamURL)?.scheme?.lowercased() != "https")
            }
            Section("关于") {
                Text("Mochy Music iOS 0.2.1")
                Link("项目主页", destination: URL(string: "https://github.com/Joshliew33/Mochy-Music")!)
                Link("歌词服务 · LRCLIB", destination: URL(string: "https://lrclib.net")!)
                Text("歌词查询会将歌曲名称、歌手和时长发送给 LRCLIB；收藏、歌单和历史默认保存在本机。").font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.footnote).textSelection(.enabled) }
        }.navigationTitle("设置")
            .fileExporter(isPresented: $export, document: document, contentType: .json, defaultFilename: "MochyMusic-backup") { result in if case .failure(let error) = result { message = error.localizedDescription } }
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pendingRestore = try Data(contentsOf: url); confirmRestore = true
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog("用备份替换本机资料？建议先导出当前资料。", isPresented: $confirmRestore, titleVisibility: .visible) { Button("恢复备份", role: .destructive) { do { if let bytes = pendingRestore { try library.restore(bytes); player.restoreSavedQueue(); message = "备份已恢复。" } } catch { message = "恢复失败：\(error.localizedDescription)" }; pendingRestore = nil } }
            .confirmationDialog("清除本机搜索和播放历史？", isPresented: $clear, titleVisibility: .visible) { Button("清除", role: .destructive) { library.clearHistory() } }
    }
}
