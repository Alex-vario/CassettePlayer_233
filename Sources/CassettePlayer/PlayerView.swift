import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation

struct PlayerView: View {

    @EnvironmentObject private var audio: AudioPlayer

    @State private var showPlaylist = false
    @State private var showLibrary = false

    // MARK: - Geometry

    private let deckWidth: CGFloat = 1024
    private let deckHeight: CGFloat = 283

    private let edgeInset: CGFloat = 25
    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 20

    // MARK: - Block sizes

    private let indicatorSize =
        CGSize(width: 321, height: 85)

    private let eqSize =
        CGSize(width: 321, height: 91)

    private let albumSize =
        CGSize(width: 137, height: 176)

    private let cassetteSize =
        CGSize(width: 307, height: 176)

    private let cassetteButtonSize =
        CGSize(width: 142, height: 28)

    private let timerSize =
        CGSize(width: 142, height: 28)

    private let transportSize =
        CGSize(width: 142, height: 171)

    private let lowerButtonsSize =
        CGSize(width: 321, height: 43)

    private let volumeSize =
        CGSize(width: 137, height: 43)

    private let progressSize =
        CGSize(width: 307, height: 43)

    // MARK: - EQ state

    @State private var eqValues: [Float] =
        Array(repeating: 0, count: 10)

    // MARK: - Body

var body: some View {

        ZStack {

            deckBackground

            deckLayout

            if showLibrary {

                LibraryView(
                    audio: audio,
                    onClose: {

                        withAnimation(
                            .easeInOut(
                                duration: 0.32
                            )
                        ) {
                            showLibrary = false
                        }
                    }
                )
                .frame(
                    width: deckWidth,
                    height: deckHeight
                )
                .transition(
                    .move(
                        edge: .top
                    )
                )
                .zIndex(200)
            }
        }
        .frame(
            width: deckWidth,
            height: deckHeight
        )
        .clipped()
        .animation(
            .easeInOut(
                duration: 0.32
            ),
            value: showLibrary
        )
        .onDrop(
            of: [
                UTType.fileURL.identifier
            ],
            isTargeted: nil
        ) { providers in

            handleDrop(
                providers
            )

            return true
        }
    }

    // MARK: - Drag and drop

    private func handleDrop(
        _ providers: [NSItemProvider]
    ) {

        guard let provider = providers.first else {
            return
        }

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { item, error in

            guard error == nil else {
                return
            }

            var url: URL?

            if let item = item as? URL {
                url = item

            } else if let item = item as? NSURL {
                url = item as URL

            } else if let data = item as? Data {
                url = URL(
                    dataRepresentation: data,
                    relativeTo: nil
                )
            }

            guard let droppedURL = url else {
                return
            }

            let fileManager = FileManager.default

            var isDirectory: ObjCBool = false

            guard fileManager.fileExists(
                atPath: droppedURL.path,
                isDirectory: &isDirectory
            ) else {
                return
            }

            let supportedExtensions: Set<String> = [
                "mp3",
                "m4a",
                "aac",
                "wav",
                "aiff",
                "aif",
                "flac"
            ]

            var urls: [URL] = []

            if isDirectory.boolValue {

                if let enumerator =
                    fileManager.enumerator(
                        at: droppedURL,
                        includingPropertiesForKeys: [
                            .isRegularFileKey,
                            .isDirectoryKey
                        ],
                        options: [
                            .skipsHiddenFiles,
                            .skipsPackageDescendants
                        ]
                    ) {

                    for case let fileURL as URL in enumerator {

                        let ext =
                            fileURL
                            .pathExtension
                            .lowercased()

                        guard supportedExtensions.contains(ext)
                        else {
                            continue
                        }

                        do {
                            let values =
                                try fileURL.resourceValues(
                                    forKeys: [
                                        .isRegularFileKey
                                    ]
                                )

                            guard values.isRegularFile == true
                            else {
                                continue
                            }

                            urls.append(fileURL)

                        } catch {
                            continue
                        }
                    }
                }

            } else {

                let ext =
                    droppedURL
                    .pathExtension
                    .lowercased()

                guard supportedExtensions.contains(ext)
                else {
                    return
                }

                urls.append(droppedURL)
            }

            guard !urls.isEmpty else {
                return
            }

            urls.sort {
                $0.lastPathComponent.localizedStandardCompare(
                    $1.lastPathComponent
                ) == .orderedAscending
            }

            let tracks = urls.map { fileURL in
                AudioTrack(
                    url: fileURL
                )
            }

            DispatchQueue.main.async {

                audio.setPlaylist(tracks)

                if let firstTrack = tracks.first {
                    audio.play(firstTrack)
                }
            }
        }
    }

    // MARK: - Main layout

    private var deckLayout: some View {

        let availableGapSpace =
            deckWidth
            - (edgeInset * 2)
            - indicatorSize.width
            - albumSize.width
            - cassetteSize.width
            - transportSize.width

        let columnGap =
            availableGapSpace / 3

        let x1 =
            edgeInset

        let x2 =
            x1
            + indicatorSize.width
            + columnGap

        let x3 =
            x2
            + albumSize.width
            + columnGap

        let x4 =
            x3
            + cassetteSize.width
            + columnGap

        let upperY =
            topInset

        let lowerY =
            deckHeight
            - bottomInset
            - lowerButtonsSize.height

        return ZStack(
            alignment: .topLeading
        ) {

            // =====================================================
            // COLUMN 1
            // =====================================================

            IndicatorBlock(
                audio: audio,
                showPlaylist: showPlaylist
            )
                .frame(
                    width: indicatorSize.width,
                    height: indicatorSize.height
                )
                .position(
                    x:
                        x1
                        + indicatorSize.width / 2,
                    y:
                        upperY
                        + indicatorSize.height / 2
                )

            RecessedPanel {

                EQPlaceholder(
                    values: $eqValues,
                    audio: audio
                )
            }
            .frame(
                width: eqSize.width,
                height: eqSize.height
            )
            .position(
                x:
                    x1
                    + eqSize.width / 2,
                y:
                    upperY
                    + indicatorSize.height
                    + eqSize.height / 2
            )

            LowerButtonsPlaceholder(
                audio: audio,
                showPlaylist: $showPlaylist,
                showLibrary: $showLibrary
            )
            .frame(
                width: lowerButtonsSize.width,
                height: lowerButtonsSize.height
            )
            .position(
                x:
                    x1
                    + lowerButtonsSize.width / 2,
                y:
                    lowerY
                    + lowerButtonsSize.height / 2
            )

            // =====================================================
            // COLUMN 2
            // =====================================================

            AlbumPlaceholder(
                audio: audio
            )
            .frame(
                width: albumSize.width,
                height: albumSize.height
            )
            .position(
                x:
                    x2
                    + albumSize.width / 2,
                y:
                    upperY
                    + albumSize.height / 2
            )

            VolumePlaceholder(
                size: volumeSize,
                audio: audio
            )
            .frame(
                width: volumeSize.width,
                height: volumeSize.height
            )
            .position(
                x:
                    x2
                    + volumeSize.width / 2,
                y:
                    lowerY
                    + volumeSize.height / 2
            )

            // =====================================================
            // COLUMN 3
            // =====================================================

            CassetteBayPlaceholder(
                audio: audio
            )
            .frame(
                width: cassetteSize.width,
                height: cassetteSize.height
            )
            .position(
                x:
                    x3
                    + cassetteSize.width / 2,
                y:
                    upperY
                    + cassetteSize.height / 2
            )

            ProgressPlaceholder(
                size: progressSize,
                audio: audio
            )
            .frame(
                width: progressSize.width,
                height: progressSize.height
            )
            .position(
                x:
                    x3
                    + progressSize.width / 2,
                y:
                    lowerY
                    + lowerButtonsSize.height / 2
            )

            // =====================================================
            // COLUMN 4
            // =====================================================

            RightControlColumn(
                cassetteSize: cassetteButtonSize,
                timerSize: timerSize,
                transportSize: transportSize,
                audio: audio
            )
            .position(
                x:
                    x4
                    + transportSize.width / 2,
                y:
                    upperY
                    + (
                        cassetteButtonSize.height
                        + 8
                        + timerSize.height
                        + 8
                        + transportSize.height
                    ) / 2
            )

            // =====================================================
            // PLAYLIST SHUTTER
            // =====================================================

            if showPlaylist {

                PlaylistView(
                    audio: audio,
                    onClose: {
                        withAnimation(
                            .easeInOut(duration: 0.32)
                        ) {
                            showPlaylist = false
                        }
                    }
                )
                .frame(
                    width: transportSize.width,
                    height: deckHeight
                )
                .position(
                    x:
                        x4
                        + transportSize.width / 2,
                    y:
                        deckHeight / 2
                )
                .transition(
                    .move(edge: .trailing)
                )
                .zIndex(100)
            }
        }
        .animation(
            .easeInOut(duration: 0.32),
            value: showPlaylist
        )
    }

    // MARK: - Deck background

    private var deckBackground: some View {

        ZStack {

            PanelMaterials.mainPanel

            LinearGradient(
                stops: [
                    .init(
                        color:
                            Color.white.opacity(0.018),
                        location: 0.00
                    ),
                    .init(
                        color:
                            Color.clear,
                        location: 0.20
                    ),
                    .init(
                        color:
                            Color.black.opacity(0.014),
                        location: 0.50
                    ),
                    .init(
                        color:
                            Color.white.opacity(0.010),
                        location: 0.78
                    ),
                    .init(
                        color:
                            Color.black.opacity(0.025),
                        location: 1.00
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(
                                color: Color.clear,
                                location: 0.55
                            ),
                            .init(
                                color:
                                    Color.black.opacity(0.10),
                                location: 0.82
                            ),
                            .init(
                                color:
                                    Color.black.opacity(0.28),
                                location: 1.00
                            )
                        ],
                        center: .center,
                        startRadius: 100,
                        endRadius: 620
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(
                                color:
                                    Color.white.opacity(0.035),
                                location: 0.00
                            ),
                            .init(
                                color:
                                    Color.white.opacity(0.008),
                                location: 0.18
                            ),
                            .init(
                                color: Color.clear,
                                location: 0.45
                            ),
                            .init(
                                color: Color.clear,
                                location: 1.00
                            )
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .stroke(
                    Color.black.opacity(0.85),
                    lineWidth: 3
                )
                .padding(1)

            Rectangle()
                .stroke(
                    Color.white.opacity(0.065),
                    lineWidth: 1
                )
                .padding(3)

            VStack {

                Spacer()

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.20)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 8)
            }
        }
    }
}

// MARK: - Right control column

private struct RightControlColumn: View {

    let cassetteSize: CGSize
    let timerSize: CGSize
    let transportSize: CGSize

    let audio: AudioPlayer

    var body: some View {

        VStack(spacing: 8) {

            CassetteButtonPlaceholder(
                size: cassetteSize
            )

            TimerPlaceholder(
                size: timerSize,
                audio: audio
            )

            TransportPlaceholder(
                size: transportSize,
                audio: audio
            )
        }
        .frame(
            width: transportSize.width,
            height:
                cassetteSize.height
                + timerSize.height
                + transportSize.height
                + 16
        )
    }
}

// MARK: - Recessed panel

private struct RecessedPanel<Content: View>: View {

    let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {

        ZStack {

            RoundedRectangle(
                cornerRadius: 1
            )
            .fill(
                Color.black.opacity(0.62)
            )

            RoundedRectangle(
                cornerRadius: 1
            )
            .stroke(
                Color.white.opacity(0.11),
                lineWidth: 1
            )
            .padding(1)

            RoundedRectangle(
                cornerRadius: 1
            )
            .stroke(
                Color.black.opacity(0.95),
                lineWidth: 2
            )
            .padding(2)
            .offset(
                x: 0.7,
                y: 0.7
            )

            content
                .padding(4)
        }
    }
}

// MARK: - EQ

private struct EQPlaceholder: View {

    @Binding var values: [Float]

    @ObservedObject var audio: AudioPlayer

    private let frequencies = [
        "31",
        "62",
        "125",
        "250",
        "500",
        "1k",
        "2k",
        "4k",
        "8k",
        "16k"
    ]

    var body: some View {

        ZStack(alignment: .topLeading) {

            HStack(
                alignment: .top,
                spacing: 4
            ) {

                EQScale()

                ForEach(
                    frequencies.indices,
                    id: \.self
                ) { index in

                    VStack(
                        spacing: 2
                    ) {

                        Text(
                            String(
                                format: "%+.0f",
                                values[index]
                            )
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .regular,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(0.72)
                        )
                        .frame(height: 10)

                        EQSlider(
                            value: $values[index],
                            onChange: { newValue in

                                audio.setEQGain(
                                    band: index,
                                    gain: newValue
                                )
                            }
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 48
                        )

                        Text(
                            frequencies[index]
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .regular,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(0.68)
                        )
                        .frame(height: 10)
                    }
                    .frame(
                        maxWidth: .infinity
                    )
                }

                EQScale()
            }
            .padding(
                .horizontal,
                2
            )
            .padding(
                .vertical,
                4
            )

            eqStatusLED
                .padding(
                    .leading,
                    5
                )
                .padding(
                    .top,
                    0
                )
        }
        .contentShape(Rectangle())
        .onAppear {
            let savedValues = audio.savedEQValues

            if values != savedValues {
                withAnimation(
                    .easeOut(duration: 0.7)
                ) {
                    values = savedValues
                }
            }
        }
        .contextMenu {
            Button("Reset EQ") {

                let resetValues =
                    Array(
                        repeating: Float(0),
                        count: 10
                    )

                withAnimation(
                    .easeOut(duration: 0.25)
                ) {
                    values = resetValues
                }

                for index in 0..<10 {
                    audio.setEQGain(
                        band: index,
                        gain: 0
                    )
                }
            }
        }
    }

    private var eqStatusLED: some View {
        RoundedRectangle(
            cornerRadius: 0.8
        )
        .fill(
            audio.isEQEnabled
                ? Color.red
                : Color.black.opacity(0.72)
        )
        .frame(
            width: 8,
            height: 4
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 0.8
            )
            .stroke(
                audio.isEQEnabled
                    ? Color.red.opacity(0.75)
                    : Color.white.opacity(0.10),
                lineWidth: 0.5
            )
        }
        .shadow(
            color: audio.isEQEnabled
                ? Color.red.opacity(0.65)
                : Color.clear,
            radius: 3
        )
        .animation(
            .easeOut(duration: 0.18),
            value: audio.isEQEnabled
        )
    }
}

// MARK: - EQ scale

private struct EQScale: View {

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                eqScaleMark(
                    value: "+15",
                    strong: false
                )
                .position(
                    x: geometry.size.width / 2,
                    y: 5
                )

                eqScaleMark(
                    value: "0",
                    strong: true
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                eqScaleMark(
                    value: "-15",
                    strong: false
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height - 5
                )
            }
        }
        .frame(
            width: 22
        )
    }

    private func eqScaleMark(
        value: String,
        strong: Bool
    ) -> some View {

        HStack(
            spacing: 2
        ) {

            Rectangle()
                .fill(
                    Color.white.opacity(
                        strong ? 0.42 : 0.18
                    )
                )
                .frame(
                    width: 7,
                    height: 1
                )

            Text(value)
                .font(
                    .system(
                        size: 7,
                        weight: .regular,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(
                        strong ? 0.72 : 0.55
                    )
                )
        }
        .frame(
            height: 10
        )
    }
}

// MARK: - EQ slider

private struct EQSlider: View {

    @Binding var value: Float

    let minimum: Float = -15
    let maximum: Float = 15

    let onChange: (Float) -> Void

    var body: some View {

        GeometryReader { geometry in

            let trackHeight =
                geometry.size.height

            let normalized =
                CGFloat(
                    (value - minimum)
                    / (maximum - minimum)
                )

            ZStack {

                RoundedRectangle(
                    cornerRadius: 1
                )
                .fill(
                    Color.black.opacity(0.85)
                )
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 1
                    )
                    .stroke(
                        Color.black.opacity(0.95),
                        lineWidth: 1
                    )
                }

                VStack(
                    spacing: 0
                ) {

                    ForEach(
                        0..<7,
                        id: \.self
                    ) { index in

                        Rectangle()
                            .fill(
                                index == 3
                                    ? Color.white.opacity(0.42)
                                    : Color.white.opacity(0.13)
                            )
                            .frame(height: 1)

                        if index < 6 {
                            Spacer()
                        }
                    }
                }
                .padding(
                    .horizontal,
                    3
                )
                .allowsHitTesting(false)

                RoundedRectangle(
                    cornerRadius: 1
                )
                .fill(
                    PanelMaterials.aluminum
                )
                .frame(
                    width: 14,
                    height: 9
                )
                .overlay {

                    RoundedRectangle(
                        cornerRadius: 1
                    )
                    .stroke(
                        Color.black.opacity(0.7),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: .black.opacity(0.55),
                    radius: 1,
                    y: 1
                )
                .position(
                    x:
                        geometry.size.width / 2,
                    y:
                        trackHeight
                        * (1 - normalized)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(
                    minimumDistance: 0
                )
                .onChanged { gesture in

                    let y =
                        min(
                            max(
                                0,
                                gesture.location.y
                            ),
                            trackHeight
                        )

                    let normalized =
                        1 - y / trackHeight

                    let newValue =
                        minimum
                        + Float(normalized)
                        * (maximum - minimum)

                    let clamped =
                        min(
                            maximum,
                            max(
                                minimum,
                                newValue
                            )
                        )

                    value = clamped

                    onChange(clamped)
                }
            )
        }
        .frame(height: 48)
    }
}

// MARK: - Album

private struct AlbumPlaceholder: View {

    @ObservedObject var audio: AudioPlayer

    var body: some View {

        ZStack {

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.13),
                            Color(white: 0.08),
                            Color(white: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Rectangle()
                .fill(
                    Color.black.opacity(0.35)
                )
                .padding(1)

            Rectangle()
                .stroke(
                    Color.black.opacity(0.95),
                    lineWidth: 2
                )
                .padding(1)

            Rectangle()
                .stroke(
                    Color.white.opacity(0.11),
                    lineWidth: 1
                )
                .padding(3)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                ZStack {

                    Rectangle()
                        .fill(Color.black.opacity(0.65))

                    if let artworkData = audio.currentTrack?.artwork,
                       let nsImage = NSImage(data: artworkData) {

                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(
                                contentMode: .fill
                            )
                            .frame(
                                width: 127,
                                height: 127
                            )
                            .clipped()

                    } else {

                        Text(
                            audio.currentTrack?.title
                            ?? "ART"
                        )
                        .font(
                            .system(
                                size: 8,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(0.15)
                        )
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        .padding(5)
                    }
                }
                .frame(
                    width: 127,
                    height: 127
                )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {

                    Text(
                        audio.currentTrack?.artist
                        ?? "Artist"
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                    Text(
                        audio.currentTrack?.album
                        ?? "Album"
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                    Text(
                        audio.currentTrack?.title
                        ?? "Track"
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .font(
                    .system(
                        size: 7,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    PanelMaterials.marking.opacity(0.65)
                )
            }
            .frame(
                width: 127,
                alignment: .leading
            )
            .padding(5)
        }
    }
}

// MARK: - Cassette bay

private struct CassetteBayPlaceholder: View {

    @ObservedObject var audio: AudioPlayer

    var body: some View {

        ZStack {

            if let bayURL =
                Bundle.module.url(
                    forResource: "cassette_bay",
                    withExtension: "png"
                ),
                let bayImage =
                    NSImage(contentsOf: bayURL) {

                Image(nsImage: bayImage)
                    .resizable()
                    .frame(
                        width: 302,
                        height: 174
                    )
            }

            if audio.currentTrack != nil {

                if let cassetteURL =
                    Bundle.module.url(
                        forResource: "cassette",
                        withExtension: "png"
                    ),
                    let cassetteImage =
                        NSImage(contentsOf: cassetteURL) {

                    Image(nsImage: cassetteImage)
                        .resizable()
                        .frame(
                            width: 212,
                            height: 121
                        )
                        .offset(
                            x: -6,
                            y: -3
                        )
                }

                let reelAngle =
                    audio.currentTime * 180.0

                if let reelURL =
                    Bundle.module.url(
                        forResource: "katushka",
                        withExtension: "png"
                    ),
                    let reelImage =
                        NSImage(contentsOf: reelURL) {

                    Image(nsImage: reelImage)
                        .resizable()
                        .frame(
                            width: 25,
                            height: 25
                        )
                        .rotationEffect(
                            .degrees(-reelAngle)
                        )
                        .offset(
                            x: -50,
                            y: -8
                        )

                    Image(nsImage: reelImage)
                        .resizable()
                        .frame(
                            width: 25,
                            height: 25
                        )
                        .rotationEffect(
                            .degrees(-reelAngle)
                        )
                        .offset(
                            x: 38,
                            y: -8
                        )
                }
            }
        }
        .frame(
            width: 307,
            height: 176
        )
        .overlay {

            Rectangle()
                .stroke(
                    Color.black.opacity(0.9),
                    lineWidth: 2
                )
        }
    }
}

// MARK: - Cassette button

private struct CassetteButtonPlaceholder: View {

    let size: CGSize

    var body: some View {

        RoundedRectangle(
            cornerRadius: 1.5
        )
        .fill(
            PanelMaterials.aluminum
        )
        .overlay {

            RoundedRectangle(
                cornerRadius: 1.5
            )
            .stroke(
                Color.black.opacity(0.7),
                lineWidth: 1
            )
        }
        .overlay {

            Text("CASSETTE")
                .font(
                    .system(
                        size: 7,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.black.opacity(0.75)
                )
        }
        .shadow(
            color: .black.opacity(0.45),
            radius: 2,
            y: 2
        )
        .frame(
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Timer

private struct TimerPlaceholder: View {

    let size: CGSize
    @ObservedObject var audio: AudioPlayer

    private let glassGreen = Color(
        red: 0.015,
        green: 0.075,
        blue: 0.045
    )

    private let glowGreen = Color(
        red: 0.03,
        green: 0.92,
        blue: 0.48
    )

    private var remainingTime: Int {
        max(
            0,
            Int(
                ceil(
                    audio.duration
                    - audio.currentTime
                )
            )
        )
    }

    private var timerCharacters: [String] {

        let minutes =
            remainingTime / 60

        let seconds =
            remainingTime % 60

        return [
            "-",
            String(minutes / 10),
            String(minutes % 10),
            ":",
            String(seconds / 10),
            String(seconds % 10)
        ]
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
                    glassGreen.opacity(0.72)
                )

            LinearGradient(
                stops: [
                    .init(
                        color:
                            Color.white.opacity(0.025),
                        location: 0.00
                    ),
                    .init(
                        color: Color.clear,
                        location: 0.28
                    ),
                    .init(
                        color:
                            Color.black.opacity(0.12),
                        location: 1.00
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 7) {

                ForEach(
                    timerCharacters.indices,
                    id: \.self
                ) { index in

                    if timerCharacters[index] == ":" {

                        SevenSegmentColon(
                            size: 20
                        )

                    } else {

                        SevenSegmentDigit(
                            value:
                                timerCharacters[index],
                            size: 20
                        )
                    }
                }
            }
            .foregroundStyle(glowGreen)
            .blur(radius: 2.2)
            .opacity(0.32)

            HStack(spacing: 7) {

                ForEach(
                    timerCharacters.indices,
                    id: \.self
                ) { index in

                    if timerCharacters[index] == ":" {

                        SevenSegmentColon(
                            size: 20
                        )

                    } else {

                        SevenSegmentDigit(
                            value:
                                timerCharacters[index],
                            size: 20
                        )
                    }
                }
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
                    lineWidth: 2
                )
                .padding(1)

            Rectangle()
                .stroke(
                    Color.white.opacity(0.07),
                    lineWidth: 1
                )
                .padding(3)
        }
        .frame(
            width: size.width,
            height: size.height
        )
    }
}

private struct LCDSegmentShape: Shape {

    func path(in rect: CGRect) -> Path {

        let cut =
            min(
                rect.width,
                rect.height
            ) * 0.28

        var path = Path()

        path.move(
            to:
                CGPoint(
                    x: rect.minX + cut,
                    y: rect.minY
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: rect.maxX - cut,
                    y: rect.minY
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: rect.maxX,
                    y: rect.midY
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: rect.maxX - cut,
                    y: rect.maxY
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: rect.minX + cut,
                    y: rect.maxY
                )
        )

        path.addLine(
            to:
                CGPoint(
                    x: rect.minX,
                    y: rect.midY
                )
        )

        path.closeSubpath()

        return path
    }
}

// MARK: - Seven segment digit

private struct SevenSegmentDigit: View {

    let value: String
    let size: CGFloat

    private let thickness: CGFloat = 3

    var body: some View {

        ZStack {

            segment("a")
                .frame(
                    width: size * 0.55,
                    height: thickness
                )
                .position(
                    x: size * 0.5,
                    y: thickness / 2 + 1
                )

            segment("g")
                .frame(
                    width: size * 0.55,
                    height: thickness
                )
                .position(
                    x: size * 0.5,
                    y: size * 0.5
                )

            segment("d")
                .frame(
                    width: size * 0.55,
                    height: thickness
                )
                .position(
                    x: size * 0.5,
                    y: size - thickness / 2 - 1
                )

            segment("f")
                .frame(
                    width: thickness,
                    height: size * 0.32
                )
                .position(
                    x: thickness / 2 + 1,
                    y: size * 0.27
                )

            segment("b")
                .frame(
                    width: thickness,
                    height: size * 0.32
                )
                .position(
                    x: size - thickness / 2 - 1,
                    y: size * 0.27
                )

            segment("e")
                .frame(
                    width: thickness,
                    height: size * 0.32
                )
                .position(
                    x: thickness / 2 + 1,
                    y: size * 0.73
                )

            segment("c")
                .frame(
                    width: thickness,
                    height: size * 0.32
                )
                .position(
                    x: size - thickness / 2 - 1,
                    y: size * 0.73
                )
        }
        .frame(
            width: size * 0.65,
            height: size
        )
    }

    @ViewBuilder
    private func segment(
        _ name: String
    ) -> some View {

        let active =
            activeSegments.contains(name)

        let green = Color(
            red: 0.035,
            green: 0.86,
            blue: 0.42
        )

        ZStack {

            if active {

                LCDSegmentShape()
                    .fill(green)
                    .blur(radius: 4.5)
                    .opacity(0.25)

                LCDSegmentShape()
                    .fill(green)
                    .blur(radius: 1.8)
                    .opacity(0.27)
            }

            if active {

                LCDSegmentShape()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(
                                    color:
                                        green.opacity(0.78),
                                    location: 0.00
                                ),
                                .init(
                                    color: green,
                                    location: 0.45
                                ),
                                .init(
                                    color:
                                        green.opacity(0.68),
                                    location: 1.00
                                )
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {

                        LCDSegmentShape()
                            .stroke(
                                green.opacity(0.22),
                                lineWidth: 0.7
                            )
                    }

            } else {

                LCDSegmentShape()
                    .fill(
                        Color(
                            red: 0.025,
                            green: 0.075,
                            blue: 0.045
                        )
                    )
                    .opacity(0.32)
            }
        }
    }

    private var activeSegments: Set<String> {

        switch value {

        case "-":
            return ["g"]

        case "0":
            return [
                "a", "b", "c",
                "d", "e", "f"
            ]

        case "1":
            return ["b", "c"]

        case "2":
            return ["a", "b", "g", "e", "d"]

        case "3":
            return ["a", "b", "g", "c", "d"]

        case "4":
            return ["f", "g", "b", "c"]

        case "5":
            return ["a", "f", "g", "c", "d"]

        case "6":
            return ["a", "f", "g", "e", "c", "d"]

        case "7":
            return ["a", "b", "c"]

        case "8":
            return [
                "a", "b", "c",
                "d", "e", "f", "g"
            ]

        case "9":
            return [
                "a", "b", "c",
                "d", "f", "g"
            ]

        default:
            return []
        }
    }
}

// MARK: - Seven segment colon

private struct SevenSegmentColon: View {

    let size: CGFloat

    private let green = Color(
        red: 0.04,
        green: 0.92,
        blue: 0.48
    )

    var body: some View {

        VStack(spacing: 1) {

            colonDot
            colonDot
        }
        .frame(
            width: 5,
            height: size
        )
        .offset(x: 3)
    }

    private var colonDot: some View {

        ZStack {

            RoundedRectangle(
                cornerRadius: 1.5
            )
            .fill(green)
            .blur(radius: 2)
            .opacity(0.42)

            RoundedRectangle(
                cornerRadius: 1.5
            )
            .fill(green)
            .frame(
                width: 3,
                height: 3
            )
            .opacity(0.78)
        }
    }
}

// MARK: - Transport

private struct TransportPlaceholder: View {

    let size: CGSize

    @ObservedObject var audio: AudioPlayer

    private let buttonWidth: CGFloat = 65
    private let buttonHeight: CGFloat = 39

    var body: some View {

        VStack(spacing: 0) {

            Rectangle()
                .fill(
                    Color.white.opacity(0.08)
                )
                .frame(height: 1)

            VStack(spacing: 0) {

                HStack(spacing: 4) {

                    transportButton(
                        "▶",
                        isActive: audio.isPlaying
                    ) {
                        audio.togglePlayPause()
                    }

                    transportButton(
                        "Ⅱ",
                        isActive:
                            !audio.isPlaying
                            && audio.currentTrack != nil
                            && audio.currentTime > 0
                    ) {
                        audio.togglePlayPause()
                    }
                }

                Spacer()

                HStack(spacing: 4) {

                    transportButton(
                        "◀◀",
                        isActive: false,
                        momentary: true
                    ) {
                        audio.previous()
                    }

                    transportButton(
                        "▶▶",
                        isActive: false,
                        momentary: true
                    ) {
                        audio.next()
                    }
                }

                Spacer()

                HStack(spacing: 4) {

                    transportButton(
                        "M",
                        isActive: audio.isMuted
                    ) {
                        audio.toggleMute()
                    }

                    transportButton(
                        "■",
                        isActive:
                            !audio.isPlaying
                            && (
                                audio.currentTrack == nil
                                || audio.currentTime == 0
                            )
                    ) {
                        audio.stop()
                    }
                }
            }
            .padding(5)
        }
        .frame(
            width: size.width,
            height: size.height
        )
        .background(
            Color(
                red: 0.045,
                green: 0.047,
                blue: 0.050
            )
        )
        .overlay {

            Rectangle()
                .stroke(
                    Color.black.opacity(0.95),
                    lineWidth: 2
                )
                .padding(1)
        }
        .overlay {

            Rectangle()
                .stroke(
                    Color.white.opacity(0.07),
                    lineWidth: 1
                )
                .padding(3)
        }
    }

    private func transportButton(
        _ title: String,
        isActive: Bool,
        momentary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {

        Button(
            action: action
        ) {
            Color.clear
        }
        .buttonStyle(
            TransportButtonStyle(
                title: title,
                isActive: isActive,
                momentary: momentary,
                buttonWidth: buttonWidth,
                buttonHeight: buttonHeight
            )
        )
    }
}

private struct TransportButtonStyle: ButtonStyle {

    let title: String
    let isActive: Bool
    let momentary: Bool
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat

    func makeBody(
        configuration: Configuration
    ) -> some View {

        let active =
            momentary
                ? configuration.isPressed
                : isActive

        ZStack {

            Rectangle()
                .fill(
                    Color.black.opacity(
                        active ? 0.92 : 0.82
                    )
                )
                .offset(y: 2)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors:
                            active
                            ? [
                                Color(white: 0.13),
                                Color(white: 0.095),
                                Color(white: 0.075)
                            ]
                            : [
                                Color(white: 0.22),
                                Color(white: 0.16),
                                Color(white: 0.12)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .stroke(
                    Color.white.opacity(
                        active ? 0.06 : 0.15
                    ),
                    lineWidth: 1
                )
                .padding(1)

            Rectangle()
                .stroke(
                    Color.black.opacity(0.88),
                    lineWidth: 1
                )
                .padding(3)

            Text(title)
                .font(
                    .system(
                        size: title == "M" ? 9 : 11,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    active
                        ? Color.green.opacity(0.95)
                        : PanelMaterials.marking.opacity(0.82)
                )
                .offset(
                    y: active ? 1 : -1
                )
        }
        .frame(
            width: buttonWidth,
            height: buttonHeight
        )
        .scaleEffect(
            configuration.isPressed
                ? 0.97
                : 1.0
        )
        .offset(
            y:
                configuration.isPressed
                ? 2
                : 0
        )
        .brightness(
            configuration.isPressed
                ? -0.025
                : 0
        )
        .animation(
            .easeOut(duration: 0.06),
            value: configuration.isPressed
        )
    }
}

// MARK: - Lower five buttons

private struct LowerButtonsPlaceholder: View {

    @ObservedObject var audio: AudioPlayer

    @Binding var showPlaylist: Bool
    @Binding var showLibrary: Bool

    var body: some View {

        HStack(
            spacing: 4
        ) {

            // EQ

            lowerButton(
                active: audio.isEQEnabled
            ) {
                audio.setEQEnabled(
                    !audio.isEQEnabled
                )
            } content: {

                Text("EQ")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
            }

            // SH — Shuffle

            lowerButton(
                active: audio.shuffle
            ) {
                audio.shuffle.toggle()
            } content: {

                Text("SH")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
            }

            // RP — Repeat

            lowerButton(
                active: audio.repeatMode != 0
            ) {

                audio.repeatMode += 1

                if audio.repeatMode > 2 {
                    audio.repeatMode = 0
                }

            } content: {

                Text(
                    audio.repeatMode == 0
                        ? "RP"
                        : audio.repeatMode == 1
                            ? "RP1"
                            : "RPA"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .medium,
                        design: .monospaced
                    )
                )
            }

            // LB — Library

            lowerButton(
                active: showLibrary
            ) {

                withAnimation(
                    .easeInOut(
                        duration: 0.32
                    )
                ) {

                    showPlaylist = false
                    showLibrary.toggle()
                }

            } content: {

                Text("LB")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
            }

            // PL — Playlist

            lowerButton(
                active: showPlaylist
            ) {

                withAnimation(
                    .easeInOut(duration: 0.32)
                ) {
                    showPlaylist.toggle()
                }

            } content: {

                Text("PL")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
            }
        }
        .padding(3)
        .background(
            PanelMaterials.texturedPlastic
        )
        .overlay {

            Rectangle()
                .stroke(
                    Color.black.opacity(0.8),
                    lineWidth: 1
                )
        }
    }

    private func lowerButton<Content: View>(
        active: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {

        Button(
            action: action
        ) {

            ZStack {

                Rectangle()
                    .fill(
                        Color.black.opacity(
                            active ? 0.92 : 0.82
                        )
                    )
                    .offset(y: 2)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors:
                                active
                                ? [
                                    Color(white: 0.13),
                                    Color(white: 0.095),
                                    Color(white: 0.075)
                                ]
                                : [
                                    Color(white: 0.22),
                                    Color(white: 0.16),
                                    Color(white: 0.12)
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Rectangle()
                    .stroke(
                        Color.white.opacity(
                            active ? 0.06 : 0.15
                        ),
                        lineWidth: 1
                    )
                    .padding(1)

                Rectangle()
                    .stroke(
                        Color.black.opacity(0.88),
                        lineWidth: 1
                    )
                    .padding(3)

                content()
                    .foregroundStyle(
                        active
                            ? Color.green.opacity(0.95)
                            : PanelMaterials.marking.opacity(0.82)
                    )
                    .offset(
                        y: active ? 1 : -1
                    )
            }
            .frame(
                width: 58,
                height: 35
            )
        }
        .buttonStyle(
            LowerButtonStyle()
        )
    }
}

private struct LowerButtonStyle: ButtonStyle {

    func makeBody(
        configuration: Configuration
    ) -> some View {

        configuration.label
            .scaleEffect(
                configuration.isPressed
                    ? 0.97
                    : 1.0
            )
            .offset(
                y:
                    configuration.isPressed
                    ? 2
                    : 0
            )
            .brightness(
                configuration.isPressed
                    ? -0.025
                    : 0
            )
            .animation(
                .easeOut(duration: 0.06),
                value: configuration.isPressed
            )
    }
}


// MARK: - Volume

private struct VolumePlaceholder: View {

    let size: CGSize

    @ObservedObject var audio: AudioPlayer

    var body: some View {

        VStack(
            spacing: 3
        ) {

            HStack {

                Text("VOLUME")

                Spacer()

                Text(
                    String(
                        format: "%d",
                        Int(audio.volume * 100)
                    )
                )
            }
            .font(
                .system(
                    size: 6,
                    weight: .regular,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                PanelMaterials.marking.opacity(0.55)
            )

            GeometryReader { geometry in

                let width =
                    geometry.size.width

                let progress =
                    CGFloat(audio.volume)

                ZStack(
                    alignment: .leading
                ) {

                    RoundedRectangle(
                        cornerRadius: 1
                    )
                    .fill(
                        Color.black.opacity(0.82)
                    )

                    RoundedRectangle(
                        cornerRadius: 1
                    )
                    .fill(
                        Color.white.opacity(0.25)
                    )
                    .frame(
                        width:
                            width * progress
                    )

                    RoundedRectangle(
                        cornerRadius: 1
                    )
                    .fill(
                        PanelMaterials.aluminum
                    )
                    .frame(
                        width: 12,
                        height: 7
                    )
                    .overlay {

                        RoundedRectangle(
                            cornerRadius: 1
                        )
                        .stroke(
                            Color.black.opacity(0.7),
                            lineWidth: 1
                        )
                    }
                    .position(
                        x:
                            min(
                                width - 6,
                                max(
                                    6,
                                    width * progress
                                )
                            ),
                        y:
                            geometry.size.height / 2
                    )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(
                        minimumDistance: 0
                    )
                    .onChanged { gesture in

                        let x =
                            min(
                                max(
                                    0,
                                    gesture.location.x
                                ),
                                width
                            )

                        let value =
                            Float(x / width)

                        audio.setVolume(value)
                    }
                )
            }
            .frame(height: 9)
        }
        .padding(5)
        .frame(
            width: size.width,
            height: 43
        )
        .background(
            PanelMaterials.texturedPlastic
        )
        .overlay {

            Rectangle()
                .stroke(
                    Color.black.opacity(0.8),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Progress

private struct ProgressPlaceholder: View {

    let size: CGSize

    @ObservedObject var audio: AudioPlayer

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0

    var body: some View {

        GeometryReader { geometry in

            let duration =
                audio.duration

            let displayedTime =
                isDragging
                    ? dragTime
                    : audio.currentTime

            let progress: CGFloat =
                duration > 0
                    ? CGFloat(
                        min(
                            1,
                            max(
                                0,
                                displayedTime
                                / duration
                            )
                        )
                    )
                    : 0

            ZStack {

                Rectangle()
                    .fill(
                        PanelMaterials.texturedPlastic
                    )

                VStack(
                    spacing: 4
                ) {

                    HStack {

                        Text(
                            formatTime(displayedTime)
                        )

                        Spacer()

                        Text(
                            formatTime(audio.duration)
                        )
                    }
                    .font(
                        .system(
                            size: 7,
                            weight: .regular,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        PanelMaterials.marking.opacity(0.55)
                    )

                    GeometryReader { trackGeometry in

                        let trackWidth =
                            trackGeometry.size.width

                        ZStack(
                            alignment: .leading
                        ) {

                            RoundedRectangle(
                                cornerRadius: 1
                            )
                            .fill(
                                Color.black.opacity(0.82)
                            )
                            .overlay {

                                RoundedRectangle(
                                    cornerRadius: 1
                                )
                                .stroke(
                                    Color.black.opacity(0.95),
                                    lineWidth: 1
                                )
                            }

                            RoundedRectangle(
                                cornerRadius: 1
                            )
                            .fill(
                                Color.white.opacity(0.28)
                            )
                            .frame(
                                width:
                                    trackWidth * progress
                            )

                            RoundedRectangle(
                                cornerRadius: 1
                            )
                            .fill(
                                PanelMaterials.aluminum
                            )
                            .frame(
                                width: 12,
                                height: 7
                            )
                            .overlay {

                                RoundedRectangle(
                                    cornerRadius: 1
                                )
                                .stroke(
                                    Color.black.opacity(0.7),
                                    lineWidth: 1
                                )
                            }
                            .shadow(
                                color: .black.opacity(0.5),
                                radius: 1,
                                y: 1
                            )
                            .position(
                                x:
                                    max(
                                        6,
                                        min(
                                            trackWidth - 6,
                                            trackWidth
                                            * progress
                                        )
                                    ),
                                y:
                                    trackGeometry
                                    .size
                                    .height
                                    / 2
                            )
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(
                                minimumDistance: 0
                            )
                            .onChanged { gesture in

                                guard duration > 0
                                else {
                                    return
                                }

                                if !isDragging {

                                    isDragging = true
                                    dragTime =
                                        audio.currentTime
                                }

                                let x =
                                    min(
                                        max(
                                            0,
                                            gesture.location.x
                                        ),
                                        trackWidth
                                    )

                                let normalized =
                                    Double(
                                        x / trackWidth
                                    )

                                dragTime =
                                    duration
                                    * normalized
                            }
                            .onEnded { _ in

                                guard duration > 0
                                else {
                                    isDragging = false
                                    return
                                }

                                let finalTime =
                                    max(
                                        0,
                                        min(
                                            duration,
                                            dragTime
                                        )
                                    )

                                isDragging = false

                                audio.seek(
                                    to: finalTime
                                )
                            }
                        )
                    }
                    .frame(height: 9)
                }
                .padding(
                    .horizontal,
                    6
                )
                .padding(
                    .vertical,
                    5
                )
            }
            .overlay {

                Rectangle()
                    .stroke(
                        Color.black.opacity(0.8),
                        lineWidth: 1
                    )
            }
        }
        .frame(
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Time formatting

private func formatTime(
    _ time: TimeInterval
) -> String {

    guard time.isFinite,
          time >= 0
    else {
        return "00:00"
    }

    let totalSeconds =
        Int(time)

    let minutes =
        totalSeconds / 60

    let seconds =
        totalSeconds % 60

    return String(
        format: "%02d:%02d",
        minutes,
        seconds
    )
}