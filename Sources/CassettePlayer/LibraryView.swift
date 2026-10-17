import SwiftUI
import AppKit
import AVFoundation
import CryptoKit

// MARK: - Persistent Library Index

/// The disk cache stores metadata, not copies of the audio files.
/// It is always written to the same path and atomically replaced.
private struct CachedLibraryTrack: Codable {
    let path: String
    let artist: String
    let album: String
    let bitrate: Int
    let artworkKey: String?

    init(track: AudioTrack, artworkKey: String?) {
        path = track.url.path
        artist = track.artist
        album = track.album
        bitrate = track.bitrate
        self.artworkKey = artworkKey
    }

    func makeTrack(artwork: Data?) -> AudioTrack {
        var track = AudioTrack(url: URL(fileURLWithPath: path))
        track.artist = artist
        track.album = album
        track.bitrate = bitrate
        track.artwork = artwork
        return track
    }
}

private struct CachedLibraryIndex: Codable {
    let version: Int
    let rootPath: String
    let folderPaths: [String]
    let tracks: [CachedLibraryTrack]
    let artworkByKey: [String: Data]

    var snapshot: LibraryIndexSnapshot {
        LibraryIndexSnapshot(
            rootPath: rootPath,
            folders: folderPaths.map { URL(fileURLWithPath: $0) },
            tracks: tracks.map { $0.makeTrack(artwork: $0.artworkKey.flatMap { artworkByKey[$0] }) }
        )
    }

    init(root: URL, folders: [URL], tracks: [AudioTrack]) {
        version = 1
        rootPath = root.standardizedFileURL.path
        folderPaths = folders.map { $0.path }

        var uniqueArtwork: [String: Data] = [:]
        self.tracks = tracks.map { track in
            let key: String?
            if let artwork = track.artwork {
                let digest = SHA256.hash(data: artwork)
                let digestKey = digest.map { String(format: "%02x", $0) }.joined()
                uniqueArtwork[digestKey] = artwork
                key = digestKey
            } else {
                key = nil
            }
            return CachedLibraryTrack(track: track, artworkKey: key)
        }
        artworkByKey = uniqueArtwork
    }
}

private struct LibraryIndexSnapshot {
    let rootPath: String
    let folders: [URL]
    let tracks: [AudioTrack]

    var rootFiles: [URL] {
        tracks.map(\.url).filter {
            $0.deletingLastPathComponent().standardizedFileURL.path == rootPath
        }
    }
}

/// One shared actor prevents search and the Artists view from starting
/// separate scans. The cache is a single JSON file in Application Support.
private actor LibraryIndexStore {
    static let shared = LibraryIndexStore()

    private var cachedIndex: CachedLibraryIndex?
    private var buildTask: Task<CachedLibraryIndex, Never>?
    private var buildRootPath: String?
    private var buildGeneration = UUID()

    private var cacheURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support
            .appendingPathComponent("CassettePlayer", isDirectory: true)
            .appendingPathComponent("LibraryIndex.json", isDirectory: false)
    }

    func load(root: URL, forceRefresh: Bool = false) async -> LibraryIndexSnapshot {
        let rootPath = root.standardizedFileURL.path

        if !forceRefresh, let cachedIndex, cachedIndex.rootPath == rootPath {
            return cachedIndex.snapshot
        }

        if !forceRefresh,
           let data = try? Data(contentsOf: cacheURL),
           let diskIndex = try? JSONDecoder().decode(CachedLibraryIndex.self, from: data),
           diskIndex.version == 1,
           diskIndex.rootPath == rootPath {
            cachedIndex = diskIndex
            return diskIndex.snapshot
        }

        if !forceRefresh,
           buildRootPath == rootPath,
           let buildTask {
            let generation = buildGeneration
            let result = await buildTask.value
            if generation == buildGeneration, result.rootPath == rootPath {
                cachedIndex = result
                persist(result)
            }
            return result.snapshot
        }

        // A manual refresh supersedes an in-progress build. Only the newest
        // generation is allowed to replace the on-disk index.
        buildGeneration = UUID()
        let generation = buildGeneration
        buildRootPath = rootPath
        let task = Task.detached(priority: .userInitiated) {
            await Self.build(root: root)
        }
        buildTask = task

        let result = await task.value
        if generation == buildGeneration {
            cachedIndex = result
            persist(result)
            buildTask = nil
            buildRootPath = nil
        }
        return result.snapshot
    }

    private func persist(_ index: CachedLibraryIndex) {
        let destination = cacheURL
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(index)
            // .atomic writes a temporary file and replaces the same cache file.
            try data.write(to: destination, options: .atomic)
        } catch {
            // The in-memory index remains usable if disk caching fails.
            NSLog("CassettePlayer: unable to save library index: %@", error.localizedDescription)
        }
    }

    private nonisolated static func build(root: URL) async -> CachedLibraryIndex {
        let fm = FileManager.default
        let audioExtensions: Set<String> = [
            "mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus"
        ]
        var folders: [URL] = []
        var audioURLs: [URL] = []

        func walk(_ directory: URL) {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    folders.append(item)
                    walk(item)
                } else if values?.isRegularFile == true,
                          audioExtensions.contains(item.pathExtension.lowercased()) {
                    audioURLs.append(item)
                }
            }
        }

        walk(root)
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        audioURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let tracks = await AudioTrack.loadAll(from: audioURLs)
        return CachedLibraryIndex(root: root, folders: folders, tracks: tracks)
    }
}


struct LibraryView: View {

    @ObservedObject var audio: AudioPlayer

    let onClose: () -> Void

    @State private var currentFolder: URL?
    @State private var folders: [URL] = []
    @State private var rootFiles: [URL] = []
    @State private var selectedRoot: URL?
    @State private var isLoading = false
    @State private var isContentVisible = false

    @State private var libraryMode = 0
    @State private var artists: [ArtistGroup] = []
    @State private var selectedArtist: ArtistGroup?
    @State private var artistFilterText = ""

    @State private var searchText = ""
    @State private var searchFolders: [URL] = []
    @State private var searchTracks: [AudioTrack] = []
    @State private var isSearchIndexLoading = false
    @State private var searchIndexRootPath: String?

    @AppStorage("CassettePlayer.Library.TileSize")
    private var libraryTileSize = 120.0

    private let rootDefaultsKey =
        "CassettePlayer.Library.Root"

    var body: some View {

        ZStack(alignment: .top) {

            PanelMaterials.mainPanel

            if isContentVisible {
                VStack(spacing: 0) {
                    header

                    Divider()
                        .background(
                            Color.black.opacity(0.7)
                        )

                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            .easeOut(duration: 0.14),
            value: isContentVisible
        )
        .task {
            do {
                try await Task.sleep(nanoseconds: 460_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            isContentVisible = true
            loadSavedRoot()
        }
        .onChange(of: searchText) { newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadSearchIndexIfNeeded()
            }
        }
        .onChange(of: selectedRoot) { _ in
            searchIndexRootPath = nil
            searchFolders = []
            searchTracks = []
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadSearchIndexIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 8) {

            modeButton(
                title: "ПАПКИ",
                active: libraryMode == 0
            ) {

                libraryMode = 0
                selectedArtist = nil

                if let folder = currentFolder {
                    reloadFolder(folder)
                } else if let root = selectedRoot {
                    currentFolder = root
                    reloadFolder(root)
                }
            }

            modeButton(
                title: "ИСПОЛНИТЕЛИ",
                active: libraryMode == 1
            ) {

                libraryMode = 1
                selectedArtist = nil
                loadArtists()
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

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))

                TextField("Поиск по библиотеке", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help("Очистить поиск")
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 150, maxWidth: 260)
            .frame(height: 25)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .help("Поиск по папкам, исполнителям, альбомам и трекам")

            Slider(
                value: $libraryTileSize,
                in: 72...120
            )
            .frame(width: 100)
            .help("Размер плиток")
            .accessibilityLabel("Размер плиток библиотеки")

            Button {
                refreshLibraryIndex()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Обновить библиотеку: пересканировать и заменить индекс")

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
            .padding(.trailing, 8)

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

    // MARK: - Breadcrumbs

    private var breadcrumbInline: some View {

        HStack(spacing: 5) {

            if libraryMode == 0 {

                folderBreadcrumbs

            } else {

                artistBreadcrumbs
            }
        }
        .lineLimit(1)
        .clipped()
    }

    private var folderBreadcrumbs: some View {

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
                        currentFolder == root
                            ? Color.white.opacity(0.92)
                            : Color.white.opacity(0.60)
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
                                Color.white.opacity(0.78)
                            )
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var artistBreadcrumbs: some View {

        HStack(spacing: 5) {

            if selectedArtist != nil {

                Button {

                    selectedArtist = nil

                } label: {

                    Text("ИСПОЛНИТЕЛИ")
                        .font(
                            .system(
                                size: 10,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.white.opacity(0.60)
                        )
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

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

                Text(
                    selectedArtist?.name ?? ""
                )
                .font(
                    .system(
                        size: 10,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.white.opacity(0.92)
                )
                .lineLimit(1)

            } else {

                Text("ИСПОЛНИТЕЛИ")
                    .font(
                        .system(
                            size: 10,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.white.opacity(0.92)
                    )
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Content

    private var content: some View {

        Group {

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResultsContent
            } else if isLoading {

                ProgressView()
                    .controlSize(.small)

            } else if libraryMode == 0 {

                folderContent

            } else {

                artistContent
            }
        }
    }

    // MARK: - Search

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingSearchFolders: [URL] {
        guard !normalizedSearchQuery.isEmpty else { return [] }
        return searchFolders
            .filter { $0.lastPathComponent.localizedCaseInsensitiveContains(normalizedSearchQuery) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private var matchingSearchArtists: [ArtistGroup] {
        guard !normalizedSearchQuery.isEmpty else { return [] }
        let grouped = Dictionary(grouping: searchTracks.filter { track in
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && name.localizedCaseInsensitiveContains(normalizedSearchQuery)
        }) { $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) }

        return grouped.map { name, tracks in
            ArtistGroup(
                name: name,
                tracks: tracks.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var matchingSearchTracks: [AudioTrack] {
        guard !normalizedSearchQuery.isEmpty else { return [] }
        return searchTracks
            .filter {
                $0.title.localizedCaseInsensitiveContains(normalizedSearchQuery)
                    || $0.album.localizedCaseInsensitiveContains(normalizedSearchQuery)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private var searchResultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isSearchIndexLoading {
                    ProgressView("Индексирую библиотеку…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else if searchIndexRootPath == nil {
                    Text("Сначала выберите папку библиотеки")
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else if matchingSearchFolders.isEmpty
                            && matchingSearchArtists.isEmpty
                            && matchingSearchTracks.isEmpty {
                    Text("Ничего не найдено")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    if !matchingSearchFolders.isEmpty {
                        searchSectionTitle("ПАПКИ", count: matchingSearchFolders.count)
                        ForEach(matchingSearchFolders, id: \.standardizedFileURL.path) { folder in
                            Button {
                                searchText = ""
                                playFolder(folder)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.white.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.lastPathComponent)
                                            .foregroundStyle(Color.white.opacity(0.92))
                                        Text(folder.deletingLastPathComponent().lastPathComponent)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !matchingSearchArtists.isEmpty {
                        searchSectionTitle("ИСПОЛНИТЕЛИ", count: matchingSearchArtists.count)
                        ForEach(matchingSearchArtists) { artist in
                            Button {
                                searchText = ""
                                playArtist(artist)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Color.white.opacity(0.7))
                                    Text(artist.name)
                                        .foregroundStyle(Color.white.opacity(0.92))
                                    Spacer()
                                    Text("\(artist.tracks.count) тр.")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !matchingSearchTracks.isEmpty {
                        searchSectionTitle("ТРЕКИ", count: matchingSearchTracks.count)
                        ForEach(matchingSearchTracks) { track in
                            TrackRow(
                                url: track.url,
                                isCurrent: audio.currentTrack?.url == track.url,
                                onPlay: {
                                    audio.setPlaylist(matchingSearchTracks)
                                    audio.play(track)
                                    onClose()
                                }
                            )
                        }
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private func searchSectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.top, 3)
    }

    private func loadSearchIndexIfNeeded() {
        guard let root = selectedRoot else { return }
        guard searchIndexRootPath != root.path, !isSearchIndexLoading else { return }

        isSearchIndexLoading = true

        Task {
            let index = await LibraryIndexStore.shared.load(root: root)

            guard selectedRoot?.standardizedFileURL.path == index.rootPath else {
                isSearchIndexLoading = false
                searchIndexRootPath = nil
                if !normalizedSearchQuery.isEmpty {
                    loadSearchIndexIfNeeded()
                }
                return
            }

            searchIndexRootPath = index.rootPath
            searchFolders = index.folders
            searchTracks = index.tracks
            artists = Self.makeArtistGroups(from: index.tracks)
            isSearchIndexLoading = false
        }
    }

    // MARK: - Folder Content

    private var folderContent: some View {

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

    private var folderGrid: some View {

        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: CGFloat(libraryTileSize),
                        maximum: CGFloat(libraryTileSize)
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

    // MARK: - Artist Content

    private var artistContent: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 10
            ) {

                if let artist = selectedArtist {

                    artistTracksSection(
                        artist
                    )

                } else {

                    artistFilterBar

                    if filteredArtists.isEmpty {
                        Text(
                            artistFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "В библиотеке пока нет исполнителей"
                                : "Исполнители не найдены"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        artistGrid
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private var normalizedArtistFilter: String {
        artistFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredArtists: [ArtistGroup] {
        guard !normalizedArtistFilter.isEmpty else {
            return artists
        }

        return artists.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedArtistFilter)
        }
    }

    private var artistFilterBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))

            TextField("Фильтр исполнителей…", text: $artistFilterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.92))
                .disableAutocorrection(true)

            if !artistFilterText.isEmpty {
                Button {
                    artistFilterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Очистить фильтр исполнителей")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 280, height: 30, alignment: .leading)
        .background(
            Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .help("Фильтрует только список исполнителей")
    }

    private var artistGrid: some View {

        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: CGFloat(libraryTileSize),
                        maximum: CGFloat(libraryTileSize)
                    ),
                    spacing: 10
                )
            ],
            spacing: 10
        ) {

            ForEach(
                Array(filteredArtists.enumerated()),
                id: \.element.id
            ) { index, artist in

                ArtistTile(
                    artist: artist,
                    artworkRevealDelay: Double(index % 7) * 0.04,
                    onOpen: {

                        selectedArtist = artist

                    },
                    onPlay: {

                        playArtist(
                            artist
                        )
                    }
                )
            }
        }
    }

    private func artistTracksSection(
        _ artist: ArtistGroup
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            HStack {

                Text(
                    artist.name
                )
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
                    "\(artist.tracks.count)"
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
                artist.tracks
            ) { track in

                TrackRow(
                    url: track.url,
                    isCurrent:
                        audio.currentTrack?.url == track.url,
                    onPlay: {
                        playArtistFile(
                            track,
                            artist: artist
                        )
                    }
                )
            }
        }
    }

    // MARK: - Root Files

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

    // MARK: - Folder Navigation

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

    // MARK: - Folder Playback

    private func playFolder(
        _ folder: URL
    ) {
        Task {
            let tracks = await collectAudioTracks(in: folder)

            guard !tracks.isEmpty else {
                return
            }

            audio.setPlaylist(tracks)
            audio.play(tracks[0])
            onClose()
        }
    }

    private func playFile(
        _ url: URL
    ) {
        Task {
            var tracks = await AudioTrack.loadAll(from: rootFiles)
            let selectedTrack: AudioTrack

            if let existingTrack = tracks.first(where: { $0.url == url }) {
                selectedTrack = existingTrack
            } else {
                selectedTrack = await AudioTrack.load(from: url)
                tracks.append(selectedTrack)
            }

            audio.setPlaylist(tracks)
            audio.play(selectedTrack)
            onClose()
        }
    }

    // MARK: - Artist Loading

    private func loadArtists() {
        guard let root = selectedRoot else {
            artists = []
            return
        }

        isLoading = true
        Task {
            let index = await LibraryIndexStore.shared.load(root: root)
            guard selectedRoot?.standardizedFileURL.path == index.rootPath else {
                isLoading = false
                return
            }
            artists = Self.makeArtistGroups(from: index.tracks)
            isLoading = false
        }
    }

    private nonisolated static func makeArtistGroups(from tracks: [AudioTrack]) -> [ArtistGroup] {
        var grouped: [String: [AudioTrack]] = [:]
        var displayNames: [String: String] = [:]

        for track in tracks {
            for rawName in track.catalogueArtists {
                let (key, displayName) = normalizedCatalogueArtist(rawName)
                if !(grouped[key] ?? []).contains(where: { $0.url == track.url }) {
                    grouped[key, default: []].append(track)
                }
                displayNames[key] = displayName
            }
        }

        return grouped.map { key, tracks in
            ArtistGroup(
                name: displayNames[key] ?? key,
                tracks: tracks.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Canonicalizes known catalogue variants without correcting arbitrary typos.
    /// Trailing release notes in brackets/parentheses affect grouping only, not metadata.
    private nonisolated static func normalizedCatalogueArtist(_ rawName: String) -> (key: String, displayName: String) {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixPatterns = [#"\s*\[[^\]]*\]\s*$"#, #"\s*\([^\)]*\)\s*$"#]

        for pattern in suffixPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let aliases: [String: String] = [
            "anathema": "Anathema",
            "ananthema": "Anathema",
            "ananthema сборник": "Anathema",
            "anathema сборник": "Anathema"
        ]
        let displayName = aliases[folded] ?? name
        let canonicalKey = displayName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        return (canonicalKey, displayName.isEmpty ? rawName : displayName)
    }

    private func refreshLibraryIndex() {
        guard let root = selectedRoot else {
            chooseLibraryFolder()
            return
        }

        isLoading = true
        isSearchIndexLoading = !normalizedSearchQuery.isEmpty

        Task {
            let index = await LibraryIndexStore.shared.load(root: root, forceRefresh: true)
            guard selectedRoot?.standardizedFileURL.path == index.rootPath else {
                isLoading = false
                isSearchIndexLoading = false
                return
            }

            searchIndexRootPath = index.rootPath
            searchFolders = index.folders
            searchTracks = index.tracks
            artists = Self.makeArtistGroups(from: index.tracks)

            let visibleFolder = currentFolder ?? root
            let folderResult = Self.scanFolder(visibleFolder)
            folders = folderResult.folders
            rootFiles = folderResult.files

            isLoading = false
            isSearchIndexLoading = false
        }
    }

    private func playArtist(
        _ artist: ArtistGroup
    ) {

        guard !artist.tracks.isEmpty else {
            return
        }

        audio.setPlaylist(
            artist.tracks
        )

        audio.play(
            artist.tracks[0]
        )

        onClose()
    }

    private func playArtistFile(
        _ track: AudioTrack,
        artist: ArtistGroup
    ) {

        audio.setPlaylist(
            artist.tracks
        )

        audio.play(
            track
        )

        onClose()
    }

    // MARK: - Recursive Audio Collection

    private func collectAudioTracks(
        in folder: URL
    ) async -> [AudioTrack] {

        await Self.collectAudioTracksStatic(
            in: folder
        )
    }

    private nonisolated static func collectAudioTracksStatic(
        in folder: URL
    ) async -> [AudioTrack] {

        let fm =
            FileManager.default

        var urls: [URL] = []

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

                    urls.append(item)
                }
            }
        }

        walk(
            folder
        )

        return await AudioTrack.loadAll(from: urls)
    }

    // MARK: - Root Chooser

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

        currentFolder = url
        selectedArtist = nil

        if libraryMode == 0 {
            openFolder(url)
        } else {
            loadArtists()
        }

        // Build or load the single cache for the newly selected root.
        Task {
            let index = await LibraryIndexStore.shared.load(root: url)
            guard selectedRoot?.standardizedFileURL.path == index.rootPath else { return }
            searchIndexRootPath = index.rootPath
            searchFolders = index.folders
            searchTracks = index.tracks
            artists = Self.makeArtistGroups(from: index.tracks)
        }
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

        if libraryMode == 0 {
            openFolder(url)
        } else {
            loadArtists()
        }

        // Load the saved index immediately on startup; scan only if no
        // compatible cache exists yet.
        Task {
            let index = await LibraryIndexStore.shared.load(root: url)
            guard selectedRoot?.standardizedFileURL.path == index.rootPath else { return }
            searchIndexRootPath = index.rootPath
            searchFolders = index.folders
            searchTracks = index.tracks
            artists = Self.makeArtistGroups(from: index.tracks)
        }
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

        var foundFolders:
            [URL] = []

        var foundFiles:
            [URL] = []

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

// MARK: - Artist Group

private struct ArtistGroup:
    Identifiable,
    Hashable {

    let id = UUID()
    let name: String
    let tracks: [AudioTrack]

    var artwork: NSImage? {

        for track in tracks {

            if let data = track.artwork,
               let image = NSImage(data: data)
            {
                return image
            }
        }

        return nil
    }

    static func == (
        lhs: ArtistGroup,
        rhs: ArtistGroup
    ) -> Bool {

        lhs.name == rhs.name
        && lhs.tracks.map(\.url)
            == rhs.tracks.map(\.url)
    }

    func hash(
        into hasher: inout Hasher
    ) {

        hasher.combine(name)

        for track in tracks {

            hasher.combine(track.url)
        }
    }
}

 // MARK: - Artist Tile

private struct ArtistTile: View {

    let artist: ArtistGroup
    let artworkRevealDelay: Double

    let onOpen: () -> Void
    let onPlay: () -> Void

    @State private var artworkVisible = false

    var body: some View {

        ZStack(
            alignment: .topTrailing
        ) {

            artistMainButton

            artistPlayButton
                .padding(6)
        }
        .aspectRatio(
            1,
            contentMode: .fit
        )
    }

    private var artistMainButton: some View {

        Button(
            action: onOpen
        ) {

            ZStack(
                alignment: .bottomLeading
            ) {

                artistArtwork

                artistBottomLabel
            }
            .contentShape(
                Rectangle()
            )
            .overlay {

                Rectangle()
                    .stroke(
                        Color.black.opacity(0.9),
                        lineWidth: 1
                    )
            }
            .clipped()
        }
        .buttonStyle(
            FolderTileButtonStyle()
        )
    }

    private var artistArtwork: some View {

        GeometryReader { geometry in

            let side = max(
                1,
                geometry.size.width
            )

            ZStack {

                Color.black.opacity(
                    0.52
                )

                if let artwork =
                    artist.artwork {

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
                    .opacity(artworkVisible ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.24)
                            .delay(artworkRevealDelay),
                        value: artworkVisible
                    )
                    .onAppear {
                        artworkVisible = true
                    }

                } else {

                    artistPlaceholder
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
            }
            .frame(
                width: side,
                height: side
            )
            .clipped()
        }
    }

    private var artistBottomLabel: some View {

        Text(
            artist.name
        )
        .font(
            .system(
                size: 12,
                weight: .medium,
                design: .monospaced
            )
        )
        .foregroundStyle(
            Color.white.opacity(0.92)
        )
        .lineLimit(1)
        .padding(
            .horizontal,
            8
        )
        .frame(
            height: 27,
            alignment: .leading
        )
        .frame(
            maxWidth: .infinity
        )
        .background(
            Color.black.opacity(0.58)
        )
    }

    private var artistPlayButton: some View {

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
                    Color.green.opacity(0.95)
                )
                .frame(
                    width: 28,
                    height: 28
                )
                .background(
                    Color.black.opacity(0.72)
                )
                .overlay {

                    Rectangle()
                        .stroke(
                            Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                }
                .contentShape(
                    Rectangle()
                )
        }
        .buttonStyle(
            FolderPlayButtonStyle()
        )
    }

    private var artistPlaceholder: some View {

        Image(
            systemName:
                "person.2.fill"
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
            artwork = await findArtwork(in: folderURL)
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

// MARK: - Folder Title

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

    @State private var artist = ""

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

                    Text(artist)
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
        .task {
            artist = (await AudioTrack.load(from: url)).artist
        }
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
) async -> NSImage? {

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

    while let url = enumerator.nextObject() as? URL {

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

        let track = await AudioTrack.load(from: url)

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
