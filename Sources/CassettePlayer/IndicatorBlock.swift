import SwiftUI

struct IndicatorBlock: View {

    @ObservedObject var audio: AudioPlayer
    let showPlaylist: Bool
    var body: some View {
        ZStack {

            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.48))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            Color.black.opacity(0.9),
                            lineWidth: 2
                        )
                }

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    Color(
                        red: 0.008,
                        green: 0.045,
                        blue: 0.028
                    )
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.025),
                            Color.clear,
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 2)
                    )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(
                            Color.white.opacity(0.07),
                            lineWidth: 1
                        )
                }
                .padding(3)

            // =================================================
            // MAIN INDICATOR CONTENT
            // =================================================

            VStack(spacing: 5) {

                HStack(spacing: 8) {

                    ZStack(alignment: .leading) {

                        VStack(spacing: 14) {

                            LevelMeter(
                                channel: "Л",
                                level: audio.leftLevel
                            )

                            LevelMeter(
                                channel: "П",
                                level: audio.rightLevel
                            )
                        }

                        Text("-20")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color(
                                    red: 0.025,
                                    green: 0.72,
                                    blue: 0.34
                                )
                                .opacity(1)
                            )
                            .position(
                                x: 14,
                                y: 26
                            )

                        Text("-10")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color(
                                    red: 0.025,
                                    green: 0.72,
                                    blue: 0.34
                                )
                                .opacity(1)
                            )
                            .position(
                                x: 67,
                                y: 26
                            )

                        Text("0")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color(
                                    red: 0.025,
                                    green: 0.72,
                                    blue: 0.34
                                )
                                .opacity(1)
                            )
                            .position(
                                x: 125.5,
                                y: 26
                            )

                        Text("+4 dB")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color(
                                    red: 0.025,
                                    green: 0.72,
                                    blue: 0.34
                                )
                                .opacity(1)
                            )
                            .position(
                                x: 181.5,
                                y: 26
                            )
                    }
                    .frame(
                        width: 238,
                        height: 52
                    )

                    IndicatorIcons(
                        audio: audio,
                        showPlaylist: showPlaylist
                    )
                    .frame(
                        width: 48,
                        height: 46
                    )
                }

                ScrollingTrackName(
                    name:
                        audio.currentTrack?.url.lastPathComponent
                        ?? "nothing.mp3"
                )
                .id(
                    audio.currentTrack?.url
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)

            // =================================================
            // OLD PLASTIC GLASS
            // =================================================

            RoundedRectangle(cornerRadius: 2)
                .fill(
                    Color(
                        red: 0.025,
                        green: 0.045,
                        blue: 0.035
                    )
                    .opacity(0.15)
                )
                .background {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.thinMaterial)
                        .opacity(0.10)
                }
                .overlay {

                    RoundedRectangle(cornerRadius: 2)
                        .stroke(
                            Color.white.opacity(0.045),
                            lineWidth: 1
                        )
                }
                .blur(radius: 0.35)
                .allowsHitTesting(false)

            // =================================================
            // SOFT LIGHT HALO
            // =================================================

            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    Color(
                        red: 0.025,
                        green: 0.72,
                        blue: 0.34
                    )
                    .opacity(0.100),
                    lineWidth: 7
                )
                .blur(radius: 20)
                .allowsHitTesting(false)
        }
    }
}

// =====================================================
// SCROLLING TRACK NAME
// =====================================================

private struct ScrollingTrackName: View {

    let name: String

    @State private var offset: CGFloat = 0

    private let green = Color(
        red: 0.025,
        green: 0.72,
        blue: 0.34
    )

    private let visibleWidth: CGFloat = 311
    private let characterWidth: CGFloat = 6.6

    private let speed: CGFloat = 35
    private let initialPause: TimeInterval = 1.2
    private let endPause: TimeInterval = 1.5

    private var textWidth: CGFloat {
        CGFloat(name.count) * characterWidth
    }

    private var travel: CGFloat {
        max(
            0,
            textWidth - visibleWidth
        )
    }

    var body: some View {

        ZStack(alignment: .leading) {

            Text(name)
                .font(
                    .system(
                        size: 11,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(green)
                .fixedSize()
                .blur(radius: 4.0)
                .opacity(0.45)
                .offset(x: -offset)

            Text(name)
                .font(
                    .system(
                        size: 11,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    green.opacity(0.72)
                )
                .fixedSize()
                .offset(x: -offset)
        }
        .frame(
            width: visibleWidth,
            height: 16,
            alignment: .leading
        )
        .clipped()
        .id(name)
        .onAppear {
            startScrolling()
        }
        .onDisappear {
            offset = 0
        }
    }

    private func startScrolling() {

        guard travel > 0 else {
            return
        }

        offset = 0

        let duration =
            Double(travel / speed)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + initialPause
        ) {

            withAnimation(
                .linear(
                    duration: duration
                )
            ) {
                offset = travel
            }

            DispatchQueue.main.asyncAfter(
                deadline:
                    .now()
                    + duration
                    + endPause
            ) {

                offset = 0

                startScrolling()
            }
        }
    }
}

// =====================================================
// HORIZONTAL LEVEL METER
// =====================================================

private struct LevelMeter: View {

    let channel: String
    let level: Float

    private let segmentCount = 14

    var body: some View {

        HStack(spacing: 4) {

            ZStack {

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black.opacity(0.88))

                HStack(spacing: 6) {

                    ForEach(
                        0..<segmentCount,
                        id: \.self
                    ) { index in

                        LevelSegment(
                            index: index,
                            level: level
                        )
                    }
                }
                .frame(
                    width: 185,
                    alignment: .leading
                )
                .padding(.leading, 5)

                RoundedRectangle(cornerRadius: 1)
                    .stroke(
                        Color.black.opacity(0.95),
                        lineWidth: 1
                    )
                    .padding(1)
            }
            .frame(
                width: 185,
                height: 19
            )

            Text(channel)
                .font(
                    .system(
                        size: 10,
                        weight: .regular,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color(
                        red: 0.025,
                        green: 0.72,
                        blue: 0.34
                    )
                )
                .frame(
                    width: 10,
                    alignment: .leading
                )
        }
        .frame(
            width: 252,
            height: 19,
            alignment: .leading
        )
    }
}

// =====================================================
// LEVEL SEGMENT
// =====================================================

private struct LevelSegment: View {

    let index: Int
    let level: Float

    @State private var displayedLevel: Float = 0

    private let segmentCount = 14
    private let releaseTime: TimeInterval = 0.35

    private var isRed: Bool {
        index >= 10
    }

    private var segmentColor: Color {

        if isRed {
            return Color(
                red: 0.92,
                green: 0.24,
                blue: 0.035
            )
        }

        return Color(
            red: 0.025,
            green: 0.72,
            blue: 0.34
        )
    }

    private var isActive: Bool {

        let normalized =
            min(
                max(displayedLevel, 0),
                1
            )

        let activeCount =
            Int(
                normalized *
                Float(segmentCount)
            )

        return index < activeCount
    }

    var body: some View {

        HStack(spacing: 1) {

            RoundedRectangle(cornerRadius: 0.5)
                .fill(segmentColor)

            RoundedRectangle(cornerRadius: 0.5)
                .fill(segmentColor)
        }
        .frame(
            width: 7,
            height: 8
        )
        .opacity(
            isActive
            ? 1
            : 0.12
        )
        .onAppear {
            displayedLevel = level
        }
        .onReceive(
            Timer.publish(
                every: 0.02,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in

            if level >= displayedLevel {

                displayedLevel = level

            } else {

                let difference =
                    displayedLevel - level

                let step =
                    difference *
                    Float(
                        0.02 /
                        releaseTime
                    )

                displayedLevel =
                    max(
                        level,
                        displayedLevel - step
                    )
            }
        }
    }
}

// =====================================================
// RIGHT-SIDE INDICATORS
// =====================================================

private struct IndicatorIcons: View {

    @ObservedObject var audio: AudioPlayer
    let showPlaylist: Bool

    private let green = Color(
        red: 0.025,
        green: 0.72,
        blue: 0.34
    )

    var body: some View {

        VStack(spacing: 14) {

            HStack(spacing: 12) {
                IndicatorMark("⇄", color: green)
                IndicatorMark("↻", color: green)
                IndicatorMark(
                    "M",
                    color: green,
                    isActive: audio.isMuted
                )
            }

            HStack(spacing: 12) {
                IndicatorMark("ST", color: green)
                IndicatorMark(
                    "PL",
                    color: green,
                    isActive: showPlaylist
                )
                IndicatorMark(
                    audio.bitrate > 0
                    ? "\(audio.bitrate)"
                    : "---",
                    color: green
                )
            }
        }
        .frame(
            width: 48,
            height: 46
        )
        .offset(x: -15)
    }
}

// =====================================================
// INDICATOR MARK
// =====================================================

private struct IndicatorMark: View {

    let text: String
    let color: Color
    let isActive: Bool

    init(
        _ text: String,
        color: Color,
        isActive: Bool = true
    ) {
        self.text = text
        self.color = color
        self.isActive = isActive
    }

    var body: some View {

        ZStack {

            Rectangle()
                .fill(
                    Color(
                        red: 0.008,
                        green: 0.018,
                        blue: 0.012
                    )
                )

            Rectangle()
                .fill(
                    Color(
                        red: 0.015,
                        green: 0.075,
                        blue: 0.045
                    )
                    .opacity(1)
                )

            LinearGradient(
                stops: [
                    .init(
                        color: Color.white.opacity(0.025),
                        location: 0.00
                    ),
                    .init(
                        color: Color.clear,
                        location: 0.28
                    ),
                    .init(
                        color: Color.black.opacity(0.12),
                        location: 1.00
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if isActive {
                Text(text)
                    .font(
                        .system(
                            size: 10,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(color)
                    .blur(radius: 4.5)
                    .opacity(0.55)

                Text(text)
                    .font(
                        .system(
                            size: 10,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(color.opacity(0.72))
            }

            Rectangle()
                .fill(
                    Color(
                        red: 0.004,
                        green: 0.020,
                        blue: 0.012
                    )
                    .opacity(0.16)
                )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.025),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )

            Rectangle()
                .stroke(
                    Color.black.opacity(0.95),
                    lineWidth: 1
                )
                .padding(0.5)

            Rectangle()
                .stroke(
                    Color.white.opacity(0.07),
                    lineWidth: 1
                )
                .padding(1.5)
        }
        .frame(
            width: 20,
            height: 18
        )
    }
}