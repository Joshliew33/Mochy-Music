import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var showPlayer = false

    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("首页", systemImage: "house.fill") }
            NavigationStack { SearchView() }.tabItem { Label("搜索", systemImage: "magnifyingglass") }
            NavigationStack { MusicLibraryView() }.tabItem { Label("音乐库", systemImage: "square.stack.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.mint)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let error = player.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity).background(.ultraThinMaterial)
                }
                if player.currentSong != nil || player.currentTrack != nil { miniPlayer }
            }
        }
        .sheet(isPresented: $showPlayer) { PlayerView() }
        .preferredColorScheme(.dark)
    }
    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Button { showPlayer = true } label: {
                HStack(spacing: 12) {
                    CoverImage(url: player.currentSong?.thumbnailURL ?? player.currentTrack?.artworkURL, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.currentSong?.title ?? player.currentTrack?.title ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.isBuffering ? "正在加载…" : player.currentSong?.artist ?? player.currentTrack?.artist ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain).accessibilityLabel("打开播放器")
            Button { player.togglePlayback() } label: {
                Image(systemName: player.isPlaying || player.isBuffering ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(player.isPlaying || player.isBuffering ? "暂停" : "播放")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 40, height: 44) }
                .disabled(!player.queue.canNext).accessibilityLabel("下一首")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(.regularMaterial)
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CoverImage(url: player.currentSong?.thumbnailURL ?? player.currentTrack?.artworkURL, size: 240).shadow(color: .mint.opacity(0.12), radius: 30)
                    VStack(spacing: 6) {
                        Text(player.currentSong?.title ?? player.currentTrack?.title ?? "尚未播放").font(.title2.bold()).multilineTextAlignment(.center)
                        Text(player.currentSong?.artist ?? player.currentTrack?.artist ?? "").foregroundStyle(.secondary)
                    }
                    if let error = player.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { min(max(0, player.elapsedTime), max(1, player.duration)) }, set: player.seek), in: 0...max(1, player.duration)).disabled(player.duration <= 0)
                        HStack { Text(time(player.elapsedTime)); Spacer(); Text(time(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 36) {
                        Button { player.previous() } label: { Image(systemName: "backward.end.fill").font(.title) }.disabled(player.currentSong == nil).accessibilityLabel("上一首")
                        Button { player.togglePlayback() } label: { Image(systemName: player.isPlaying || player.isBuffering ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64)) }.accessibilityLabel(player.isPlaying || player.isBuffering ? "暂停" : "播放")
                        Button { player.next() } label: { Image(systemName: "forward.end.fill").font(.title) }.disabled(!player.queue.canNext).accessibilityLabel("下一首")
                    }
                    if player.isBuffering { ProgressView("加载音频…") }
                    HStack {
                        Button { player.toggleShuffle() } label: { Label("随机", systemImage: "shuffle").foregroundStyle(player.queue.isShuffled ? Color.mint : Color.secondary) }
                        Spacer()
                        Button { player.cycleRepeat() } label: { Label(player.queue.repeatMode.label, systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat").foregroundStyle(player.queue.repeatMode == .off ? Color.secondary : Color.mint) }
                        Spacer()
                        if let song = player.currentSong { Button { library.toggleFavorite(song) } label: { Image(systemName: library.isFavorite(song) ? "heart.fill" : "heart") }.accessibilityLabel("收藏") }
                    }.font(.subheadline)
                    NavigationLink { QueueView() } label: { Label("播放队列（\(player.queue.entries.count)）", systemImage: "list.bullet") }
                    if let song = player.currentSong { LyricsPanel(song: song) }
                }.padding(24)
            }.navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }.tint(.mint).preferredColorScheme(.dark)
    }
    private func time(_ seconds: Double) -> String { let n = seconds.isFinite ? max(0, Int(seconds)) : 0; return "\(n / 60):\(String(format: "%02d", n % 60))" }
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
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
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
                Text("Mochy Music iOS 0.2")
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
