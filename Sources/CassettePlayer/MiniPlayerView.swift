import SwiftUI
import AppKit

struct MiniPlayerView: View {

    @ObservedObject var audio: AudioPlayer
    @ObservedObject var levelMeter: AudioLevelMeter
    @Binding var alwaysOnTop: Bool
    let onReturnToMain: () -> Void

    private let green = Color(
        red: 0.025,
        green: 0.72,
        blue: 0.34
    )

    private let panelWidth: CGFloat = 600
    private let panelHeight: CGFloat = 60

    private var artistName: String {
        guard let track = audio.currentTrack else {
            return "NO TRACK LOADED"
        }
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? "UNKNOWN ARTIST" : artist
    }

    private var trackTitle: String {
        guard let track = audio.currentTrack else {
            return ""
        }
        let title = track.taggedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? track.title : title
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

            HStack(spacing: 5) {
                displayPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                verticalDivider

                transportControls

                verticalDivider

                Button(action: onReturnToMain) {
                    Color.clear
                }
                .buttonStyle(
                    TransportButtonStyle(
                        title: "↑",
                        isActive: false,
                        momentary: true,
                        buttonWidth: 34,
                        buttonHeight: 33
                    )
                )
                .help("Return to the main player")

                alwaysOnTopControl
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipped()
    }

    /// Shared cloudy plastic panel for both stereo meters and track metadata.
    private var displayPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.48))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.black.opacity(0.9), lineWidth: 2)
                }

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    Color(red: 0.002, green: 0.010, blue: 0.006)
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.055),
                            Color.clear,
                            Color.black.opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .padding(3)

            HStack(spacing: 8) {
                compactMeters
                    .frame(width: 123)

                VStack(alignment: .leading, spacing: 2) {
                    MiniScrollingTextLine(name: artistName, green: green, fontSize: 10)
                    MiniScrollingTextLine(name: trackTitle, green: green, fontSize: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .shadow(color: green.opacity(0.10), radius: 5, x: 0, y: 0)

            // Stronger frosted-plastic layer: more visible haze, soft highlights,
            // and a little more translucency without obscuring the readout.
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    Color(red: 0.006, green: 0.014, blue: 0.009)
                        .opacity(0.62)
                )
                .background {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.thinMaterial)
                        .opacity(0.22)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.060),
                                    Color.white.opacity(0.006),
                                    Color.black.opacity(0.34)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.085), lineWidth: 1)
                }
                .blur(radius: 0.65)
                .allowsHitTesting(false)

            // Wider, brighter shared halo, still diffused rather than a hard frame.
            RoundedRectangle(cornerRadius: 2)
                .stroke(green.opacity(0.16), lineWidth: 9)
                .blur(radius: 20)
                .allowsHitTesting(false)
        }
    }

    private var compactMeters: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("L")
                    .foregroundStyle(green)
                    .frame(width: 9, alignment: .leading)
                MiniMeterBar(level: levelMeter.leftLevel, green: green)
            }

            HStack(spacing: 4) {
                Text("R")
                    .foregroundStyle(green)
                    .frame(width: 9, alignment: .leading)
                MiniMeterBar(level: levelMeter.rightLevel, green: green)
            }
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .padding(.trailing, 1)
    }

    private var transportControls: some View {
        HStack(spacing: 5) {
            miniTransportButton("◀◀", help: "Previous track", action: audio.previous)

            Button(action: audio.togglePlayPause) {
                Color.clear
            }
            .buttonStyle(
                TransportButtonStyle(
                    title: audio.isPlaying ? "Ⅱ" : "▶",
                    isActive: audio.isPlaying,
                    momentary: false,
                    buttonWidth: 34,
                    buttonHeight: 33
                )
            )
            .help(audio.isPlaying ? "Pause" : "Play")

            miniTransportButton("▶▶", help: "Next track", action: audio.next)
        }
    }

    private func miniTransportButton(
        _ title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Color.clear
        }
        .buttonStyle(
            TransportButtonStyle(
                title: title,
                isActive: false,
                momentary: true,
                buttonWidth: 34,
                buttonHeight: 33
            )
        )
        .help(help)
    }

    private var alwaysOnTopControl: some View {
        Button {
            alwaysOnTop.toggle()
        } label: {
            VStack(spacing: 2) {
                Text("TOP")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        alwaysOnTop ? green : Color.white.opacity(0.45)
                    )

                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 14, height: 21)
                        .overlay {
                            Rectangle()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.78), Color(white: 0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                        }
                        .offset(y: alwaysOnTop ? -7 : 7)
                }
            }
            .frame(width: 22, height: 33)
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
            .frame(width: 1, height: 38)
    }
}

private struct MiniMeterBar: View {

    let level: Float
    let green: Color

    private let segmentCount = 14

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                let isActive = index < Int(
                    min(1, max(0, level)) * Float(segmentCount)
                )
                let color = index >= 10
                    ? Color(red: 0.92, green: 0.24, blue: 0.035)
                    : green

                HStack(spacing: 1) {
                    Rectangle()
                        .fill(color)
                        .opacity(isActive ? 0.95 : 0.13)
                        .shadow(
                            color: color.opacity(isActive ? 0.55 : 0),
                            radius: isActive ? 3.5 : 0
                        )

                    Rectangle()
                        .fill(color)
                        .opacity(isActive ? 0.95 : 0.13)
                        .shadow(
                            color: color.opacity(isActive ? 0.55 : 0),
                            radius: isActive ? 3.5 : 0
                        )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 8)
            }
        }
        .frame(height: 10)
        .padding(.horizontal, 3)
        .background(Color.black.opacity(0.75))
        .overlay {
            Rectangle()
                .stroke(Color.black.opacity(0.95), lineWidth: 1)
        }
    }
}

private struct MiniScrollingTextLine: View {

    let name: String
    let green: Color
    let fontSize: CGFloat

    @State private var offset: CGFloat = 0

    private let scrollSpeed: CGFloat = 32
    private let initialPause: Double = 1.1
    private let endPause: Double = 1.2

    private var textWidth: CGFloat {
        (name as NSString).size(
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
            ]
        ).width
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Text(name)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(green.opacity(0.22))
                    .fixedSize()
                    .blur(radius: 2)
                    .offset(x: -offset)

                Text(name)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(green)
                    .shadow(color: green.opacity(0.48), radius: 3, x: 0, y: 0)
                    .fixedSize()
                    .offset(x: -offset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: fontSize + 3)
            .clipped()
            .task(id: name + String(describing: fontSize)) {
                offset = 0
                let travel = max(0, textWidth - geometry.size.width)
                guard travel > 0 else { return }

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(initialPause * 1_000_000_000))
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
        .frame(height: fontSize + 3)
        .frame(maxWidth: .infinity)
    }
}
