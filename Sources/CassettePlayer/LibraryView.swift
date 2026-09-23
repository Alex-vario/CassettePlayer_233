import SwiftUI
import AppKit
import AVFoundation

struct LibraryView: View {

    @ObservedObject var audio: AudioPlayer

    let onClose: () -> Void

    @State private var currentFolder: URL?
    @State private var folders: [URL] = []
    @State private var rootFiles: [URL] = []
    @State private var selectedRoot: URL?
    @State private var isLoading = false

    private let rootDefaultsKey =
        "CassettePlayer.Library.Root"

    var body: some View {

        ZStack {

            PanelMaterials.mainPanel

            VStack(spacing: 0) {

                header

                Divider()
                    .background(
                        Color.black.opacity(0.7)
                    )

                content
            }
        }
        .task {
            loadSavedRoot()
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 8) {

            modeButton(
                title: "ПАПКИ",
                active: true
            ) {
            }

            modeButton(
                title: "ИСПОЛНИТЕЛИ",
                active: false
            ) {
            }

            Rectangle()
                .fill(
                    Color.white.opacity(0.18)
                )
                .frame(
                    width: 1,
                    height: 18
                )
                .padding(
                    .horizontal,
                    2
                )

            breadcrumbInline

            Spacer(minLength: 4)

            Button {
                chooseLibraryFolder()
            } label: {

                Text("ПАПКА")
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.9)
                    )
            }
            .buttonStyle(.plain)

            Button {
                onClose()
            } label: {

                Text("▲")
                    .font(
                        .system(
                            size: 15,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.9)
                    )
                    .offset(y: -2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            Color.black.opacity(0.30)
        )
    }

    // MARK: - Header Buttons

    private func modeButton(
        title: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {

        Button(
            action: action
        ) {

            Text(title)
                .font(
                    .system(
                        size: 11,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    active
                        ? Color.white.opacity(0.95)
                        : Color.white.opacity(0.48)
                )
        }
        .buttonStyle(.plain)
    }

    private var breadcrumbInline: some View {

        HStack(spacing: 5) {

            if let root = selectedRoot {

                Button {
                    currentFolder = root

                    reloadFolder(
                        root
                    )
                } label: {

                    Text(
                        root.lastPathComponent
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            currentFolder == root
                                ? 0.92
                                : 0.60
                        )
                    )
                    .lineLimit(1)
                }
                .buttonStyle(.plain)

                if let current = currentFolder {

                    let components =
                        breadcrumbComponents(
                            root: root,
                            current: current
                        )

                    ForEach(
                        components,
                        id: \.url
                    ) { component in

                        Text("›")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color.white.opacity(0.32)
                            )

                        Button {

                            currentFolder =
                                component.url

                            reloadFolder(
                                component.url
                            )

                        } label: {

                            Text(
                                component.name
                            )
                            .font(
                                .system(
                                    size: 10,
                                    weight: .medium,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color.white.opacity(
                                    0.78
                                )
                            )
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .lineLimit(1)
        .clipped()
    }

    // MARK: - Content

    private var content: some View {

        Group {

            if isLoading {

                ProgressView()
                    .controlSize(.small)

            } else {

                ScrollView {

                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {

                        folderGrid

                        if !rootFiles.isEmpty {

                            tracksSection
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var folderGrid: some View {

        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: 118,
                        maximum: 165
                    ),
                    spacing: 10
                )
            ],
            spacing: 10
        ) {

            ForEach(
                folders,
                id: \.self
            ) { folder in

                FolderTile(
                    folderURL: folder,
                    onOpen: {
                        openFolder(folder)
                    },
                    onPlay: {
                        playFolder(folder)
                    }
                )
            }
        }
    }

    // MARK: - Root files

    private var tracksSection: some View {

        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            HStack {

                Text("ФАЙЛЫ")
                    .font(
                        .system(
                            size: 10,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.82)
                    )

                Spacer()

                Text(
                    "\(rootFiles.count)"
                )
                .font(
                    .system(
                        size: 10,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.55)
                )
            }

            ForEach(
                rootFiles,
                id: \.self
            ) { url in

                TrackRow(
                    url: url,
                    isCurrent:
                        audio.currentTrack?.url == url,
                    onPlay: {
                        playFile(url)
                    }
                )
            }
        }
    }

    // MARK: - Folder navigation

    private func openFolder(
        _ folder: URL
    ) {

        currentFolder = folder

        reloadFolder(
            folder
        )
    }

    private func reloadFolder(
        _ folder: URL
    ) {

        isLoading = true

        Task {

            let result =
                await Task.detached(
                    priority: .userInitiated
                ) {
                    Self.scanFolder(
                        folder
                    )
                }
                .value

            folders =
                result.folders

            rootFiles =
                result.files

            isLoading = false
        }
    }

    // MARK: - Folder playback

    private func playFolder(
        _ folder: URL
    ) {

        let tracks =
            collectAudioTracks(
                in: folder
            )

        guard !tracks.isEmpty else {
            return
        }

        audio.setPlaylist(
            tracks
        )

        audio.play(
            tracks[0]
        )

        onClose()
    }

    private func playFile(
        _ url: URL
    ) {

        let track =
            AudioTrack(
                url: url
            )

        audio.setPlaylist(
            rootFiles.map {
                AudioTrack(
                    url: $0
                )
            }
        )

        audio.play(
            track
        )

        onClose()
    }

    // MARK: - Recursive audio collection

    private func collectAudioTracks(
        in folder: URL
    ) -> [AudioTrack] {

        let fm =
            FileManager.default

        var result: [AudioTrack] = []

        let audioExtensions: Set<String> = [
            "mp3",
            "m4a",
            "aac",
            "wav",
            "aiff",
            "aif",
            "flac",
            "ogg",
            "opus"
        ]

        func walk(
            _ url: URL
        ) {

            guard
                let items =
                    try? fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [
                            .isDirectoryKey,
                            .isRegularFileKey
                        ],
                        options: [
                            .skipsHiddenFiles
                        ]
                    )
            else {
                return
            }

            let sorted =
                items.sorted {

                    $0.lastPathComponent.localizedStandardCompare(
                        $1.lastPathComponent
                    ) == .orderedAscending
                }

            for item in sorted {

                let values =
                    try? item.resourceValues(
                        forKeys: [
                            .isDirectoryKey,
                            .isRegularFileKey
                        ]
                    )

                if values?.isDirectory == true {

                    walk(
                        item
                    )

                } else if
                    values?.isRegularFile == true,
                    audioExtensions.contains(
                        item.pathExtension.lowercased()
                    )
                {

                    result.append(
                        AudioTrack(
                            url: item
                        )
                    )
                }
            }
        }

        walk(
            folder
        )

        return result
    }

    // MARK: - Root chooser

    private func chooseLibraryFolder() {

        let panel =
            NSOpenPanel()

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }

        selectedRoot = url

        UserDefaults.standard.set(
            url.path,
            forKey: rootDefaultsKey
        )

        openFolder(
            url
        )
    }

    private func loadSavedRoot() {

        guard
            let path =
                UserDefaults.standard.string(
                    forKey: rootDefaultsKey
                )
        else {
            return
        }

        let url =
            URL(
                fileURLWithPath: path
            )

        guard
            FileManager.default.fileExists(
                atPath: url.path
            )
        else {
            return
        }

        selectedRoot = url

        openFolder(
            url
        )
    }

    // MARK: - Breadcrumbs

    private struct BreadcrumbComponent {

        let name: String
        let url: URL
    }

    private func breadcrumbComponents(
        root: URL,
        current: URL
    ) -> [BreadcrumbComponent] {

        let rootPath =
            root.standardizedFileURL.path

        let currentPath =
            current.standardizedFileURL.path

        guard
            currentPath.hasPrefix(rootPath)
        else {
            return []
        }

        let relative =
            String(
                currentPath.dropFirst(
                    rootPath.count
                )
            )
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "/"
                )
            )

        guard !relative.isEmpty else {
            return []
        }

        var result:
            [BreadcrumbComponent] = []

        var url = root

        for component in
            relative.split(
                separator: "/"
            ) {

            url =
                url.appendingPathComponent(
                    String(component)
                )

            result.append(
                BreadcrumbComponent(
                    name: String(component),
                    url: url
                )
            )
        }

        return result
    }

    // MARK: - Scanner

    private struct FolderScanResult {

        let folders: [URL]
        let files: [URL]
    }

    private nonisolated static func scanFolder(
        _ folder: URL
    ) -> FolderScanResult {

        let fm =
            FileManager.default

        guard
            let items =
                try? fm.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey
                    ],
                    options: [
                        .skipsHiddenFiles
                    ]
                )
        else {

            return FolderScanResult(
                folders: [],
                files: []
            )
        }

        let audioExtensions: Set<String> = [
            "mp3",
            "m4a",
            "aac",
            "wav",
            "aiff",
            "aif",
            "flac",
            "ogg",
            "opus"
        ]

        var foundFolders: [URL] = []
        var foundFiles: [URL] = []

        for item in items {

            let values =
                try? item.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey
                    ]
                )

            if values?.isDirectory == true {

                foundFolders.append(
                    item
                )

            } else if values?.isRegularFile == true {

                if audioExtensions.contains(
                    item.pathExtension.lowercased()
                ) {

                    foundFiles.append(
                        item
                    )
                }
            }
        }

        foundFolders.sort {

            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }

        foundFiles.sort {

            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }

        return FolderScanResult(
            folders: foundFolders,
            files: foundFiles
        )
    }
}

// MARK: - Folder Tile

private struct FolderTile: View {

    let folderURL: URL

    let onOpen: () -> Void
    let onPlay: () -> Void

    @State private var artwork: NSImage?

    var body: some View {

        GeometryReader { geometry in

            let side =
                max(
                    1,
                    geometry.size.width
                )

            ZStack(
                alignment: .topTrailing
            ) {

                Button(
                    action: onOpen
                ) {

                    ZStack(
                        alignment: .bottomLeading
                    ) {

                        Color.black.opacity(
                            0.52
                        )

                        if let artwork {

                            Image(
                                nsImage: artwork
                            )
                            .resizable()
                            .aspectRatio(
                                contentMode: .fill
                            )
                            .frame(
                                width: side,
                                height: side
                            )
                            .clipped()

                        } else {

                            folderPlaceholder
                                .frame(
                                    width: side,
                                    height: side
                                )
                        }

                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(
                                    0.82
                                )
                            ],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(
                            width: side,
                            height: side
                        )

                        FolderTitleScroller(
                            title:
                                folderURL.lastPathComponent
                        )
                        .frame(
                            width: side
                        )
                    }
                    .frame(
                        width: side,
                        height: side
                    )
                    .clipped()
                    .overlay {

                        Rectangle()
                            .stroke(
                                Color.black.opacity(
                                    0.9
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(
                    FolderTileButtonStyle()
                )

                Button(
                    action: onPlay
                ) {

                    Text("▶")
                        .font(
                            .system(
                                size: 12,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.green.opacity(
                                0.95
                            )
                        )
                        .frame(
                            width: 28,
                            height: 28
                        )
                        .background(
                            Color.black.opacity(
                                0.72
                            )
                        )
                        .overlay {

                            Rectangle()
                                .stroke(
                                    Color.white.opacity(
                                        0.12
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(
                    FolderPlayButtonStyle()
                )
                .padding(6)
            }
        }
        .aspectRatio(
            1,
            contentMode: .fit
        )
        .clipped()
        .task {

            artwork =
                findArtwork(
                    in: folderURL
                )
        }
    }

    private var folderPlaceholder: some View {

        Image(
            systemName:
                "folder.fill"
        )
        .font(
            .system(
                size: 38,
                weight: .regular
            )
        )
        .foregroundStyle(
            Color.white.opacity(0.18)
        )
    }
}

// MARK: - Folder title

private struct FolderTitleScroller: View {

    let title: String

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {

        GeometryReader { geometry in

            let available =
                geometry.size.width - 16

            ZStack(
                alignment: .leading
            ) {

                Color.black.opacity(
                    0.58
                )

                HStack(
                    spacing: 0
                ) {

                    Text(title)
                        .font(
                            .system(
                                size: 12,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(
                                0.92
                            )
                        )
                        .lineLimit(1)
                        .fixedSize(
                            horizontal: true,
                            vertical: false
                        )
                        .background(
                            GeometryReader { proxy in

                                Color.clear
                                    .onAppear {

                                        textWidth =
                                            proxy.size.width
                                    }
                                    .onChange(
                                        of: proxy.size.width
                                    ) { newValue in

                                        textWidth =
                                            newValue
                                    }
                            }
                        )
                        .offset(
                            x:
                                8
                                + offset
                        )

                    Spacer(
                        minLength: 0
                    )
                }
                .clipped()
            }
            .onAppear {

                startScrolling(
                    available: available
                )
            }
            .onChange(
                of: textWidth
            ) { _ in

                startScrolling(
                    available: available
                )
            }
        }
        .frame(
            height: 27
        )
        .clipped()
    }

    private func startScrolling(
        available: CGFloat
    ) {

        guard textWidth > available
        else {

            offset = 0
            return
        }

        let distance =
            textWidth - available

        offset = 0

        withAnimation(
            .easeInOut(
                duration:
                    max(
                        2.0,
                        Double(distance) / 18.0
                    )
            )
            .repeatForever(
                autoreverses: true
            )
        ) {

            offset = -distance
        }
    }
}

// MARK: - Track Row

private struct TrackRow: View {

    let url: URL
    let isCurrent: Bool
    let onPlay: () -> Void

    var body: some View {

        Button(
            action: onPlay
        ) {

            HStack(spacing: 8) {

                Text(
                    isCurrent
                        ? "▶"
                        : "•"
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
                        ? Color.green.opacity(
                            0.95
                        )
                        : Color.white.opacity(
                            0.35
                        )
                )
                .frame(
                    width: 12
                )

                VStack(
                    alignment: .leading,
                    spacing: 1
                ) {

                    Text(
                        url.deletingPathExtension()
                            .lastPathComponent
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.90
                        )
                    )
                    .lineLimit(1)

                    Text(
                        AudioTrack(
                            url: url
                        ).artist
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .regular,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(
                            0.52
                        )
                    )
                    .lineLimit(1)
                }

                Spacer(
                    minLength: 4
                )

                Text(
                    durationText(
                        url: url
                    )
                )
                .font(
                    .system(
                        size: 10,
                        weight: .regular,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(
                        0.58
                    )
                )
            }
            .padding(
                .vertical,
                3
            )
            .padding(
                .horizontal,
                5
            )
            .background(
                isCurrent
                    ? Color.green.opacity(
                        0.07
                    )
                    : Color.clear
            )
        }
        .buttonStyle(
            TrackRowButtonStyle()
        )
    }

    private func durationText(
        url: URL
    ) -> String {

        guard
            let file =
                try? AVAudioFile(
                    forReading: url
                )
        else {
            return "--:--"
        }

        let duration =
            Double(
                file.length
            )
            / file.processingFormat.sampleRate

        let totalSeconds =
            max(
                0,
                Int(
                    duration
                )
            )

        return String(
            format: "%d:%02d",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}

// MARK: - Artwork

private func findArtwork(
    in folder: URL
) -> NSImage? {

    let fm =
        FileManager.default

    guard
        let enumerator =
            fm.enumerator(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [
                    .skipsHiddenFiles
                ]
            )
    else {
        return nil
    }

    for case let url as URL in enumerator {

        guard
            [
                "mp3",
                "m4a",
                "aac",
                "flac",
                "ogg"
            ]
            .contains(
                url.pathExtension.lowercased()
            )
        else {
            continue
        }

        let track =
            AudioTrack(
                url: url
            )

        if let data = track.artwork,
           let image =
                NSImage(
                    data: data
                )
        {
            return image
        }
    }

    return nil
}

// MARK: - Button Styles

private struct FolderTileButtonStyle:
    ButtonStyle {

    func makeBody(
        configuration: Configuration
    ) -> some View {

        configuration.label
            .brightness(
                configuration.isPressed
                    ? -0.04
                    : 0
            )
            .scaleEffect(
                configuration.isPressed
                    ? 0.985
                    : 1.0
            )
    }
}

private struct FolderPlayButtonStyle:
    ButtonStyle {

    func makeBody(
        configuration: Configuration
    ) -> some View {

        configuration.label
            .brightness(
                configuration.isPressed
                    ? -0.08
                    : 0
            )
            .scaleEffect(
                configuration.isPressed
                    ? 0.94
                    : 1.0
            )
    }
}

private struct TrackRowButtonStyle:
    ButtonStyle {

    func makeBody(
        configuration: Configuration
    ) -> some View {

        configuration.label
            .brightness(
                configuration.isPressed
                    ? -0.04
                    : 0
            )
    }
}