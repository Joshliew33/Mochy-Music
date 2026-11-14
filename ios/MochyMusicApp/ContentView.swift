import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @State private var streamURL = ""
    @State private var title = ""

    private var parsedURL: URL? {
        guard let url = URL(string: streamURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    streamEntry
                    if let track = audioPlayer.currentTrack {
                        nowPlaying(track)
                    } else {
                        emptyState
                    }
                    if let error = audioPlayer.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("playback-error")
                    }
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Mochy Music")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your music,")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("ready to play.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.mint)
            Text("The native iOS playback foundation for Mochy Music.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private var streamEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play a stream")
                .font(.headline)

            TextField("Track title", text: $title)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel("Track title")

            TextField("https://… audio stream URL", text: $streamURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Audio stream URL")

            Button {
                guard let url = parsedURL else { return }
                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                audioPlayer.play(
                    Track(
                        title: cleanTitle.isEmpty ? url.lastPathComponent : cleanTitle,
                        artist: "Mochy Music",
                        streamURL: url
                    )
                )
            } label: {
                Label("Play stream", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .disabled(parsedURL == nil)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(.mint)
            Text("Start with a direct audio URL")
                .font(.headline)
            Text("This first slice wires up native streaming playback. Search providers and library sync will be added in later steps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
    }

    private func nowPlaying(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.mint.gradient)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.8))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                    Text(track.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { audioPlayer.elapsedTime },
                        set: { audioPlayer.seek(to: $0) }
                    ),
                    in: 0...max(audioPlayer.duration, 1)
                )
                .tint(.mint)
                .disabled(audioPlayer.duration <= 0)

                HStack {
                    Text(timestamp(audioPlayer.elapsedTime))
                    Spacer()
                    Text(timestamp(audioPlayer.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                audioPlayer.togglePlayback()
            } label: {
                Label(
                    audioPlayer.isPlaying ? "Pause" : "Resume",
                    systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
    private func timestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(seconds))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
