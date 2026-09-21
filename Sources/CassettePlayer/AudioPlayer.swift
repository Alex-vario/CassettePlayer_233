import Foundation
import AVFoundation
import Combine

final class AudioPlayer: NSObject, ObservableObject {

    // MARK: - Published state

    @Published private(set) var currentTrack: AudioTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var isMuted = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 1.0
    @Published private(set) var leftLevel: Float = 0
    @Published private(set) var rightLevel: Float = 0
    @Published private(set) var bitrate: Int = 0

    @Published var shuffle = false
    @Published var repeatMode = 0
    // 0 = off
    // 1 = repeat track
    // 2 = repeat playlist

    @Published private(set) var isEQEnabled = false

    // MARK: - Playlist

    @Published private(set) var playlist: [AudioTrack] = []
    private var currentIndex: Int = 0

// MARK: - Playlist management

func addToPlaylist(_ track: AudioTrack) {
    guard !playlist.contains(track) else {
        return
    }

    playlist.append(track)

    if currentTrack == nil {
        currentIndex = playlist.count - 1
        currentTrack = track
    }
}

func addToPlaylist(_ tracks: [AudioTrack]) {
    for track in tracks {
        addToPlaylist(track)
    }
}

func removeFromPlaylist(_ track: AudioTrack) {
    guard let index = playlist.firstIndex(of: track) else {
        return
    }

    let wasCurrent =
        currentTrack?.url == track.url

    playlist.remove(at: index)

    if playlist.isEmpty {
        currentIndex = 0
        playerNode.stop()
        stopTimer()

        currentTrack = nil
        currentFile = nil

        currentTime = 0
        duration = 0
        bitrate = 0

        pausedTime = 0
        playbackStartTime = nil
        isPlaying = false

        return
    }

    if index < currentIndex {
        currentIndex -= 1
    }

    currentIndex =
        min(
            currentIndex,
            playlist.count - 1
        )

    if wasCurrent {
        playerNode.stop()
        stopTimer()

        currentTrack = nil
        currentFile = nil

        currentTime = 0
        duration = 0
        bitrate = 0

        pausedTime = 0
        playbackStartTime = nil
        isPlaying = false

        currentTrack =
            playlist[currentIndex]
    }
}

    // MARK: - Audio engine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)

    private var currentFile: AVAudioFile?

    // MARK: - Playback timer

    private var playbackTimer: DispatchSourceTimer?
    private var playbackGeneration = 0

    // MARK: - Playback time

    private var playbackStartTime: Date?
    private var pausedTime: TimeInterval = 0

    // MARK: - EQ

    private let frequencies: [Float] = [
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
        18000
    ]

    private let eqDefaultsKey = "CassettePlayer.EQ.Gains"
    private let eqEnabledDefaultsKey = "CassettePlayer.EQ.Enabled"

    // MARK: - Init

    override init() {
        super.init()

        setupAudioEngine()
        loadEQSettings()
    }

    deinit {
        stopTimer()
        playerNode.stop()
        engine.stop()
    }

    // MARK: - Setup

    private func setupAudioEngine() {

        engine.attach(playerNode)
        engine.attach(eq)

        for (index, frequency) in frequencies.enumerated() {

            let filter = eq.bands[index]

            filter.filterType = .parametric
            filter.frequency = frequency
            filter.bandwidth = 1.0
            filter.gain = 0
            filter.bypass = true
        }

        engine.connect(
            playerNode,
            to: eq,
            format: nil
        )

        engine.connect(
            eq,
            to: engine.mainMixerNode,
            format: nil
        )

        engine.mainMixerNode.outputVolume = volume

        installLevelMeter()

        do {
            try engine.start()
        } catch {
            print(
                "Audio engine start error:",
                error
            )
        }
    }

    // MARK: - Level meter

    private func installLevelMeter() {

        let mixer = engine.mainMixerNode

        mixer.removeTap(
            onBus: 0
        )

        mixer.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: mixer.outputFormat(forBus: 0)
        ) { [weak self] buffer, _ in

            guard let self else {
                return
            }

            guard
                let channelData = buffer.floatChannelData
            else {
                return
            }

            let channelCount =
                Int(buffer.format.channelCount)

            let frameCount =
                Int(buffer.frameLength)

            guard frameCount > 0 else {
                return
            }

            var leftSum: Float = 0
            var rightSum: Float = 0

            for frame in 0..<frameCount {

                let left =
                    channelData[0][frame]

                leftSum += left * left

                if channelCount > 1 {

                    let right =
                        channelData[1][frame]

                    rightSum += right * right

                } else {

                    rightSum += left * left
                }
            }

            let leftRMS =
                sqrt(
                    leftSum /
                    Float(frameCount)
                )

            let rightRMS =
                sqrt(
                    rightSum /
                    Float(frameCount)
                )

            DispatchQueue.main.async {

                self.leftLevel =
                    min(
                        1,
                        leftRMS * 1.2
                    )

                self.rightLevel =
                    min(
                        1,
                        rightRMS * 1.2
                    )
            }
        }
    }

    // MARK: - Playlist

    func setPlaylist(_ tracks: [AudioTrack]) {

        playlist = tracks

        if playlist.isEmpty {

            currentIndex = 0
            currentTrack = nil
            currentFile = nil

            duration = 0
            currentTime = 0
            pausedTime = 0
            playbackStartTime = nil

            isPlaying = false

            return
        }

        if currentIndex >= playlist.count {
            currentIndex = 0
        }

        if currentTrack == nil {
            currentTrack = playlist[currentIndex]
        }
    }



    // MARK: - Playback

    func play(_ track: AudioTrack) {

        guard let index = playlist.firstIndex(of: track)
        else {

            playlist = [track]
            currentIndex = 0

            startTrack(track)

            return
        }

        currentIndex = index

        startTrack(track)
    }

    private func startTrack(_ track: AudioTrack) {

        playbackGeneration += 1
        let generation = playbackGeneration

        playerNode.stop()
        stopTimer()

        do {

            let file =
                try AVAudioFile(
                    forReading: track.url
                )

            currentFile = file
            currentTrack = track
            bitrate = 0

            loadBitrate(
                for: track.url
            )

            let sampleRate =
                file.processingFormat.sampleRate

            if sampleRate > 0 {

                duration =
                    Double(file.length) / sampleRate

            } else {

                duration = 0
            }

            currentTime = 0
            pausedTime = 0

            playbackStartTime = Date()

            print(
                "Playing:",
                track.url.lastPathComponent
            )

            print(
                "Frames:",
                file.length,
                "Sample rate:",
                sampleRate,
                "Duration:",
                duration
            )

            playerNode.scheduleFile(
                file,
                at: nil
            ) { [weak self] in

                DispatchQueue.main.async {

                    guard let self
                    else {
                        return
                    }

                    guard self.playbackGeneration == generation
                    else {
                        return
                    }

                    self.trackFinished()
                }
            }

            if !engine.isRunning {

                try engine.start()
            }

            playerNode.play()

            isPlaying = true

            startTimer()

        } catch {

            print(
                "Cannot play:",
                error
            )

            isPlaying = false
        }
    }

private func loadBitrate(
    for url: URL
) {

    Task {

        let asset =
            AVURLAsset(
                url: url
            )

        var calculatedBitrate: Int = 0

        if
            let tracks =
                try? await asset.load(
                    .tracks
                ),
            let audioTrack =
                tracks.first(
                    where: {
                        $0.mediaType == .audio
                    }
                ),
            let dataRate =
                try? await audioTrack.load(
                    .estimatedDataRate
                ),
            dataRate > 0
        {

            calculatedBitrate =
                Int(
                    (dataRate / 1000)
                        .rounded()
                )
        }

        if calculatedBitrate <= 0 {

            if
                let duration =
                    try? await asset.load(
                        .duration
                    )
            {

                let seconds =
                    duration.seconds

                if seconds > 0 {

                    do {

                        let attributes =
                            try FileManager.default.attributesOfItem(
                                atPath: url.path
                            )

                        if let fileSize =
                            attributes[
                                .size
                            ] as? NSNumber
                        {

                            let bits =
                                fileSize.doubleValue * 8.0

                            calculatedBitrate =
                                Int(
                                    (bits / seconds / 1000.0)
                                        .rounded()
                                )
                        }

                    } catch {

                        print(
                            "Cannot determine file size:",
                            error
                        )
                    }
                }
            }
        }

        let resultBitrate =
            calculatedBitrate

        await MainActor.run {

            guard
                let track =
                    self.currentTrack
            else {
                return
            }

            guard
                track.url == url
            else {
                return
            }

            self.bitrate =
                resultBitrate
        }
    }
}
    func togglePlayPause() {

        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    // MARK: - Pause

    func pause() {

        updateCurrentTime()

        playerNode.pause()

        pausedTime = currentTime
        playbackStartTime = nil

        isPlaying = false

        stopTimer()
    }

    // MARK: - Resume

    private func resume() {

        guard let track = currentTrack
        else {
            return
        }

        if currentTime == 0 {

            startTrack(track)

            return
        }

        if !engine.isRunning {

            do {
                try engine.start()
            } catch {

                print(
                    "Audio engine restart error:",
                    error
                )

                return
            }
        }

        playbackStartTime = Date()

        playerNode.play()

        isPlaying = true

        startTimer()
    }

    // MARK: - Next

    func next() {

        guard !playlist.isEmpty
        else {
            return
        }

        if shuffle {

            if playlist.count > 1 {

                var nextIndex =
                    currentIndex

                while nextIndex == currentIndex {

                    nextIndex =
                        Int.random(
                            in: 0..<playlist.count
                        )
                }

                currentIndex =
                    nextIndex
            }

        } else {

            currentIndex += 1

            if currentIndex >= playlist.count {

                if repeatMode == 2 {

                    currentIndex = 0

                } else {

                    currentIndex =
                        playlist.count - 1

                    stop()

                    return
                }
            }
        }

        startTrack(
            playlist[currentIndex]
        )
    }

    // MARK: - Previous

    func previous() {

        guard !playlist.isEmpty
        else {
            return
        }

        if currentTime > 3 {

            seek(to: 0)

            return
        }

        currentIndex -= 1

        if currentIndex < 0 {

            if repeatMode == 2 {

                currentIndex =
                    playlist.count - 1

            } else {

                currentIndex = 0
            }
        }

        startTrack(
            playlist[currentIndex]
        )
    }

    // MARK: - Stop

    func stop() {

        playbackGeneration += 1

        playerNode.stop()

        isPlaying = false

        currentTime = 0
        pausedTime = 0

        playbackStartTime = nil

        stopTimer()

        if let file = currentFile {

            let sampleRate =
                file.processingFormat.sampleRate

            if sampleRate > 0 {

                duration =
                    Double(file.length) / sampleRate
            }
        }
    }

    // MARK: - Track finished

    private func trackFinished() {

        guard !playlist.isEmpty
        else {

            isPlaying = false

            stopTimer()

            return
        }

        DispatchQueue.main.async { [weak self] in

            guard let self
            else {
                return
            }

            self.playbackStartTime = nil

            self.stopTimer()

            switch self.repeatMode {

            case 1:

                if let track =
                    self.currentTrack {

                    self.startTrack(track)
                }

            default:

                self.next()
            }
        }
    }

    // MARK: - Seek

    func seek(to time: TimeInterval) {

        print(
            "SEEK REQUEST:",
            time
        )

        guard let file = currentFile
        else {
            return
        }

        let wasPlaying = isPlaying

        let clamped =
            max(
                0,
                min(
                    time,
                    duration
                )
            )

        let sampleRate =
            file.processingFormat.sampleRate

        guard sampleRate > 0
        else {
            return
        }

        let sampleTime =
            AVAudioFramePosition(
                clamped * sampleRate
            )

        let remainingFrames =
            file.length - sampleTime

        guard remainingFrames > 0
        else {
            stop()
            return
        }

        let frameCount =
            AVAudioFrameCount(
                min(
                    Int64(remainingFrames),
                    Int64(UInt32.max)
                )
            )

        playbackGeneration += 1
        let generation = playbackGeneration

        playerNode.stop()

        currentTime = clamped
        pausedTime = clamped

        playerNode.scheduleSegment(
            file,
            startingFrame: sampleTime,
            frameCount: frameCount,
            at: nil
        ) { [weak self] in

            DispatchQueue.main.async {

                guard let self
                else {
                    return
                }

                guard self.playbackGeneration == generation
                else {
                    return
                }

                self.trackFinished()
            }
        }

        if wasPlaying {

            playbackStartTime = Date()

            isPlaying = true

            playerNode.play()

            startTimer()

        } else {

            playbackStartTime = nil

            isPlaying = false

            stopTimer()
        }
    }

    // MARK: - Volume

    func setVolume(_ value: Float) {

        let clamped =
            min(
                1,
                max(
                    0,
                    value
                )
            )

        volume = clamped

        if isMuted {
            isMuted = false
        }

        playerNode.volume = clamped
    }

    func toggleMute() {

        isMuted.toggle()

        if isMuted {

            playerNode.volume = 0

        } else {

            playerNode.volume = volume
        }
    }

    // MARK: - Playback timer

    private func startTimer() {

        stopTimer()

        let timer =
            DispatchSource.makeTimerSource(
                queue: .main
            )

        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(50)
        )

        timer.setEventHandler { [weak self] in

            guard let self
            else {
                return
            }

            guard self.isPlaying
            else {
                return
            }

            self.updateCurrentTime()
        }

        playbackTimer = timer

        timer.resume()
    }

    private func stopTimer() {

        playbackTimer?.setEventHandler {}
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    private func updateCurrentTime() {

        guard isPlaying
        else {
            return
        }

        guard let start =
            playbackStartTime
        else {
            return
        }

        let elapsed =
            Date().timeIntervalSince(start)

        let newTime =
            pausedTime + elapsed

        currentTime =
            min(
                duration,
                max(
                    0,
                    newTime
                )
            )

        print(
            "TIME:",
            currentTime
        )
    }

    // MARK: - EQ

    func setEQGain(
        band: Int,
        gain: Float
    ) {

        guard band >= 0,
              band < 10
        else {
            return
        }

        let clampedGain =
            max(
                -15,
                min(
                    gain,
                    15
                )
            )

        eq.bands[band].gain =
            clampedGain

        saveEQSettings()
    }

    func setEQEnabled(
        _ enabled: Bool
    ) {

        isEQEnabled = enabled
        eqEnabledDefaultsKeySave(enabled)

        for band in eq.bands {

            band.bypass =
                !enabled
        }
    }

    // MARK: - EQ persistence

    var savedEQValues: [Float] {

        if let saved =
            UserDefaults.standard.array(
                forKey: eqDefaultsKey
            ) as? [NSNumber] {

            let values =
                saved.prefix(10).map {
                    $0.floatValue
                }

            if values.count == 10 {
                return values
            }
        }

        return Array(
            repeating: 0,
            count: 10
        )
    }

    private func loadEQSettings() {

        let values =
            savedEQValues

        for index in 0..<10 {

            eq.bands[index].gain =
                values[index]
        }

        let enabled =
            UserDefaults.standard.bool(
                forKey: eqEnabledDefaultsKey
            )

        isEQEnabled = enabled

        for band in eq.bands {

            band.bypass =
                !enabled
        }
    }

    private func saveEQSettings() {

        let values =
            (0..<10).map {
                NSNumber(
                    value: eq.bands[$0].gain
                )
            }

        UserDefaults.standard.set(
            values,
            forKey: eqDefaultsKey
        )
    }

    private func eqEnabledDefaultsKeySave(
        _ enabled: Bool
    ) {

        UserDefaults.standard.set(
            enabled,
            forKey: eqEnabledDefaultsKey
        )
    }

    // MARK: - Clear

    func clear() {

        playbackGeneration += 1

        playerNode.stop()

        stopTimer()

        playlist.removeAll()

        currentIndex = 0

        currentTrack = nil
        currentFile = nil

        currentTime = 0
        duration = 0

        bitrate = 0

        pausedTime = 0
        playbackStartTime = nil

        isPlaying = false
    }
}