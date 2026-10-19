import SwiftUI
import AppKit

struct MiniPlayerView: View {

    @ObservedObject var audio: AudioPlayer
    @Binding var alwaysOnTop: Bool
    let onReturnToMain: () -> Void

    private let green = Color(
        red: 0.025,
        green: 0.72,
        blue: 0.34
    )

    private let panelWidth: CGFloat = 520
    private let panelHeight: CGFloat = 104

    private var trackTitle: String {
        guard let track = audio.currentTrack else {
            return "NO TRACK LOADED"
        }

        return track.artist.isEmpty
            ? track.title
            : "\(track.artist) — \(track.title)"
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.13),
                            Color(white: 0.075),
                            Color(white: 0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Rectangle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .padding(1)

            Rectangle()
                .stroke(Color.black.opacity(0.9), lineWidth: 1)
                .padding(3)

            HStack(spacing: 8) {
                compactMeters
                    .frame(width: 92)

                verticalDivider

                MiniScrollingTrackTitle(
                    name: trackTitle,
                    green: green
                )
                .frame(maxWidth: .infinity)

                verticalDivider

                transportControls

                verticalDivider

                Button(action: onReturnToMain) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(green)
                        .frame(width: 30, height: 42)
                        .background(Color.black.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Return to the main player")

                alwaysOnTopControl
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipped()
    }

    private var compactMeters: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Text("L")
                    .foregroundStyle(green)
                    .frame(width: 9, alignment: .leading)

                MiniMeterBar(level: audio.levelMeter.leftLevel, green: green)
            }

            HStack(spacing: 5) {
                Text("R")
                    .foregroundStyle(Color(red: 0.92, green: 0.24, blue: 0.035))
                    .frame(width: 9, alignment: .leading)

                MiniMeterBar(
                    level: audio.levelMeter.rightLevel,
                    green: green
                )
            }
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .padding(.trailing, 2)
    }

    private var transportControls: some View {
        HStack(spacing: 4) {
            transportButton(
                symbol: "backward.end.fill",
                help: "Previous track",
                action: audio.previous
            )

            transportButton(
                symbol: audio.isPlaying ? "pause.fill" : "play.fill",
                help: audio.isPlaying ? "Pause" : "Play",
                action: audio.togglePlayPause
            )
            .frame(width: 36, height: 42)

            transportButton(
                symbol: "forward.end.fill",
                help: "Next track",
                action: audio.next
            )
        }
    }

    private func transportButton(
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(green.opacity(0.95))
                .frame(width: 32, height: 42)
                .background(
                    LinearGradient(
                        colors: [Color(white: 0.17), Color(white: 0.075)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var alwaysOnTopControl: some View {
        Button {
            alwaysOnTop.toggle()
        } label: {
            VStack(spacing: 4) {
                Text("TOP")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        alwaysOnTop ? green : Color.white.opacity(0.45)
                    )

                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 18, height: 42)
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(white: 0.78),
                                    Color(white: 0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 12, height: 12)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                        }
                        .offset(y: alwaysOnTop ? -11 : 11)
                }
            }
            .frame(width: 26, height: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Always on Top — keep Mini Player above other windows")
        .accessibilityLabel("Always on Top")
        .accessibilityValue(alwaysOnTop ? "On" : "Off")
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 54)
    }
}

private struct MiniMeterBar: View {

    let level: Float
    let green: Color

    private let segmentCount = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let isActive = index < Int(
                    min(1, max(0, level)) * Float(segmentCount)
                )
                let color = index >= 9
                    ? Color(red: 0.92, green: 0.24, blue: 0.035)
                    : green

                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .opacity(isActive ? 0.95 : 0.13)
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.75))
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.black.opacity(0.95), lineWidth: 1)
        }
    }
}

private struct MiniScrollingTrackTitle: View {

    let name: String
    let green: Color

    @State private var offset: CGFloat = 0

    private let fontSize: CGFloat = 11
    private let scrollSpeed: CGFloat = 32
    private let initialPause: Double = 1.1
    private let endPause: Double = 1.2

    private var textWidth: CGFloat {
        (name as NSString).size(
            withAttributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: fontSize,
                    weight: .medium
                )
            ]
        ).width
    }

    private var travel: CGFloat {
        max(0, textWidth - 190)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NOW PLAYING")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.42))

            ZStack(alignment: .leading) {
                Text(name)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(green.opacity(0.22))
                    .fixedSize()
                    .blur(radius: 3)
                    .offset(x: -offset)

                Text(name)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(green)
                    .fixedSize()
                    .offset(x: -offset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 17)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: name) {
            offset = 0
            guard travel > 0 else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(initialPause * 1_000_000_000)
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                let duration = Double(travel / scrollSpeed)
                withAnimation(.linear(duration: duration)) {
                    offset = travel
                }

                do {
                    try await Task.sleep(
                        nanoseconds: UInt64((duration + endPause) * 1_000_000_000)
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                offset = 0
            }
        }
    }
}
