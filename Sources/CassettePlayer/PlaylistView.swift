import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct PlaylistView: View {

    @ObservedObject var audio: AudioPlayer
    let onClose: () -> Void

    private let panelWidth: CGFloat = 180
    private let panelHeight: CGFloat = 283

    @State private var durations: [URL: TimeInterval] = [:]
    @State private var totalDuration: TimeInterval = 0

    var body: some View {
        ZStack {
            panelBackground

            VStack(spacing: 0) {
                playlistHeader

                playlistDivider

                playlistContent

                playlistFooter
            }
            .padding(.horizontal, 7)
            .padding(.top, 8)
            .padding(.bottom, 7)
        }
        .frame(
            width: panelWidth,
            height: panelHeight
        )
        .onAppear {
            loadDurations()
        }
        .onChange(of: audio.playlist) { _ in
            loadDurations()
        }

        .onChange(of: audio.currentTrack) { newTrack in
            scrollToCurrentTrack(newTrack)
        }
    }

    // MARK: - Panel

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(
                                color: Color(
                                    red: 0.115,
                                    green: 0.120,
                                    blue: 0.125
                                ),
                                location: 0.00
                            ),
                            .init(
                                color: Color(
                                    red: 0.075,
                                    green: 0.078,
                                    blue: 0.082
                                ),
                                location: 0.18
                            ),
                            .init(
                                color: Color(
                                    red: 0.095,
                                    green: 0.098,
                                    blue: 0.102
                                ),
                                location: 0.52
                            ),
                            .init(
                                color: Color(
                                    red: 0.060,
                                    green: 0.063,
                                    blue: 0.067
                                ),
                                location: 1.00
                            )
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    Color.white.opacity(0.10),
                    lineWidth: 1
                )
                .padding(1)

            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    Color.black.opacity(0.95),
                    lineWidth: 2
                )
                .padding(2)
                .offset(x: 0.7, y: 0.7)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.025),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    // MARK: - Header

    private var playlistHeader: some View {
        HStack(spacing: 0) {
            Text("PLAYLIST")
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.78)
                )

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.right")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.55)
                    )
                    .frame(
                        width: 24,
                        height: 22
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close playlist")
        }
        .frame(height: 22)
    }

    private var playlistDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.75))
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .offset(y: -1)
            )
    }

    // MARK: - List

    private var playlistContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(
                        Array(audio.playlist.enumerated()),
                        id: \.element.id
                    ) { index, track in

                        PlaylistTrackRow(
                            number: index + 1,
                            track: track,
                            duration: durations[track.url] ?? 0,
                            isCurrent:
                                audio.currentTrack?.url == track.url
                        )
                        .id(track.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            audio.play(track)
                        }
                    }
                }
            }
            .onAppear {
                scrollToCurrentTrack(
                    audio.currentTrack,
                    proxy: proxy
                )
            }
            .onChange(of: audio.currentTrack) { newTrack in
                scrollToCurrentTrack(
                    newTrack,
                    proxy: proxy
                )
            }
        }
        .clipped()
    }

    // MARK: - Footer

    private var playlistFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.75))
                .frame(height: 1)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .offset(y: -1)
                )

            HStack {
                Spacer()

                Text(formatDuration(totalDuration))
                    .font(
                        .system(
                            size: 9,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.70)
                    )
            }
            .frame(height: 21)
        }
    }

    // MARK: - Duration loading

    private func loadDurations() {
        let tracks = audio.playlist

        Task {
            var loaded: [URL: TimeInterval] = [:]
            var total: TimeInterval = 0

            for track in tracks {
                do {
                    let file = try AVAudioFile(
                        forReading: track.url
                    )

                    let sampleRate =
                        file.processingFormat.sampleRate

                    guard sampleRate > 0 else {
                        continue
                    }

                    let duration =
                        Double(file.length) / sampleRate

                    loaded[track.url] = duration
                    total += duration
                } catch {
                    loaded[track.url] = 0
                }
            }

            await MainActor.run {
                durations = loaded
                totalDuration = total
            }
        }
    }

    // MARK: - Current track scrolling

    private func scrollToCurrentTrack(
        _ track: AudioTrack?
    ) {
        // Actual scrolling is handled by ScrollViewReader.
        // This method intentionally remains empty because
        // the reader is recreated with the current playlist state.
    }

    private func scrollToCurrentTrack(
        _ track: AudioTrack?,
        proxy: ScrollViewProxy
    ) {
        guard let track else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(
                    track.id,
                    anchor: .center
                )
            }
        }
    }

    // MARK: - Formatting

    private func formatDuration(
        _ duration: TimeInterval
    ) -> String {
        guard duration.isFinite, duration >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(duration.rounded())

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}

// MARK: - Track row

private struct PlaylistTrackRow: View {

    let number: Int
    let track: AudioTrack
    let duration: TimeInterval
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 3) {

            Text(
                String(
                    format: "%02d",
                    number
                )
            )
            .font(
                .system(
                    size: 10,
                    weight: .medium,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                isCurrent
                    ? Color.white.opacity(0.90)
                    : Color.white.opacity(0.42)
            )
            .frame(
                width: 15,
                alignment: .leading
            )

            Text(
                track.artist.isEmpty
                    ? track.title
                    : "\(track.artist) — \(track.title)"
            )
            .font(
                .system(
                    size: 10,
                    weight: isCurrent ? .semibold : .regular,
                    design: .default
                )
            )
            .foregroundStyle(
                isCurrent
                    ? Color.white.opacity(0.94)
                    : Color.white.opacity(0.72)
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Text(
                formatDuration(duration)
            )
            .font(
                .system(
                    size: 10,
                    weight: .medium,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                isCurrent
                    ? Color.white.opacity(0.88)
                    : Color.white.opacity(0.52)
            )
            .frame(
                width: 31,
                alignment: .trailing
            )
        }
        .padding(.horizontal, 2)
        .frame(
            height: 20
        )
        .background(
            isCurrent
                ? Color.white.opacity(0.085)
                : Color.clear
        )
        .overlay(alignment: .leading) {
            if isCurrent {
                Rectangle()
                    .fill(
                        Color(
                            red: 0.025,
                            green: 0.72,
                            blue: 0.34
                        ).opacity(0.85)
                    )
                    .frame(width: 2)
            }
        }
    }

    private func formatDuration(
        _ duration: TimeInterval
    ) -> String {
        guard duration.isFinite, duration >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(duration.rounded())

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }
}