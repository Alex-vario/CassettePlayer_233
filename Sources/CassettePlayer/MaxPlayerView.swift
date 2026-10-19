import SwiftUI
import AppKit
import AVFoundation
import CoreImage

/// Controls native macOS fullscreen transitions and mirrors the window's actual state.
final class FullscreenModeController: ObservableObject {
    @Published private(set) var isFullscreen = false

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var isTransitioning = false

    func attach(_ window: NSWindow) {
        guard self.window !== window else {
            if !isTransitioning {
                isFullscreen = window.styleMask.contains(.fullScreen)
            }
            return
        }

        removeObservers()
        self.window = window
        isFullscreen = window.styleMask.contains(.fullScreen)

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isFullscreen = true
                self?.isTransitioning = false
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isFullscreen = false
                self?.isTransitioning = false
            }
        )
    }

    func enterFullscreen() {
        guard let window, !isFullscreen, !isTransitioning else { return }
        isTransitioning = true
        isFullscreen = true
        window.toggleFullScreen(nil)
    }

    func exitFullscreen() {
        guard let window, isFullscreen, !isTransitioning else { return }
        isTransitioning = true
        isFullscreen = false
        window.toggleFullScreen(nil)
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        removeObservers()
    }
}

struct MaxPlayerView: View {
    @ObservedObject var audio: AudioPlayer
    let onExit: () -> Void

    @State private var coverImage: NSImage?
    @State private var blurredBackgroundImage: NSImage?
    @State private var artworkGeneration = 0

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    @State private var trackDurations: [URL: TimeInterval] = [:]
    @State private var playlistTotalDuration: TimeInterval = 0
    @State private var durationLoadGeneration = 0

    private static let imageContext = CIContext()

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let sidePadding = max(16, min(28, screenWidth * 0.018))
            let gap = max(12, min(20, screenWidth * 0.012))
            let usableWidth = max(760, screenWidth - sidePadding * 2 - gap * 2)
            let leftWidth = min(620, max(260, usableWidth * 0.29))
            let middleWidth = min(720, max(320, usableWidth * 0.32))
            let rightWidth = max(280, usableWidth - leftWidth - middleWidth)
            let coverSide = min(leftWidth - 32, max(160, screenHeight * 0.47))
            let infoHeight = min(max(screenHeight * 0.29, 180), 280)

            ZStack {
                backgroundLayer(size: geometry.size)

                HStack(alignment: .top, spacing: gap) {
                    leftPanel(coverSide: coverSide)
                        .frame(width: leftWidth)
                .frame(maxHeight: .infinity)

                    middlePanel(infoHeight: infoHeight)
                        .frame(width: middleWidth)
                .frame(maxHeight: .infinity)

                    rightPanel
                        .frame(width: rightWidth)
                .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, sidePadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(red: 0.025, green: 0.030, blue: 0.045))
        .ignoresSafeArea()
        .onAppear {
            prepareArtwork()
            loadPlaylistDurations()
        }
        .onChange(of: audio.currentTrack?.id) { _ in
            prepareArtwork()
        }
        .onChange(of: audio.playlist) { _ in
            loadPlaylistDurations()
        }
        .onExitCommand(perform: onExit)
    }

    // MARK: - Dynamic artwork background

    private func backgroundLayer(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.025, green: 0.030, blue: 0.045)

            if let image = blurredBackgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(1.18)
                    .id(audio.currentTrack?.id)
                    .transition(.opacity)
            }

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.42), location: 0),
                    .init(color: Color.black.opacity(0.58), location: 0.48),
                    .init(color: Color.black.opacity(0.76), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: Color.black.opacity(0.22), location: 0.68),
                    .init(color: Color.black.opacity(0.55), location: 1)
                ],
                center: .center,
                startRadius: 80,
                endRadius: max(size.width, size.height) * 0.72
            )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .animation(.easeInOut(duration: 0.85), value: audio.currentTrack?.id)
    }

    private func prepareArtwork() {
        artworkGeneration += 1
        let generation = artworkGeneration
        let artworkData = audio.currentTrack?.artwork

        guard let artworkData else {
            withAnimation(.easeInOut(duration: 0.65)) {
                coverImage = nil
                blurredBackgroundImage = nil
            }
            return
        }

        guard let original = NSImage(data: artworkData) else {
            withAnimation(.easeInOut(duration: 0.65)) {
                coverImage = nil
                blurredBackgroundImage = nil
            }
            return
        }

        let blurred = Self.makeBlurredBackground(from: artworkData)

        guard generation == artworkGeneration else { return }

        withAnimation(.easeInOut(duration: 0.85)) {
            coverImage = original
            blurredBackgroundImage = blurred
        }
    }

    /// The blur is rasterized once per track change, not recomputed during animation.
    private static func makeBlurredBackground(from data: Data) -> NSImage? {
        guard let source = CIImage(data: data) else { return nil }

        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 48])
            .cropped(to: source.extent)

        guard let cgImage = imageContext.createCGImage(blurred, from: source.extent) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    // MARK: - Left panel

    private func leftPanel(coverSide: CGFloat) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.34))

                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: coverSide, height: coverSide)
                        .accessibilityLabel("Обложка текущего альбома")
                        .id(audio.currentTrack?.id)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: min(coverSide * 0.28, 110), weight: .ultraLight))
                        Text("NO ARTWORK")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundStyle(Color.white.opacity(0.30))
                    .frame(width: coverSide, height: coverSide)
                }
            }
            .frame(width: coverSide, height: coverSide)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
            .frame(maxWidth: .infinity)

            progressControl

            HStack(spacing: 0) {
                transportButton("backward.end.fill", help: "Предыдущий трек") {
                    audio.previous()
                }

                Button {
                    audio.togglePlayPause()
                } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .frame(width: 58, height: 48)
                        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .help(audio.isPlaying ? "Пауза" : "Воспроизвести")

                transportButton("forward.end.fill", help: "Следующий трек") {
                    audio.next()
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 18) {
                modeButton(
                    audio.shuffle ? "shuffle" : "shuffle",
                    active: audio.shuffle,
                    help: "Случайное воспроизведение"
                ) {
                    audio.shuffle.toggle()
                }

                modeButton(
                    audio.repeatMode == 1 ? "repeat.1" : "repeat",
                    active: audio.repeatMode != 0,
                    help: repeatHelp
                ) {
                    audio.repeatMode = (audio.repeatMode + 1) % 3
                }

                Spacer(minLength: 0)

                Text(repeatLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                Button {
                    audio.toggleMute()
                } label: {
                    Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(audio.isMuted ? Color.orange.opacity(0.95) : Color.white.opacity(0.78))
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.plain)
                .help(audio.isMuted ? "Включить звук" : "Отключить звук")

                Slider(
                    value: Binding(
                        get: { Double(audio.volume) },
                        set: { audio.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(Color.white.opacity(0.86))

                Text("\(Int(audio.volume * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panelSurface()
    }

    private var progressControl: some View {
        VStack(spacing: 7) {
            HStack {
                Text(maxFormatTime(isSeeking ? seekTime : audio.playbackClock.currentTime))
                Spacer()
                Text(maxFormatTime(audio.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.65))

            Slider(
                value: Binding(
                    get: { isSeeking ? seekTime : audio.playbackClock.currentTime },
                    set: { seekTime = $0 }
                ),
                in: 0...max(audio.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        seekTime = audio.playbackClock.currentTime
                        isSeeking = true
                    } else {
                        if isSeeking {
                            audio.seek(to: seekTime)
                        }
                        isSeeking = false
                    }
                }
            )
            .tint(Color.white.opacity(0.90))
            .disabled(audio.duration <= 0)
        }
    }

    private func transportButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: 50, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func modeButton(
        _ symbol: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.green.opacity(0.95) : Color.white.opacity(0.56))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var repeatLabel: String {
        switch audio.repeatMode {
        case 1: return "REPEAT 1"
        case 2: return "REPEAT ALL"
        default: return "REPEAT OFF"
        }
    }

    private var repeatHelp: String {
        switch audio.repeatMode {
        case 0: return "Повтор выключен"
        case 1: return "Повтор текущего трека"
        default: return "Повтор плейлиста"
        }
    }

    // MARK: - Middle panel

    private func middlePanel(infoHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            trackInformation
                .frame(maxWidth: .infinity, minHeight: infoHeight, maxHeight: infoHeight, alignment: .topLeading)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            playlistPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelSurface()
    }

    private var trackInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOW PLAYING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.52))

            if let track = audio.currentTrack {
                Text(track.taggedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? track.title : track.taggedTitle)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(track.artist)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(2)
                }

                if !track.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(track.album)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(2)
                }

                Spacer(minLength: 2)

                Text(track.url.lastPathComponent)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(audioQualityLabel(for: track))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.66))
            } else {
                Spacer(minLength: 0)
                Text("Перетащите аудиофайлы в окно плеера или выберите композицию в библиотеке.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var playlistPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CURRENT PLAYLIST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.70))

                Spacer()

                Text("\(audio.playlist.count) TRACKS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(audio.playlist.enumerated()), id: \.element.id) { index, track in
                            playlistRow(track, index: index)
                                .id(track.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let id = audio.currentTrack?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onChange(of: audio.currentTrack?.id) { id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)

            HStack {
                Text("\(audio.playlist.count) треков")
                Spacer()
                Text(maxFormatTime(playlistTotalDuration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.58))
            .padding(.horizontal, 18)
            .frame(height: 38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    private func playlistRow(_ track: AudioTrack, index: Int) -> some View {
        let isCurrent = audio.currentTrack?.url == track.url
        let displayTitle = track.taggedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? track.title
            : track.taggedTitle

        return Button {
            audio.play(track)
        } label: {
            HStack(spacing: 10) {
                Text(isCurrent ? "▶" : String(format: "%02d", index + 1))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isCurrent ? Color.green.opacity(0.95) : Color.white.opacity(0.38))
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.78))
                        .lineLimit(1)

                    if !track.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(track.artist)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(maxFormatTime(trackDurations[track.url] ?? 0))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.095))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green.opacity(0.86))
                                .frame(width: 3)
                                .padding(.vertical, 6)
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        LibraryView(
            audio: audio,
            onClose: {},
            showsCloseButton: false,
            compactHeader: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }

    // MARK: - Playlist durations and metadata

    private func loadPlaylistDurations() {
        durationLoadGeneration += 1
        let generation = durationLoadGeneration
        let urls = audio.playlist.map(\.url)

        Task {
            let result = await Task.detached(priority: .utility) {
                () -> ([URL: TimeInterval], TimeInterval) in

                var loaded: [URL: TimeInterval] = [:]
                var total: TimeInterval = 0

                for url in urls {
                    do {
                        let file = try AVAudioFile(forReading: url)
                        let sampleRate = file.processingFormat.sampleRate
                        guard sampleRate > 0 else { continue }

                        let duration = Double(file.length) / sampleRate
                        loaded[url] = duration
                        total += duration
                    } catch {
                        continue
                    }
                }

                return (loaded, total)
            }.value

            guard generation == durationLoadGeneration else { return }
            trackDurations = result.0
            playlistTotalDuration = result.1
        }
    }

    private func audioQualityLabel(for track: AudioTrack) -> String {
        let format = track.url.pathExtension.uppercased()
        if format == "MP3" {
            return audio.bitrate > 0 ? "MP3 · \(audio.bitrate) kb/s" : "MP3"
        }
        if format == "FLAC" {
            return "FLAC · lossless"
        }
        return format.isEmpty ? "AUDIO" : format
    }
}

private extension View {
    func panelSurface() -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private func maxFormatTime(_ time: TimeInterval) -> String {
    guard time.isFinite, time >= 0 else { return "00:00" }
    let seconds = Int(time)
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let remainder = seconds % 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%02d:%02d", minutes, remainder)
}
