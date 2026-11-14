import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @StateObject private var search = YouTubeMusicSearch()
    @State private var query = ""
    @State private var streamURL = ""
    @State private var title = ""

    private var parsedURL: URL? {
        guard let url = URL(string: streamURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    searchSection
                    if let track = audioPlayer.currentTrack { nowPlaying(track) }
                    directStreamSection
                    if let error = audioPlayer.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("playback-error")
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Mochy Music")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find your next song")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Search YouTube Music")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Songs, artists, albums", text: $query)
                    .submitLabel(.search)
                    .onSubmit { search.search(query) }
                    .accessibilityLabel("Search YouTube Music")
                if !query.isEmpty {
                    Button { query = ""; search.search("") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
                Button { search.search(query) } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(.mint)
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.isLoading)
                .accessibilityLabel("Search")
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

            if search.isLoading {
                ProgressView("Searching YouTube Music…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if let error = search.errorMessage {
                Text(error).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
            }

            ForEach(search.results) { song in
                songRow(song)
                if song.id != search.results.last?.id { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func songRow(_ song: CatalogSong) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: song.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(Color.mint.opacity(0.18))
                    .overlay { Image(systemName: "music.note").foregroundStyle(.mint) }
            }
            .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text([song.artist, song.duration].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: "https://music.youtube.com/watch?v=\(song.id)")!) {
                Image(systemName: "arrow.up.right.square").foregroundStyle(.mint)
            }
            .accessibilityLabel("Open \(song.title) in YouTube Music")
        }
        .padding(.vertical, 3)
    }

    private var directStreamSection: some View {
        DisclosureGroup("Play a direct audio URL") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Track title", text: $title)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.sentences)
                TextField("https://… audio stream URL", text: $streamURL)
                    .textFieldStyle(.roundedBorder).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button {
                    guard let url = parsedURL else { return }
                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    audioPlayer.play(Track(title: cleanTitle.isEmpty ? url.lastPathComponent : cleanTitle,
                                           artist: "Mochy Music", streamURL: url))
                } label: {
                    Label("Play stream", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).tint(.mint).disabled(parsedURL == nil)
            }
            .padding(.top, 12)
        }
        .font(.headline)
        .tint(.mint)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16).fill(.mint.gradient).frame(width: 64, height: 64)
                    .overlay { Image(systemName: "music.note").font(.title2.weight(.semibold)).foregroundStyle(.black.opacity(0.8)) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing").font(.caption.weight(.semibold)).foregroundStyle(.mint)
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                Slider(value: Binding(get: { audioPlayer.elapsedTime }, set: { audioPlayer.seek(to: $0) }),
                       in: 0...max(audioPlayer.duration, 1))
                    .tint(.mint).disabled(audioPlayer.duration <= 0)
                HStack {
                    Text(timestamp(audioPlayer.elapsedTime)); Spacer(); Text(timestamp(audioPlayer.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { audioPlayer.togglePlayback() } label: {
                Label(audioPlayer.isPlaying ? "Pause" : "Resume",
                      systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(.mint)
        }
        .padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func timestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
